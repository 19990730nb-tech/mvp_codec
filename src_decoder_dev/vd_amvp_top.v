// -----------------------------------------------------------------------------
// Decoder-native AMVP wrapper.
// It captures parsed syntax, collects candidates that may arrive on different
// cycles, selects cand0/cand1 from mvp_l0_flag (cand0 for AVC median mode), and
// reconstructs the final MV by adding the parsed MVD.
// -----------------------------------------------------------------------------
`include "ve_defines.v"

module vd_amvp_top #(
    parameter NUM_REF      = 2,
    parameter MVP_SCALE_EN = 0,
    parameter FSMW         = 5
)(
    //==========================================================
    // Clock / Reset
    //==========================================================
    input  wire                     clk_vd,
    input  wire                     vd_rst_z,

    //==========================================================
    // Decoder control / parsed syntax
    //==========================================================
    input  wire                     amvp_start,
    input  wire                     slice_start,
    input  wire                     mvp_l0_flag,
    input  wire signed [15:0]       parsed_mvd_x,
    input  wire signed [15:0]       parsed_mvd_y,

    //==========================================================
    // Sequence / slice configuration
    //==========================================================
    input  wire                     reg_tmp_mvp_flag,
    input  wire                     reg_avc_mode,
    input  wire [3:0]               reg_num_ref_l0_act_m1,
    input  wire [31:0]              reg_cur_poc,

    //==========================================================
    // Current block information
    // [16:14] block-size one-hot
    // [13:0]  CU command
    //==========================================================
    input  wire [16:0]              cu_cmd_in,

    //==========================================================
    // Spatial neighbor motion information
    // [33:32] ref_idx
    // [31:16] mvy
    // [15:0]  mvx
    //==========================================================
    input  wire [1:0][33:0]         neib_a,
    input  wire [2:0][33:0]         neib_b,

    //==========================================================
    // Colocated neighbor motion information
    // [41]    long-term
    // [40]    intra
    // [39:32] poc_diff
    // [31:16] mvy
    // [15:0]  mvx
    //==========================================================
    input  wire [1:0][41:0]        col_c,
    input  wire [1:0]              col_c_avail,

    //==========================================================
    // Reference list information
    // [32]    long-term
    // [31:0]  reference POC
    //==========================================================
    input  wire [NUM_REF-1:0][32:0] reflist_info,
    input  wire [1:0]               cur_ref_idx,
    input  wire [1:0]               col_ref_idx,

    //==========================================================
    // Reconstructed AMVP result
    // selected_mvp_info:
    // [42]    candidate long-term metadata
    // [41:34] candidate poc_diff metadata
    // [33:32] candidate ref_idx metadata
    // [31:16] selected MVP Y
    // [15:0]  selected MVP X
    //==========================================================
    output reg  [42:0]              selected_mvp_info,
    output reg  signed [15:0]       selected_mvp_x,
    output reg  signed [15:0]       selected_mvp_y,

    // final_mv = selected_mvp + parsed_mvd
    output reg  signed [15:0]       final_mv_x,
    output reg  signed [15:0]       final_mv_y,

    // AMVP current reference comes from parsed ref_idx_l0,
    // not from encoder-side candidate cost selection.
    output reg  [1:0]               final_ref_idx,
    output reg                      final_ref_long,
    output reg  [7:0]               final_ref_poc_diff,

    output reg                      final_valid,
    output wire                     amvp_done,
    output wire                     amvp_idle,

    //==========================================================
    // Debug / verification
    //==========================================================
    output wire [1:0][42:0]         dbg_cand_mv,
    output wire [1:0]               dbg_cand_valid,
    output wire [1:0]               dbg_cand_seen,
    output wire [FSMW-1:0]          dbg_fsm_cand_cs
);

    //==========================================================
    // Candidate core connection
    //==========================================================
    wire [1:0][42:0] cand_mv;
    wire [1:0]       cand_valid;
    wire             cand_done;
    wire             cand_idle;

    // cand_valid may assert before cand_done and the two candidates
    // may be produced in different cycles when MV scaling is used.
    reg  [1:0][42:0] cand_hold;
    reg  [1:0]       cand_seen;

    // Parsed syntax is latched at the beginning of this AMVP transaction.
    reg              mvp_l0_flag_r;
    reg              avc_mode_r;
    reg signed [15:0] parsed_mvd_x_r;
    reg signed [15:0] parsed_mvd_y_r;
    reg [1:0]        cur_ref_idx_r;
    reg              cur_ref_long_r;
    reg [7:0]        cur_ref_poc_diff_r;

    wire [32:0]      cur_ref_info_in;
    wire [7:0]       cur_ref_poc_diff_in;

    // Include a candidate that is valid in the current cycle when
    // evaluating the transaction completion condition.
    wire [1:0]       cand_seen_eff;
    wire [42:0]      cand0_eff;
    wire [42:0]      cand1_eff;
    wire             selected_idx;
    wire [42:0]      selected_cand_eff;
    wire             selected_seen_eff;

    wire signed [16:0] final_mv_x_sum;
    wire signed [16:0] final_mv_y_sum;

    //==========================================================
    // Current reference-list entry
    // First version supports NUM_REF equal to 1 or 2.
    //==========================================================
    generate
        if (NUM_REF == 1) begin : g_cur_ref_num1
            assign cur_ref_info_in = reflist_info[0];
        end
        else begin : g_cur_ref_num2
            assign cur_ref_info_in =
                cur_ref_idx[0] ? reflist_info[1] : reflist_info[0];
        end
    endgenerate

    assign cur_ref_poc_diff_in =
        poc_diff_clip3(reg_cur_poc, cur_ref_info_in[31:0]);

    // AVC mode uses the median candidate on cand0 and does not use cand1.
    // HEVC-like mode uses mvp_l0_flag directly as the candidate index:
    // 0 -> cand0, 1 -> cand1.
    assign selected_idx = avc_mode_r ? 1'b0 : mvp_l0_flag_r;

    assign cand_seen_eff = cand_seen | cand_valid;
    assign cand0_eff      = cand_valid[0] ? cand_mv[0] : cand_hold[0];
    assign cand1_eff      = cand_valid[1] ? cand_mv[1] : cand_hold[1];
    assign selected_cand_eff =
        selected_idx ? cand1_eff : cand0_eff;
    assign selected_seen_eff = cand_seen_eff[selected_idx];

    // Use a signed 17-bit intermediate and retain the lower 16 bits.
    // This is the inverse of encoder-side 16-bit MVD generation.
    assign final_mv_x_sum =
        $signed({selected_cand_eff[15], selected_cand_eff[15:0]}) +
        $signed({parsed_mvd_x_r[15], parsed_mvd_x_r});

    assign final_mv_y_sum =
        $signed({selected_cand_eff[31], selected_cand_eff[31:16]}) +
        $signed({parsed_mvd_y_r[15], parsed_mvd_y_r});

    assign amvp_done = cand_done;
    assign amvp_idle = cand_idle;

    assign dbg_cand_mv    = cand_mv;
    assign dbg_cand_valid = cand_valid;
    assign dbg_cand_seen  = cand_seen;

    //==========================================================
    // Transaction state and result registers
    //==========================================================
    always @(posedge clk_vd or negedge vd_rst_z) begin
        if (!vd_rst_z) begin
            cand_hold             <= '0;
            cand_seen             <= '0;
            mvp_l0_flag_r         <= 1'b0;
            avc_mode_r            <= 1'b0;
            parsed_mvd_x_r        <= '0;
            parsed_mvd_y_r        <= '0;
            cur_ref_idx_r         <= '0;
            cur_ref_long_r        <= 1'b0;
            cur_ref_poc_diff_r    <= '0;
            selected_mvp_info     <= '0;
            selected_mvp_x        <= '0;
            selected_mvp_y        <= '0;
            final_mv_x            <= '0;
            final_mv_y            <= '0;
            final_ref_idx         <= '0;
            final_ref_long        <= 1'b0;
            final_ref_poc_diff    <= '0;
            final_valid           <= 1'b0;
        end
        else if (slice_start) begin
            cand_hold             <= '0;
            cand_seen             <= '0;
            mvp_l0_flag_r         <= 1'b0;
            avc_mode_r            <= 1'b0;
            parsed_mvd_x_r        <= '0;
            parsed_mvd_y_r        <= '0;
            cur_ref_idx_r         <= '0;
            cur_ref_long_r        <= 1'b0;
            cur_ref_poc_diff_r    <= '0;
            selected_mvp_info     <= '0;
            selected_mvp_x        <= '0;
            selected_mvp_y        <= '0;
            final_mv_x            <= '0;
            final_mv_y            <= '0;
            final_ref_idx         <= '0;
            final_ref_long        <= 1'b0;
            final_ref_poc_diff    <= '0;
            final_valid           <= 1'b0;
        end
        else begin
            final_valid <= 1'b0;

            if (amvp_start) begin
                cand_hold          <= '0;
                cand_seen          <= '0;
                mvp_l0_flag_r      <= mvp_l0_flag;
                avc_mode_r         <= reg_avc_mode;
                parsed_mvd_x_r     <= parsed_mvd_x;
                parsed_mvd_y_r     <= parsed_mvd_y;
                cur_ref_idx_r      <= cur_ref_idx;
                cur_ref_long_r     <= cur_ref_info_in[32];
                cur_ref_poc_diff_r <= cur_ref_poc_diff_in;
            end

            if (cand_valid[0]) begin
                cand_hold[0] <= cand_mv[0];
                cand_seen[0] <= 1'b1;
            end

            if (cand_valid[1]) begin
                cand_hold[1] <= cand_mv[1];
                cand_seen[1] <= 1'b1;
            end

            if (cand_done) begin
                if (selected_seen_eff) begin
                    selected_mvp_info  <= selected_cand_eff;
                    selected_mvp_x     <= selected_cand_eff[15:0];
                    selected_mvp_y     <= selected_cand_eff[31:16];
                    final_mv_x         <= final_mv_x_sum[15:0];
                    final_mv_y         <= final_mv_y_sum[15:0];
                    final_ref_idx      <= cur_ref_idx_r;
                    final_ref_long     <= cur_ref_long_r;
                    final_ref_poc_diff <= cur_ref_poc_diff_r;
                    final_valid        <= 1'b1;
                end
                else begin
                    selected_mvp_info  <= '0;
                    selected_mvp_x     <= '0;
                    selected_mvp_y     <= '0;
                    final_mv_x         <= '0;
                    final_mv_y         <= '0;
                    final_ref_idx      <= cur_ref_idx_r;
                    final_ref_long     <= cur_ref_long_r;
                    final_ref_poc_diff <= cur_ref_poc_diff_r;
                    final_valid        <= 1'b0;
                end
            end
        end
    end

    //==========================================================
    // Reused candidate generator wrapper
    //==========================================================
    vd_mvp_cand_core #(
        .NUM_REF      (NUM_REF),
        .AMVP_OR_MRG  (1),
        .MVP_SCALE_EN (MVP_SCALE_EN),
        .FSMW         (FSMW)
    )
    U_VD_MVP_CAND_CORE (
        .clk_vd                 (clk_vd),
        .vd_rst_z               (vd_rst_z),
        .cand_start             (amvp_start),
        .slice_start            (slice_start),
        .reg_tmp_mvp_flag       (reg_tmp_mvp_flag),
        .reg_avc_mode           (reg_avc_mode),
        .reg_num_ref_l0_act_m1  (reg_num_ref_l0_act_m1),
        .reg_cur_poc            (reg_cur_poc),
        .cu_cmd_in              (cu_cmd_in),
        .neib_a                 (neib_a),
        .neib_b                 (neib_b),
        .col_c                  (col_c),
        .col_c_avail            (col_c_avail),
        .reflist_info           (reflist_info),
        .cur_ref_idx            (cur_ref_idx),
        .col_ref_idx            (col_ref_idx),
        .merge_cand_num_m1      (3'd1),
        .cand_mv                (cand_mv),
        .cand_valid             (cand_valid),
        .cand_done              (cand_done),
        .cand_idle              (cand_idle),
        .dbg_fsm_cand_cs        (dbg_fsm_cand_cs)
    );

    //==========================================================
    // Clip current POC difference to signed 8-bit range.
    //==========================================================
    function signed [7:0] poc_diff_clip3;
        input [31:0] poc_0;
        input [31:0] poc_1;
        reg signed [32:0] poc_diff;
        begin
            poc_diff = $signed(poc_0) - $signed(poc_1);

            if (poc_diff < -128)
                poc_diff_clip3 = -8'sd128;
            else if (poc_diff > 127)
                poc_diff_clip3 = 8'sd127;
            else
                poc_diff_clip3 = poc_diff[7:0];
        end
    endfunction

endmodule
