// AVC DEC: compatibility wrapper for the decoder transaction controller.
// It forwards CCU syntax, stage completions, MC commit, and slice/mode flush
// while exposing the registered transaction context and stage handoff pulses.
// It performs no Neighbor, MVP, reconstruction, or MC-result processing.

module vc_mvp_ctrl (
    input                   clk_vc,
    input                   vc_rst_z,
    input                   codec_mode,
    input                   reg_slice_go,
    input                   ccu2irpu_valid,
    output                  irpu2ccu_rdy,
    input      [1:0][15:0]  ccu2irpu_mvd,
    input      [3:0]        ccu2irpu_ref_idx,
    input                   ccu2irpu_is_skip,
    input                   ccu2irpu_part_mode,
    input      [1:0]        ccu2irpu_sub_idx,
    input      [2:0]        dec_txn_cux,
    input      [2:0]        dec_txn_cuy,
    input                   neib_done_amvp,
    input                   cand_capture_done,
    input                   recon_done,
    input                   mc_commit,
    output                  dec_neib_start,
    output                  dec_cand_start,
    output                  dec_recon_start,
    output     [1:0][15:0]  dec_mvd,
    output     [3:0]        dec_ref_idx,
    output                  dec_is_skip,
    output                  dec_part_mode,
    output     [1:0]        dec_sub_idx,
    output     [2:0]        dec_cux,
    output     [2:0]        dec_cuy,
    output     [1:0]        dec_expected_sub_idx,
    output                  dec_busy,
    output     [5:0]        dbg_dec_fsm_cs
);

    vc_mvp_dec_ctrl u_vc_mvp_dec_ctrl (
        .clk_vc               (clk_vc),
        .vc_rst_z             (vc_rst_z),
        .codec_mode           (codec_mode),
        .reg_slice_go         (reg_slice_go),
        .ccu2irpu_valid       (ccu2irpu_valid),
        .irpu2ccu_rdy         (irpu2ccu_rdy),
        .ccu2irpu_mvd         (ccu2irpu_mvd),
        .ccu2irpu_ref_idx     (ccu2irpu_ref_idx),
        .ccu2irpu_is_skip     (ccu2irpu_is_skip),
        .ccu2irpu_part_mode   (ccu2irpu_part_mode),
        .ccu2irpu_sub_idx     (ccu2irpu_sub_idx),
        .dec_txn_cux          (dec_txn_cux),
        .dec_txn_cuy          (dec_txn_cuy),
        .neib_done_amvp       (neib_done_amvp),
        .cand_capture_done    (cand_capture_done),
        .recon_done           (recon_done),
        .mc_commit            (mc_commit),
        .dec_neib_start       (dec_neib_start),
        .dec_cand_start       (dec_cand_start),
        .dec_recon_start      (dec_recon_start),
        .dec_mvd              (dec_mvd),
        .dec_ref_idx          (dec_ref_idx),
        .dec_is_skip          (dec_is_skip),
        .dec_part_mode        (dec_part_mode),
        .dec_sub_idx          (dec_sub_idx),
        .dec_cux              (dec_cux),
        .dec_cuy              (dec_cuy),
        .dec_expected_sub_idx (dec_expected_sub_idx),
        .dec_busy             (dec_busy),
        .dbg_dec_fsm_cs       (dbg_dec_fsm_cs)
    );

endmodule
