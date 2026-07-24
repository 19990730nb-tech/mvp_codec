// -----------------------------------------------------------------------------
// Thin decoder-side adapter around vc_mvp_cand_gen.
// It renames clock/reset/control ports and preserves the shared 43-bit
// candidate representation without adding state or changing candidate order.
// -----------------------------------------------------------------------------
`include "ve_defines.v"

module vd_mvp_cand_core #(
    parameter NUM_REF      = 2,
    parameter AMVP_OR_MRG  = 1,
    parameter MVP_SCALE_EN = 0,
    parameter AW           = AMVP_OR_MRG ? 4 : 2,
    parameter BW           = AMVP_OR_MRG ? 6 : 3,
    parameter FSMW         = AMVP_OR_MRG ? 5 : 3
)(
    //==========================================================
    // Clock / Reset
    //==========================================================
    input  wire                     clk_vd,
    input  wire                     vd_rst_z,

    //==========================================================
    // Control
    //==========================================================
    input  wire                     cand_start,
    input  wire                     slice_start,

    input  wire                     reg_tmp_mvp_flag,
    input  wire                     reg_avc_mode,
    input  wire [3:0]               reg_num_ref_l0_act_m1,
    input  wire [31:0]              reg_cur_poc,

    //==========================================================
    // Current Block Information
    // blk_sz[2:0], availability and CU coordinates
    //==========================================================
    input  wire [16:0]              cu_cmd_in,

    //==========================================================
    // Spatial Neighbor Motion Information
    // [33:32] ref_idx
    // [31:16] mvy
    // [15:0]  mvx
    //==========================================================
    input  wire [1:0][33:0]         neib_a,
    input  wire [2:0][33:0]         neib_b,

    //==========================================================
    // Colocated Motion Information
    // [41]    long-term
    // [40]    intra
    // [39:32] poc_diff
    // [31:16] mvy
    // [15:0]  mvx
    //==========================================================
    input  wire [1:0][41:0]         col_c,
    input  wire [1:0]               col_c_avail,

    //==========================================================
    // Reference List Information
    // [32]    long-term
    // [31:0]  reference POC
    //==========================================================
    input  wire [NUM_REF-1:0][32:0] reflist_info,

    input  wire [1:0]               cur_ref_idx,
    input  wire [1:0]               col_ref_idx,

    //==========================================================
    // Merge Configuration
    //==========================================================
    input  wire [2:0]               merge_cand_num_m1,

    //==========================================================
    // Candidate Output
    // [42]    long-term
    // [41:34] poc_diff
    // [33:32] ref_idx
    // [31:16] mvy
    // [15:0]  mvx
    //==========================================================
    output wire [1:0][42:0]         cand_mv,
    output wire [1:0]               cand_valid,

    output wire                     cand_done,
    output wire                     cand_idle,

    //==========================================================
    // Debug
    //==========================================================
    output wire [FSMW-1:0]          dbg_fsm_cand_cs
);

    //==========================================================
    // Reused candidate generator
    //==========================================================

    vc_mvp_cand_gen #(
        .NUM_REF      (NUM_REF),
        .AMVP_OR_MRG  (AMVP_OR_MRG),
        .MVP_SCALE_EN (MVP_SCALE_EN),
        .AW           (AW),
        .BW           (BW),
        .FSMW         (FSMW)
    ) u_vc_mvp_cand_gen (
        .cand_mv                (cand_mv),
        .cand_rdy               (cand_valid),
        .cand_blk_done          (cand_done),
        .cand_blk_idle          (cand_idle),
        .dbg_fsm_cand_cs        (dbg_fsm_cand_cs),

        .clk_vc                 (clk_vd),
        .vc_rst_z               (vd_rst_z),
        .cand_cu_start          (cand_start),
        .mrg_cand_nr_m1         (merge_cand_num_m1),
        .reg_slice_go           (slice_start),
        .reg_tmp_mvp_flag       (reg_tmp_mvp_flag),
        .reg_num_ref_l0_act_m1  (reg_num_ref_l0_act_m1),
        .reg_cur_poc            (reg_cur_poc),
        .reg_avc_mode           (reg_avc_mode),
        .cu_cmd_out             (cu_cmd_in),

        .neib_b                 (neib_b),
        .neib_a                 (neib_a),
        .col_c                  (col_c),
        .col_c_avail            (col_c_avail),
        .reflist_info           (reflist_info),
        .cur_ref_idx            (cur_ref_idx),
        .col_ref_idx            (col_ref_idx)
    );

endmodule
