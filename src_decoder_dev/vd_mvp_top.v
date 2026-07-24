`include "ve_defines.v"

module vd_mvp_top #(
    parameter NUM_REF      = 2,
    parameter MVP_SCALE_EN = 0
)(
    //==========================================================
    // Clock / Reset
    //==========================================================
    input  wire                     clk_vd,
    input  wire                     vd_rst_z,

    //==========================================================
    // Block transaction control
    //==========================================================
    input  wire                     blk_start,
    input  wire                     ctu_start,
    input  wire                     slice_start,

    // 0: AMVP, 1: Merge
    input  wire                     merge_mode,
    input  wire                     intra_mode,

    // 8x8-slot coordinates inside current 64x64 CTU
    input  wire [2:0]               cur_x,
    input  wire [2:0]               cur_y,

    // Existing project encoding:
    // 2'd1 = blk8, 2'd2 = blk16, other = blk32
    input  wire [1:0]               blk_sz,

    input  wire                     skip_flag,
    input  wire                     zmv_flag,
    input  wire                     terminate_flag,

    //==========================================================
    // Parsed AMVP / Merge syntax
    //==========================================================
    input  wire                     mvp_l0_flag,
    input  wire signed [15:0]       parsed_mvd_x,
    input  wire signed [15:0]       parsed_mvd_y,

    input  wire [2:0]               merge_idx,
    input  wire [2:0]               merge_cand_num_m1,

    input  wire [1:0]               cur_ref_idx,
    input  wire [1:0]               col_ref_idx,

    //==========================================================
    // Sequence / slice configuration
    //==========================================================
    input  wire                     reg_tmp_mvp_flag,
    input  wire                     reg_avc_mode,
    input  wire [3:0]               reg_num_ref_l0_act_m1,
    input  wire [31:0]              reg_cur_poc,

    //==========================================================
    // Explicit spatial availability
    //
    // These inputs must already include picture/slice/tile/
    // scan-order availability checks.
    //==========================================================
    input  wire                     a0_avail_in,
    input  wire                     a1_avail_in,
    input  wire                     b0_avail_in,
    input  wire                     b1_avail_in,
    input  wire                     b2_avail_in,

    //==========================================================
    // Cross-CTU spatial-neighbor inputs
    //==========================================================
    input  wire [34:0]              ext_a0_motion,
    input  wire                     ext_a0_valid,
    input  wire                     ext_a0_intra,

    input  wire [34:0]              ext_a1_motion,
    input  wire                     ext_a1_valid,
    input  wire                     ext_a1_intra,

    input  wire [34:0]              ext_b0_motion,
    input  wire                     ext_b0_valid,
    input  wire                     ext_b0_intra,

    input  wire [34:0]              ext_b1_motion,
    input  wire                     ext_b1_valid,
    input  wire                     ext_b1_intra,

    input  wire [34:0]              ext_b2_motion,
    input  wire                     ext_b2_valid,
    input  wire                     ext_b2_intra,

    //==========================================================
    // Colocated / reference-list inputs
    //==========================================================
    input  wire [1:0][41:0]         col_c_in,
    input  wire [1:0]               col_c_avail_in,
    input  wire [NUM_REF-1:0][32:0] reflist_info,

    //==========================================================
    // Final reconstructed motion information
    //==========================================================
    output reg  signed [15:0]       final_mv_x,
    output reg  signed [15:0]       final_mv_y,
    output reg  [1:0]               final_ref_idx,
    output reg                      final_ref_long,
    output reg  [7:0]               final_ref_poc_diff,
    output reg                      final_valid,

    output reg                      blk_done,
    output wire                     blk_idle,

    //==========================================================
    // Error / debug
    //==========================================================
    output wire                     mrg_merge_idx_error,
    output wire                     mrg_avc_mode_error,
    output wire [3:0]               dbg_top_state,
    output wire [63:0]              dbg_cache_valid_map,
    output wire [63:0]              dbg_cache_intra_map
);

    //==========================================================
    // Top-level control FSM
    //==========================================================
    localparam [3:0]
        TOP_IDLE      = 4'd0,
        TOP_WAIT_NEIB = 4'd1,
        TOP_START_CORE= 4'd2,
        TOP_WAIT_CORE = 4'd3,
        TOP_UPDATE    = 4'd4,
        TOP_DONE      = 4'd5;

    reg [3:0] top_state;
    reg [3:0] top_next_state;

    reg       merge_mode_r;
    reg       intra_mode_r;
    reg [2:0] cur_x_r;
    reg [2:0] cur_y_r;
    reg [1:0] blk_sz_r;
    reg       skip_flag_r;
    reg       zmv_flag_r;
    reg       terminate_flag_r;

    reg       neib_start;
    reg       amvp_start;
    reg       mrg_start;

    wire      neib_done;
    wire      amvp_done;
    wire      mrg_done;

    wire      amvp_final_valid;
    wire      mrg_final_valid;

    //==========================================================
    // Neighbor view
    //==========================================================
    wire [1:0][33:0] neib_a;
    wire [2:0][33:0] neib_b;
    wire [1:0]       neib_a_avail;
    wire [2:0]       neib_b_avail;
    wire [1:0][41:0] col_c;
    wire [1:0]       col_c_avail;

    //==========================================================
    // Motion-cache read interface
    //==========================================================
    wire        cache_rd0_en;
    wire [2:0]  cache_rd0_x;
    wire [2:0]  cache_rd0_y;
    wire [34:0] cache_rd0_motion;
    wire        cache_rd0_valid;
    wire        cache_rd0_intra;

    wire        cache_rd1_en;
    wire [2:0]  cache_rd1_x;
    wire [2:0]  cache_rd1_y;
    wire [34:0] cache_rd1_motion;
    wire        cache_rd1_valid;
    wire        cache_rd1_intra;

    wire        cache_rd2_en;
    wire [2:0]  cache_rd2_x;
    wire [2:0]  cache_rd2_y;
    wire [34:0] cache_rd2_motion;
    wire        cache_rd2_valid;
    wire        cache_rd2_intra;

    wire        cache_rd3_en;
    wire [2:0]  cache_rd3_x;
    wire [2:0]  cache_rd3_y;
    wire [34:0] cache_rd3_motion;
    wire        cache_rd3_valid;
    wire        cache_rd3_intra;

    wire        cache_rd4_en;
    wire [2:0]  cache_rd4_x;
    wire [2:0]  cache_rd4_y;
    wire [34:0] cache_rd4_motion;
    wire        cache_rd4_valid;
    wire        cache_rd4_intra;

    //==========================================================
    // Candidate command compatibility bus
    //
    // [2:0]   cux
    // [5:3]   cuy
    // [8:6]   B availability: B0/B1/B2
    // [10:9]  A availability: A0/A1
    // [11]    ZMV
    // [12]    skip
    // [13]    terminate
    // [16:14] block-size one-hot
    //==========================================================
    wire [2:0] blk_sz_onehot;
    wire [16:0] cu_cmd_in;

    assign blk_sz_onehot =
        (blk_sz_r == 2'd1) ? 3'b001 :
        (blk_sz_r == 2'd2) ? 3'b010 :
                             3'b100;

    assign cu_cmd_in = {
        blk_sz_onehot,
        terminate_flag_r,
        skip_flag_r,
        zmv_flag_r,
        neib_a_avail,
        neib_b_avail,
        cur_y_r,
        cur_x_r
    };

    //==========================================================
    // AMVP outputs
    //==========================================================
    wire signed [15:0] amvp_final_mv_x;
    wire signed [15:0] amvp_final_mv_y;
    wire [1:0]         amvp_final_ref_idx;
    wire               amvp_final_ref_long;
    wire [7:0]         amvp_final_ref_poc_diff;

    //==========================================================
    // Merge outputs
    //==========================================================
    wire signed [15:0] mrg_final_mv_x;
    wire signed [15:0] mrg_final_mv_y;
    wire [1:0]         mrg_final_ref_idx;
    wire               mrg_final_ref_long;
    wire [7:0]         mrg_final_ref_poc_diff;

    //==========================================================
    // Cache update selection
    //==========================================================
    wire cache_upd_valid;
    wire signed [15:0] cache_upd_mvx;
    wire signed [15:0] cache_upd_mvy;
    wire [1:0]         cache_upd_ref_idx;
    wire               cache_upd_long;

    assign cache_upd_valid =
        (top_state == TOP_UPDATE) &&
        (intra_mode_r || final_valid);

    assign cache_upd_mvx     = intra_mode_r ? 16'sd0 : final_mv_x;
    assign cache_upd_mvy     = intra_mode_r ? 16'sd0 : final_mv_y;
    assign cache_upd_ref_idx = intra_mode_r ? 2'd0   : final_ref_idx;
    assign cache_upd_long    = intra_mode_r ? 1'b0   : final_ref_long;

    //==========================================================
    // FSM next-state logic
    //==========================================================
    always @(*) begin
        top_next_state = top_state;

        case (top_state)
            TOP_IDLE: begin
                if (blk_start)
                    top_next_state = intra_mode ? TOP_UPDATE : TOP_WAIT_NEIB;
            end

            TOP_WAIT_NEIB: begin
                if (neib_done)
                    top_next_state = TOP_START_CORE;
            end

            TOP_START_CORE:
                top_next_state = TOP_WAIT_CORE;

            TOP_WAIT_CORE: begin
                if ((!merge_mode_r && amvp_done) ||
                    ( merge_mode_r && mrg_done))
                    top_next_state = TOP_UPDATE;
            end

            TOP_UPDATE:
                top_next_state = TOP_DONE;

            TOP_DONE:
                top_next_state = TOP_IDLE;

            default:
                top_next_state = TOP_IDLE;
        endcase
    end

    //==========================================================
    // FSM state / transaction registers
    //==========================================================
    always @(posedge clk_vd or negedge vd_rst_z) begin
        if (!vd_rst_z) begin
            top_state         <= TOP_IDLE;
            merge_mode_r      <= 1'b0;
            intra_mode_r      <= 1'b0;
            cur_x_r           <= 3'd0;
            cur_y_r           <= 3'd0;
            blk_sz_r          <= 2'd1;
            skip_flag_r       <= 1'b0;
            zmv_flag_r        <= 1'b0;
            terminate_flag_r  <= 1'b0;
        end
        else if (slice_start) begin
            top_state         <= TOP_IDLE;
            merge_mode_r      <= 1'b0;
            intra_mode_r      <= 1'b0;
            cur_x_r           <= 3'd0;
            cur_y_r           <= 3'd0;
            blk_sz_r          <= 2'd1;
            skip_flag_r       <= 1'b0;
            zmv_flag_r        <= 1'b0;
            terminate_flag_r  <= 1'b0;
        end
        else begin
            top_state <= top_next_state;

            if ((top_state == TOP_IDLE) && blk_start) begin
                merge_mode_r     <= merge_mode;
                intra_mode_r     <= intra_mode;
                cur_x_r          <= cur_x;
                cur_y_r          <= cur_y;
                blk_sz_r         <= blk_sz;
                skip_flag_r      <= skip_flag;
                zmv_flag_r       <= zmv_flag;
                terminate_flag_r <= terminate_flag;
            end
        end
    end

    //==========================================================
    // One-cycle control pulses
    //==========================================================
    always @(*) begin
        neib_start = 1'b0;
        amvp_start = 1'b0;
        mrg_start  = 1'b0;

        if (top_state == TOP_WAIT_NEIB)
            neib_start = 1'b1;

        if (top_state == TOP_START_CORE) begin
            if (merge_mode_r)
                mrg_start = 1'b1;
            else
                amvp_start = 1'b1;
        end
    end

    //==========================================================
    // Final-output latch
    //==========================================================
    always @(posedge clk_vd or negedge vd_rst_z) begin
        if (!vd_rst_z) begin
            final_mv_x          <= 16'sd0;
            final_mv_y          <= 16'sd0;
            final_ref_idx       <= 2'd0;
            final_ref_long      <= 1'b0;
            final_ref_poc_diff  <= 8'd0;
            final_valid         <= 1'b0;
            blk_done            <= 1'b0;
        end
        else if (slice_start) begin
            final_mv_x          <= 16'sd0;
            final_mv_y          <= 16'sd0;
            final_ref_idx       <= 2'd0;
            final_ref_long      <= 1'b0;
            final_ref_poc_diff  <= 8'd0;
            final_valid         <= 1'b0;
            blk_done            <= 1'b0;
        end
        else begin
            blk_done <= 1'b0;

            if ((top_state == TOP_IDLE) && blk_start) begin
                final_valid <= 1'b0;
            end

            if (top_state == TOP_WAIT_CORE) begin
                if (!merge_mode_r && amvp_done) begin
                    final_mv_x         <= amvp_final_mv_x;
                    final_mv_y         <= amvp_final_mv_y;
                    final_ref_idx      <= amvp_final_ref_idx;
                    final_ref_long     <= amvp_final_ref_long;
                    final_ref_poc_diff <= amvp_final_ref_poc_diff;
                    final_valid        <= amvp_final_valid;
                end
                else if (merge_mode_r && mrg_done) begin
                    final_mv_x         <= mrg_final_mv_x;
                    final_mv_y         <= mrg_final_mv_y;
                    final_ref_idx      <= mrg_final_ref_idx;
                    final_ref_long     <= mrg_final_ref_long;
                    final_ref_poc_diff <= mrg_final_ref_poc_diff;
                    final_valid        <= mrg_final_valid;
                end
            end

            if (top_state == TOP_UPDATE) begin
                if (intra_mode_r)
                    final_valid <= 1'b0;
            end

            if (top_state == TOP_DONE)
                blk_done <= 1'b1;
        end
    end

    assign blk_idle      = (top_state == TOP_IDLE);
    assign dbg_top_state = top_state;

    //==========================================================
    // Current-CTU motion cache
    //==========================================================
    vd_mvp_motion_cache U_VD_MVP_MOTION_CACHE (
        .clk_vd             (clk_vd),
        .vd_rst_z           (vd_rst_z),
        .ctu_start          (ctu_start),

        .upd_valid          (cache_upd_valid),
        .upd_blk_sz         (blk_sz_r),
        .upd_x              (cur_x_r),
        .upd_y              (cur_y_r),
        .upd_mvx            (cache_upd_mvx),
        .upd_mvy            (cache_upd_mvy),
        .upd_ref_idx        (cache_upd_ref_idx),
        .upd_long_term      (cache_upd_long),
        .upd_intra          (intra_mode_r),

        .rd0_en             (cache_rd0_en),
        .rd0_x              (cache_rd0_x),
        .rd0_y              (cache_rd0_y),
        .rd0_motion         (cache_rd0_motion),
        .rd0_valid          (cache_rd0_valid),
        .rd0_intra          (cache_rd0_intra),

        .rd1_en             (cache_rd1_en),
        .rd1_x              (cache_rd1_x),
        .rd1_y              (cache_rd1_y),
        .rd1_motion         (cache_rd1_motion),
        .rd1_valid          (cache_rd1_valid),
        .rd1_intra          (cache_rd1_intra),

        .rd2_en             (cache_rd2_en),
        .rd2_x              (cache_rd2_x),
        .rd2_y              (cache_rd2_y),
        .rd2_motion         (cache_rd2_motion),
        .rd2_valid          (cache_rd2_valid),
        .rd2_intra          (cache_rd2_intra),

        .rd3_en             (cache_rd3_en),
        .rd3_x              (cache_rd3_x),
        .rd3_y              (cache_rd3_y),
        .rd3_motion         (cache_rd3_motion),
        .rd3_valid          (cache_rd3_valid),
        .rd3_intra          (cache_rd3_intra),

        .rd4_en             (cache_rd4_en),
        .rd4_x              (cache_rd4_x),
        .rd4_y              (cache_rd4_y),
        .rd4_motion         (cache_rd4_motion),
        .rd4_valid          (cache_rd4_valid),
        .rd4_intra          (cache_rd4_intra),

        .dbg_valid_map      (dbg_cache_valid_map),
        .dbg_intra_map      (dbg_cache_intra_map)
    );

    //==========================================================
    // Neighbor view construction
    //==========================================================
    vd_mvp_get_neib U_VD_MVP_GET_NEIB (
        .clk_vd             (clk_vd),
        .vd_rst_z           (vd_rst_z),
        .neib_start         (neib_start),

        .cur_x              (cur_x_r),
        .cur_y              (cur_y_r),
        .blk_sz             (blk_sz_r),

        .a0_avail_in        (a0_avail_in),
        .a1_avail_in        (a1_avail_in),
        .b0_avail_in        (b0_avail_in),
        .b1_avail_in        (b1_avail_in),
        .b2_avail_in        (b2_avail_in),

        .cache_rd0_en       (cache_rd0_en),
        .cache_rd0_x        (cache_rd0_x),
        .cache_rd0_y        (cache_rd0_y),
        .cache_rd0_motion   (cache_rd0_motion),
        .cache_rd0_valid    (cache_rd0_valid),
        .cache_rd0_intra    (cache_rd0_intra),

        .cache_rd1_en       (cache_rd1_en),
        .cache_rd1_x        (cache_rd1_x),
        .cache_rd1_y        (cache_rd1_y),
        .cache_rd1_motion   (cache_rd1_motion),
        .cache_rd1_valid    (cache_rd1_valid),
        .cache_rd1_intra    (cache_rd1_intra),

        .cache_rd2_en       (cache_rd2_en),
        .cache_rd2_x        (cache_rd2_x),
        .cache_rd2_y        (cache_rd2_y),
        .cache_rd2_motion   (cache_rd2_motion),
        .cache_rd2_valid    (cache_rd2_valid),
        .cache_rd2_intra    (cache_rd2_intra),

        .cache_rd3_en       (cache_rd3_en),
        .cache_rd3_x        (cache_rd3_x),
        .cache_rd3_y        (cache_rd3_y),
        .cache_rd3_motion   (cache_rd3_motion),
        .cache_rd3_valid    (cache_rd3_valid),
        .cache_rd3_intra    (cache_rd3_intra),

        .cache_rd4_en       (cache_rd4_en),
        .cache_rd4_x        (cache_rd4_x),
        .cache_rd4_y        (cache_rd4_y),
        .cache_rd4_motion   (cache_rd4_motion),
        .cache_rd4_valid    (cache_rd4_valid),
        .cache_rd4_intra    (cache_rd4_intra),

        .ext_a0_motion      (ext_a0_motion),
        .ext_a0_valid       (ext_a0_valid),
        .ext_a0_intra       (ext_a0_intra),

        .ext_a1_motion      (ext_a1_motion),
        .ext_a1_valid       (ext_a1_valid),
        .ext_a1_intra       (ext_a1_intra),

        .ext_b0_motion      (ext_b0_motion),
        .ext_b0_valid       (ext_b0_valid),
        .ext_b0_intra       (ext_b0_intra),

        .ext_b1_motion      (ext_b1_motion),
        .ext_b1_valid       (ext_b1_valid),
        .ext_b1_intra       (ext_b1_intra),

        .ext_b2_motion      (ext_b2_motion),
        .ext_b2_valid       (ext_b2_valid),
        .ext_b2_intra       (ext_b2_intra),

        .col_c_in           (col_c_in),
        .col_c_avail_in     (col_c_avail_in),

        .neib_a             (neib_a),
        .neib_b             (neib_b),
        .neib_a_avail       (neib_a_avail),
        .neib_b_avail       (neib_b_avail),
        .col_c              (col_c),
        .col_c_avail        (col_c_avail),
        .neib_done          (neib_done),

        .dbg_a0_x           (),
        .dbg_a0_y           (),
        .dbg_a1_x           (),
        .dbg_a1_y           (),
        .dbg_b0_x           (),
        .dbg_b0_y           (),
        .dbg_b1_x           (),
        .dbg_b1_y           (),
        .dbg_b2_x           (),
        .dbg_b2_y           ()
    );

    //==========================================================
    // AMVP reconstruction
    //==========================================================
    vd_amvp_top #(
        .NUM_REF      (NUM_REF),
        .MVP_SCALE_EN (MVP_SCALE_EN),
        .FSMW         (5)
    )
    U_VD_AMVP_TOP (
        .clk_vd                 (clk_vd),
        .vd_rst_z               (vd_rst_z),
        .amvp_start             (amvp_start),
        .slice_start            (slice_start),
        .mvp_l0_flag            (mvp_l0_flag),
        .parsed_mvd_x           (parsed_mvd_x),
        .parsed_mvd_y           (parsed_mvd_y),
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

        .selected_mvp_info      (),
        .selected_mvp_x         (),
        .selected_mvp_y         (),
        .final_mv_x             (amvp_final_mv_x),
        .final_mv_y             (amvp_final_mv_y),
        .final_ref_idx          (amvp_final_ref_idx),
        .final_ref_long         (amvp_final_ref_long),
        .final_ref_poc_diff     (amvp_final_ref_poc_diff),
        .final_valid            (amvp_final_valid),
        .amvp_done              (amvp_done),
        .amvp_idle              (),
        .dbg_cand_mv            (),
        .dbg_cand_valid         (),
        .dbg_cand_seen          (),
        .dbg_fsm_cand_cs        ()
    );

    //==========================================================
    // Merge reconstruction
    //==========================================================
    vd_mrg_top #(
        .NUM_REF      (NUM_REF),
        .MVP_SCALE_EN (MVP_SCALE_EN),
        .FSMW         (3)
    )
    U_VD_MRG_TOP (
        .clk_vd                 (clk_vd),
        .vd_rst_z               (vd_rst_z),
        .mrg_start              (mrg_start),
        .slice_start            (slice_start),
        .merge_idx              (merge_idx),
        .merge_cand_num_m1      (merge_cand_num_m1),
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

        .selected_mrg_info      (),
        .final_mv_x             (mrg_final_mv_x),
        .final_mv_y             (mrg_final_mv_y),
        .final_ref_idx          (mrg_final_ref_idx),
        .final_ref_long         (mrg_final_ref_long),
        .final_ref_poc_diff     (mrg_final_ref_poc_diff),
        .selected_merge_idx     (),
        .final_valid            (mrg_final_valid),
        .mrg_done               (mrg_done),
        .mrg_idle               (),
        .merge_idx_error        (mrg_merge_idx_error),
        .avc_mode_error         (mrg_avc_mode_error),
        .dbg_cand_mv            (),
        .dbg_cand_valid         (),
        .dbg_cand_seen          (),
        .dbg_fsm_cand_cs        ()
    );

endmodule
