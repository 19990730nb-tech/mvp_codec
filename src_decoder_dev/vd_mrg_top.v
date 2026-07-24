// -----------------------------------------------------------------------------
// Decoder-native Merge wrapper.
// It validates the parsed merge index, collects the reused candidate core's
// outputs, and publishes the selected candidate as final decoder motion info.
// This first version supports merge_idx 0/1 and rejects normal Merge in AVC.
// -----------------------------------------------------------------------------
`include "ve_defines.v"

module vd_mrg_top #(
    parameter NUM_REF      = 2,
    parameter MVP_SCALE_EN = 0,
    parameter FSMW         = 3
)(
    //==========================================================
    // Clock / Reset
    //==========================================================
    input  wire                     clk_vd,
    input  wire                     vd_rst_z,

    //==========================================================
    // Decoder control / parsed syntax
    //==========================================================
    input  wire                     mrg_start,
    input  wire                     slice_start,
    input  wire [2:0]               merge_idx,
    input  wire [2:0]               merge_cand_num_m1,

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
    // Selected Merge result
    // [42]    long-term
    // [41:34] poc_diff
    // [33:32] ref_idx
    // [31:16] mvy
    // [15:0]  mvx
    //==========================================================
    output reg  [42:0]              selected_mrg_info,
    output reg  signed [15:0]       final_mv_x,
    output reg  signed [15:0]       final_mv_y,
    output reg  [1:0]               final_ref_idx,
    output reg                      final_ref_long,
    output reg  [7:0]               final_ref_poc_diff,
    output reg  [2:0]               selected_merge_idx,
    output reg                      final_valid,

    output wire                     mrg_done,
    output wire                     mrg_idle,

    //==========================================================
    // Illegal-request indication
    // Current candidate core exposes only cand0/cand1.
    // AVC mode normal Merge scheduling is disabled in the
    // existing encoder top-level integration.
    //==========================================================
    output reg                      merge_idx_error,
    output reg                      avc_mode_error,

    //==========================================================
    // Debug / verification
    //==========================================================
    output wire [1:0][42:0]         dbg_cand_mv,
    output wire [1:0]               dbg_cand_valid,
    output wire [1:0]               dbg_cand_seen,
    output wire [FSMW-1:0]          dbg_fsm_cand_cs
);

    //==========================================================
    // Candidate-core connection
    //==========================================================
    wire [1:0][42:0] cand_mv;
    wire [1:0]       cand_valid;
    wire             cand_done;
    wire             cand_idle;

    reg  [1:0][42:0] cand_hold;
    reg  [1:0]       cand_seen;

    reg  [2:0]       merge_idx_r;
    reg  [2:0]       merge_cand_num_m1_r;

    reg              request_error_done;

    wire             merge_idx_supported_in;
    wire             merge_idx_supported_r;
    wire             core_start;

    wire [1:0]       cand_seen_eff;
    wire [42:0]      cand0_eff;
    wire [42:0]      cand1_eff;
    wire             selected_idx;
    wire [42:0]      selected_cand_eff;
    wire             selected_seen_eff;

    //==========================================================
    // Request legality
    //
    // The reused vc_mvp_cand_gen interface produces two outputs:
    // cand0 and cand1.  Existing ve_mrg_top also fixes
    // mrg_cand_nr_m1 to 1, so this first decoder version accepts
    // merge_idx 0 or 1 only.
    //==========================================================
    assign merge_idx_supported_in =
        (merge_idx <= 3'd1) &&
        (merge_idx <= merge_cand_num_m1);

    assign merge_idx_supported_r =
        (merge_idx_r <= 3'd1) &&
        (merge_idx_r <= merge_cand_num_m1_r);

    // The existing encoder integration suppresses the normal
    // Merge candidate path in AVC mode.  AVC median reconstruction
    // remains in the decoder AMVP/AVC path.
    assign core_start =
        mrg_start &&
        !reg_avc_mode &&
        merge_idx_supported_in;

    // Candidate valid may precede cand_done, especially when
    // candidate scaling uses multiple cycles.
    assign cand_seen_eff = cand_seen | cand_valid;
    assign cand0_eff     = cand_valid[0] ? cand_mv[0] : cand_hold[0];
    assign cand1_eff     = cand_valid[1] ? cand_mv[1] : cand_hold[1];

    assign selected_idx      = merge_idx_r[0];
    assign selected_cand_eff = selected_idx ? cand1_eff : cand0_eff;
    assign selected_seen_eff = cand_seen_eff[selected_idx];

    assign mrg_done = cand_done | request_error_done;
    assign mrg_idle = cand_idle;

    assign dbg_cand_mv    = cand_mv;
    assign dbg_cand_valid = cand_valid;
    assign dbg_cand_seen  = cand_seen;

    //==========================================================
    // Transaction state and selected result
    //==========================================================
    always @(posedge clk_vd or negedge vd_rst_z) begin
        if (!vd_rst_z) begin
            cand_hold             <= '0;
            cand_seen             <= '0;
            merge_idx_r           <= '0;
            merge_cand_num_m1_r   <= '0;
            request_error_done    <= 1'b0;
            selected_mrg_info     <= '0;
            final_mv_x            <= '0;
            final_mv_y            <= '0;
            final_ref_idx         <= '0;
            final_ref_long        <= 1'b0;
            final_ref_poc_diff    <= '0;
            selected_merge_idx    <= '0;
            final_valid           <= 1'b0;
            merge_idx_error       <= 1'b0;
            avc_mode_error        <= 1'b0;
        end
        else if (slice_start) begin
            cand_hold             <= '0;
            cand_seen             <= '0;
            merge_idx_r           <= '0;
            merge_cand_num_m1_r   <= '0;
            request_error_done    <= 1'b0;
            selected_mrg_info     <= '0;
            final_mv_x            <= '0;
            final_mv_y            <= '0;
            final_ref_idx         <= '0;
            final_ref_long        <= 1'b0;
            final_ref_poc_diff    <= '0;
            selected_merge_idx    <= '0;
            final_valid           <= 1'b0;
            merge_idx_error       <= 1'b0;
            avc_mode_error        <= 1'b0;
        end
        else begin
            request_error_done <= 1'b0;
            final_valid        <= 1'b0;
            merge_idx_error    <= 1'b0;
            avc_mode_error     <= 1'b0;

            if (mrg_start) begin
                cand_hold           <= '0;
                cand_seen           <= '0;
                merge_idx_r         <= merge_idx;
                merge_cand_num_m1_r <= merge_cand_num_m1;

                if (reg_avc_mode) begin
                    avc_mode_error     <= 1'b1;
                    request_error_done <= 1'b1;
                end
                else if (!merge_idx_supported_in) begin
                    merge_idx_error    <= 1'b1;
                    request_error_done <= 1'b1;
                end
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
                if (merge_idx_supported_r && selected_seen_eff) begin
                    selected_mrg_info  <= selected_cand_eff;
                    final_mv_x         <= selected_cand_eff[15:0];
                    final_mv_y         <= selected_cand_eff[31:16];
                    final_ref_idx      <= selected_cand_eff[33:32];
                    final_ref_poc_diff <= selected_cand_eff[41:34];
                    final_ref_long     <= selected_cand_eff[42];
                    selected_merge_idx <= merge_idx_r;
                    final_valid        <= 1'b1;
                end
                else begin
                    selected_mrg_info  <= '0;
                    final_mv_x         <= '0;
                    final_mv_y         <= '0;
                    final_ref_idx      <= '0;
                    final_ref_poc_diff <= '0;
                    final_ref_long     <= 1'b0;
                    selected_merge_idx <= merge_idx_r;
                    final_valid        <= 1'b0;
                    merge_idx_error    <= 1'b1;
                end
            end
        end
    end

    //==========================================================
    // Reused candidate generator wrapper
    //==========================================================
    vd_mvp_cand_core #(
        .NUM_REF      (NUM_REF),
        .AMVP_OR_MRG  (0),
        .MVP_SCALE_EN (MVP_SCALE_EN),
        .FSMW         (FSMW)
    )
    U_VD_MVP_CAND_CORE (
        .clk_vd                 (clk_vd),
        .vd_rst_z               (vd_rst_z),
        .cand_start             (core_start),
        .slice_start            (slice_start),
        .reg_tmp_mvp_flag       (reg_tmp_mvp_flag),
        .reg_avc_mode           (1'b0),
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
        .merge_cand_num_m1      (merge_cand_num_m1),
        .cand_mv                (cand_mv),
        .cand_valid             (cand_valid),
        .cand_done              (cand_done),
        .cand_idle              (cand_idle),
        .dbg_fsm_cand_cs        (dbg_fsm_cand_cs)
    );

endmodule
