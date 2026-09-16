// AVC DEC: integrate the registered Decoder transaction, command adapter,
// and legacy Neighbor engine.  It qualifies Neighbor completion and exposes
// A/B results and memory ports; it does not implement MED, reconstruction,
// MC, RefList traversal, or the future mc_commit rolling-state writer.

module vc_mvp_dec_neib_top #(
    parameter VC_CTU_X_NB  = 7,
    parameter VC_CTU_Y_NB  = 7,
    parameter VC_CU_X_NB   = 9,
    parameter VC_CU_Y_NB   = 9,
    parameter NUM_REF      = 2,
    parameter VC_EN_BI_DIR = 0
) (
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
    input      [1:0]        dec_txn_a_avail,
    input      [2:0]        dec_txn_b_avail,
    // CTU X is part of the active AVC B-neighbor SRAM address.  The decoder
    // wrapper latches it with the accepted transaction.
    input      [VC_CTU_X_NB-1:0] dec_txn_ctux,
    // The legacy B address generator uses this configuration in addition to
    // ctux/cux/cuy; the remaining picture geometry is Col-path-only here.
    input      [VC_CTU_X_NB-1:0] reg_pic_width_ctu_m1,

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
    output     [1:0]        dec_a_avail,
    output     [2:0]        dec_b_avail,
    output     [1:0]        dec_expected_sub_idx,
    output                  dec_busy,
    output     [5:0]        dbg_dec_fsm_cs,

    // Existing public Neighbor update interface; this wrapper does not
    // generate the future mc_commit-to-update path.
    input                   cur_cu_upd,
    input      [1:0]        cur_cu_upd_sz,
    input      [2:0]        cur_cu_upd_x,
    input      [2:0]        cur_cu_upd_y,
    input      [15:0]       cur_cu_upd_mvx,
    input      [15:0]       cur_cu_upd_mvy,
    input      [1:0]        cur_cu_upd_refidx,

    // Decoder Neighbor memory interfaces.
    output     [4:0]        irpu2neib_b_req,
    output     [4:0]        irpu2neib_b_addr,
    input                   neib_b2irpu_gnt,
    input                   neib_b2irpu_rd_lat,
    input      [67:0]       neib_b2irpu_rd,
    output     [1:0]        irpu2neib_a_req,
    output     [1:0]        irpu2neib_a_addr,
    input                   neib_a2irpu_gnt,
    input                   neib_a2irpu_rd_lat,
    input      [67:0]       neib_a2irpu_rd,

    output                  irpu2col_req,
    output     [4:0]        irpu2col_addr,
    input                   col2irpu_gnt,
    input                   col2irpu_rd_lat,
    input      [83:0]       col2irpu_rd,
    output                  irpu2ref_req,
    output     [3+VC_EN_BI_DIR:0] irpu2ref_addr,
    input                   ref2irpu_gnt,
    input                   ref2irpu_rd_lat,
    input      [32:0]       ref2irpu_rd,

    output                  raw_neib_done_amvp,
    output                  neib_done_amvp,
    output                  neib_pending,
    output     [2:0][33:0]  amvp_neib_b,
    output     [1:0][33:0]  amvp_neib_a
);

    wire                    qualified_neib_done;
    wire                    raw_neib_done_amvp_w;
    reg                     neib_pending_q;
    reg      [VC_CTU_X_NB-1:0] dec_ctux_q;
    reg      [3:0]          neib_a_read_pending_q;
    reg      [3:0]          neib_b_read_pending_q;
    wire                    neib_reg_slice_go;
    wire                    ctrl_irpu2ccu_rdy;
    wire                    ctrl_ccu2irpu_valid;
    wire                    neib_mem_quiescent;
    wire                    dec_accept;
    wire     [1:0][2:0]     cmdq_empty_n;
    wire     [2:0]          amvp_blk_sz;
    wire     [2:0]          n_blk_sz_amvp;
    wire                    blk_sz_lat_amvp;
    wire     [2:0][13:0]     amvp_cmd_out;
    wire                    amvp_cu_start;
    wire     [2:0][13:0]     mrg_cmd_out;
    wire     [2:0]          mrg_blk_sz;
    wire                    mrg_cu_start;
    wire     [2:0]          n_blk_sz_mrg;
    wire                    neib_a_req_hs;
    wire                    neib_b_req_hs;
    wire                    neib_a_read_pending;
    wire                    neib_b_read_pending;

    assign mrg_cmd_out = 42'd0;
    assign mrg_blk_sz = 3'b000;
    assign mrg_cu_start = 1'b0;
    assign n_blk_sz_mrg = 3'b000;

    wire     [VC_CTU_X_NB-1:0] pic_width_ctu_m1 = reg_pic_width_ctu_m1;
    // These inputs only affect disabled Col/temporal logic.  Keep the legacy
    // ports structurally connected without exposing unused Decoder ports.
    wire     [VC_CU_X_NB-1:0]  pic_width_cu_m1  = {VC_CU_X_NB{1'b0}};
    wire     [VC_CU_Y_NB-1:0]  pic_height_cu_m1 = {VC_CU_Y_NB{1'b0}};

    // Decoder mode resets the legacy read FSMs without allowing a RefList
    // start; cur_ctu_start below remains permanently low for this path.
    assign neib_reg_slice_go = reg_slice_go | !codec_mode;

    vc_mvp_dec_ctrl U_DEC_CTRL (
        .clk_vc               (clk_vc),
        .vc_rst_z             (vc_rst_z),
        .codec_mode           (codec_mode),
        .reg_slice_go         (reg_slice_go),
        .ccu2irpu_valid       (ctrl_ccu2irpu_valid),
        .irpu2ccu_rdy         (ctrl_irpu2ccu_rdy),
        .ccu2irpu_mvd         (ccu2irpu_mvd),
        .ccu2irpu_ref_idx     (ccu2irpu_ref_idx),
        .ccu2irpu_is_skip     (ccu2irpu_is_skip),
        .ccu2irpu_part_mode   (ccu2irpu_part_mode),
        .ccu2irpu_sub_idx     (ccu2irpu_sub_idx),
        .dec_txn_cux          (dec_txn_cux),
        .dec_txn_cuy          (dec_txn_cuy),
        .dec_txn_a_avail      (dec_txn_a_avail),
        .dec_txn_b_avail      (dec_txn_b_avail),
        .neib_done_amvp       (qualified_neib_done),
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
        .dec_a_avail          (dec_a_avail),
        .dec_b_avail          (dec_b_avail),
        .dec_expected_sub_idx (dec_expected_sub_idx),
        .dec_busy             (dec_busy),
        .dbg_dec_fsm_cs       (dbg_dec_fsm_cs)
    );

    vc_mvp_dec_neib_adapter U_DEC_ADAPTER (
        .clk_vc          (clk_vc),
        .codec_mode      (codec_mode),
        .dec_neib_start  (dec_neib_start),
        .dec_part_mode   (dec_part_mode),
        .dec_is_skip     (dec_is_skip),
        .dec_sub_idx     (dec_sub_idx),
        .dec_cux         (dec_cux),
        .dec_cuy         (dec_cuy),
        .dec_a_avail     (dec_a_avail),
        .dec_b_avail     (dec_b_avail),
        .amvp_cu_start   (amvp_cu_start),
        .amvp_cmd_out    (amvp_cmd_out),
        .cmdq_empty_n    (cmdq_empty_n),
        .amvp_blk_sz     (amvp_blk_sz),
        .n_blk_sz_amvp   (n_blk_sz_amvp),
        .blk_sz_lat_amvp (blk_sz_lat_amvp)
    );

    // Keep blk_sz_lat_amvp at launch: it seeds the local/no-read Neighbor view
    // immediately, while a later A/B rd_lat overwrites it with SRAM data.

    assign neib_a_req_hs = irpu2neib_a_req[0] && neib_a2irpu_gnt;
    assign neib_b_req_hs = irpu2neib_b_req[0] && neib_b2irpu_gnt;
    assign neib_a_read_pending = |neib_a_read_pending_q;
    assign neib_b_read_pending = |neib_b_read_pending_q;
    assign neib_mem_quiescent = (neib_a_read_pending_q == 4'd0) &&
                                 (neib_b_read_pending_q == 4'd0);
    // Physical A/B reads survive Decoder flush until their rd_lat responses
    // drain.  Admission is reopened only after the memory path is quiescent.
    assign ctrl_ccu2irpu_valid = ccu2irpu_valid && neib_mem_quiescent;
    assign irpu2ccu_rdy = ctrl_irpu2ccu_rdy && neib_mem_quiescent;
    assign dec_accept = ccu2irpu_valid && irpu2ccu_rdy;

    // Raw completion is level-sensitive idle status.  Pending is set only
    // after launch, and public read tracking drains queued A/B responses so a
    // transient rd_mem_idle pulse cannot complete before the final read.
    assign raw_neib_done_amvp = raw_neib_done_amvp_w;
    assign qualified_neib_done = neib_pending_q && raw_neib_done_amvp_w &&
                                 !neib_a_read_pending && !neib_b_read_pending &&
                                 codec_mode && !reg_slice_go;
    assign neib_done_amvp = qualified_neib_done;
    assign neib_pending = neib_pending_q;

    // CTU context is transaction state, just like cux/cuy and availability.
    // It must not be coupled to cur_ctu_start: that signal only gates the
    // legacy RefList launch.
    always @(posedge clk_vc or negedge vc_rst_z) begin
        if (~vc_rst_z)
            dec_ctux_q <= {VC_CTU_X_NB{1'b0}};
        else if (reg_slice_go || !codec_mode)
            dec_ctux_q <= {VC_CTU_X_NB{1'b0}};
        else if (dec_accept)
            dec_ctux_q <= dec_txn_ctux;
    end

    always @(posedge clk_vc or negedge vc_rst_z) begin
        if (~vc_rst_z)
            neib_pending_q <= 1'b0;
        else if (reg_slice_go || !codec_mode)
            neib_pending_q <= 1'b0;
        else if (dec_neib_start)
            neib_pending_q <= 1'b1;
        else if (qualified_neib_done)
            neib_pending_q <= 1'b0;
    end

    // These are physical accepted-but-not-yet-returned Neighbor reads, not
    // current-Decoder reads.  They must survive Decoder flush until rd_lat.
    // The drain barrier makes req_hs and stale rd_lat overlap impossible.
    always @(posedge clk_vc or negedge vc_rst_z) begin
        if (~vc_rst_z) begin
            neib_a_read_pending_q <= 4'd0;
            neib_b_read_pending_q <= 4'd0;
        end
        else begin
            case ({neib_a_req_hs, neib_a2irpu_rd_lat})
                2'b10: neib_a_read_pending_q <= neib_a_read_pending_q + 1'b1;
                // Keep the T01-B2.2 zero guard for an unmatched response.
                2'b01: if (neib_a_read_pending_q != 4'd0)
                           neib_a_read_pending_q <= neib_a_read_pending_q - 1'b1;
                       else
                           neib_a_read_pending_q <= 4'd0;
                default: neib_a_read_pending_q <= neib_a_read_pending_q;
            endcase
            case ({neib_b_req_hs, neib_b2irpu_rd_lat})
                2'b10: neib_b_read_pending_q <= neib_b_read_pending_q + 1'b1;
                // See the A-direction guard above.
                2'b01: if (neib_b_read_pending_q != 4'd0)
                           neib_b_read_pending_q <= neib_b_read_pending_q - 1'b1;
                       else
                           neib_b_read_pending_q <= 4'd0;
                default: neib_b_read_pending_q <= neib_b_read_pending_q;
            endcase
        end
    end

    vc_mvp_get_neib #(
        .VC_CTU_X_NB  (VC_CTU_X_NB),
        .VC_CTU_Y_NB  (VC_CTU_Y_NB),
        .VC_CU_X_NB   (VC_CU_X_NB),
        .VC_CU_Y_NB   (VC_CU_Y_NB),
        .NUM_REF      (NUM_REF),
        .MAX_BLK_SZ   (2),
        .VC_EN_BI_DIR (VC_EN_BI_DIR)
    ) U_GET_NEIB (
        .neib_done_amvp       (raw_neib_done_amvp_w),
        .neib_done_mrg        (),
        .irpu2neib_b_req      (irpu2neib_b_req),
        .irpu2neib_b_addr     (irpu2neib_b_addr),
        .amvp_neib_b          (amvp_neib_b),
        .mrg_neib_b           (),
        .blk32_neib_b_r       (),
        .blk16_neib_b_r       (),
        .blk8_neib_b_r        (),
        .irpu2neib_a_req      (irpu2neib_a_req),
        .irpu2neib_a_addr     (irpu2neib_a_addr),
        .amvp_neib_a          (amvp_neib_a),
        .mrg_neib_a           (),
        .blk32_neib_a_r       (),
        .blk16_neib_a_r       (),
        .blk8_neib_a_r        (),
        .irpu2col_req         (irpu2col_req),
        .irpu2col_addr        (irpu2col_addr),
        .amvp_col_c           (),
        .mrg_col_c            (),
        .amvp_col_c_avail     (),
        .mrg_col_c_avail      (),
        .irpu2ref_req         (irpu2ref_req),
        .irpu2ref_addr        (irpu2ref_addr),
        .reflist_info         (),
        .clk_vc               (clk_vc),
        .vc_rst_z             (vc_rst_z),
        .cmdq_empty_n         (cmdq_empty_n),
        .amvp_blk_sz          (amvp_blk_sz),
        .mrg_blk_sz           (mrg_blk_sz),
        .reg_avc_mode         (1'b1),
        .reg_slice_go         (neib_reg_slice_go),
        .reg_i_slice          (1'b0),
        .reg_pic_width_ctu_m1 (pic_width_ctu_m1),
        .reg_pic_width_cu_m1  (pic_width_cu_m1),
        .reg_pic_height_cu_m1 (pic_height_cu_m1),
        // Temporal/colocated MVP is disabled; Col remains structurally present
        // but cannot start in Decoder mode.
        .reg_tmp_mvp_flag     (1'b0),
        .reg_num_ref_l0_act_m1(4'd0),
        .cur_ctu_start        (1'b0),
        .ctux                 (dec_ctux_q),
        .ctuy                 ({VC_CTU_Y_NB{1'b0}}),
        .pic_x                (12'd0),
        .pic_y                (12'd0),
        .amvp_cu_start        (amvp_cu_start),
        .mrg_cu_start         (mrg_cu_start),
        .amvp_cmd_out         (amvp_cmd_out),
        .mrg_cmd_out          (mrg_cmd_out),
        .cur_cu_upd           (cur_cu_upd),
        .cur_cu_upd_sz        (cur_cu_upd_sz),
        .cur_cu_upd_x         (cur_cu_upd_x),
        .cur_cu_upd_y         (cur_cu_upd_y),
        .cur_cu_upd_mvx       (cur_cu_upd_mvx),
        .cur_cu_upd_mvy       (cur_cu_upd_mvy),
        .cur_cu_upd_refidx    (cur_cu_upd_refidx),
        .neib_b2irpu_gnt     (neib_b2irpu_gnt),
        .neib_b2irpu_rd_lat  (neib_b2irpu_rd_lat),
        .neib_b2irpu_rd      (neib_b2irpu_rd),
        .neib_a2irpu_gnt     (neib_a2irpu_gnt),
        .neib_a2irpu_rd_lat  (neib_a2irpu_rd_lat),
        .neib_a2irpu_rd      (neib_a2irpu_rd),
        .col2irpu_gnt        (col2irpu_gnt),
        .col2irpu_rd_lat     (col2irpu_rd_lat),
        .col2irpu_rd         (col2irpu_rd),
        .ref2irpu_gnt        (ref2irpu_gnt),
        .ref2irpu_rd_lat     (ref2irpu_rd_lat),
        .ref2irpu_rd         (ref2irpu_rd),
        .blk_sz_lat_mrg      (1'b0),
        .blk_sz_lat_amvp     (blk_sz_lat_amvp),
        .n_blk_sz_mrg        (n_blk_sz_mrg),
        .n_blk_sz_amvp       (n_blk_sz_amvp)
    );

endmodule
