// T07-B backend integration TB.  Candidate arithmetic is driven only at the
// explicit seam; Neighbor, reconstruction, MC, and rolling update are real.
`timescale 1ns/1ps

module tb_vc_mvp_dec_backend_top;

    localparam integer MRG2MC_DW = 63;

    reg clk_vc;
    reg vc_rst_z;
    reg codec_mode;
    reg reg_slice_go;
    reg ccu2irpu_valid;
    wire irpu2ccu_rdy;
    reg [1:0][15:0] ccu2irpu_mvd;
    reg [3:0] ccu2irpu_ref_idx;
    reg ccu2irpu_is_skip;
    reg ccu2irpu_part_mode;
    reg [1:0] ccu2irpu_sub_idx;
    reg [2:0] dec_txn_cux;
    reg [2:0] dec_txn_cuy;
    reg [1:0] dec_txn_a_avail;
    reg [2:0] dec_txn_b_avail;
    reg [6:0] dec_txn_ctux;
    reg [6:0] dec_txn_ctuy;
    reg [6:0] reg_pic_width_ctu_m1;

    reg cand_capture_done;
    reg [31:0] dec_spatial_mvp;
    wire dec_cand_start;
    wire [16:0] dec_selected_cu_cmd;
    wire [1:0][33:0] amvp_neib_a;
    wire [2:0][33:0] amvp_neib_b;

    wire [4:0] irpu2neib_b_req;
    wire [4:0] irpu2neib_b_addr;
    wire neib_b2irpu_gnt;
    reg neib_b2irpu_rd_lat;
    reg [67:0] neib_b2irpu_rd;
    wire [1:0] irpu2neib_a_req;
    wire [1:0] irpu2neib_a_addr;
    wire neib_a2irpu_gnt;
    reg neib_a2irpu_rd_lat;
    reg [67:0] neib_a2irpu_rd;
    wire irpu2col_req;
    wire [4:0] irpu2col_addr;
    reg col2irpu_gnt;
    reg col2irpu_rd_lat;
    reg [83:0] col2irpu_rd;
    wire irpu2ref_req;
    wire [3:0] irpu2ref_addr;
    reg ref2irpu_gnt;
    reg ref2irpu_rd_lat;
    reg [32:0] ref2irpu_rd;

    reg [2:0] mc2mrg_cand_ack;
    wire [2:0] dec_mrg2mc_cand_rdy;
    wire [2:0][MRG2MC_DW-1:0] dec_mrg2mc_cand_data;
    wire [2:0] dec_mrg2mc_cand_nb;
    wire [2:0] dec_mrg2mc_cand_done;
    wire dec_neib_start;
    wire dec_recon_start;
    wire recon_done;
    wire dec_send;
    wire mc_commit;
    wire [31:0] dec_final_mv;
    wire [3:0] dec_final_ref_idx;
    wire [1:0][15:0] dec_mvd;
    wire [3:0] dec_ref_idx;
    wire dec_is_skip;
    wire dec_part_mode;
    wire [1:0] dec_sub_idx;
    wire [2:0] dec_cux;
    wire [2:0] dec_cuy;
    wire [6:0] dec_ctux;
    wire [6:0] dec_ctuy;
    wire dec_is_pic_top16;
    wire dec_is_pic_left16;
    wire [1:0] dec_a_avail;
    wire [2:0] dec_b_avail;
    wire [1:0] dec_expected_sub_idx;
    wire dec_busy;
    wire [5:0] dbg_dec_fsm_cs;
    wire raw_neib_done_amvp;
    wire neib_done_amvp;
    wire rolling_update = dut.U_NEIB_TOP.cur_cu_upd;

    integer errors;
    integer cycle_count;
    integer a_req_count;
    integer b_req_count;
    integer col_req_count;
    integer ref_req_count;
    integer transfer_count;
    integer commit_count;
    integer done_count;
    integer recon_done_count;
    integer update_count;
    integer lane_done_count0;
    integer lane_done_count1;
    integer lane_done_count2;
    integer stall_i;
    integer wait_i;
    integer before_transfers;
    integer before_commits;
    integer before_dones;
    integer before_updates;
    integer before_lane_done0;
    integer before_lane_done1;
    integer before_lane_done2;
    integer p8_transfer_base;
    integer p8_commit_base;
    integer p8_done_base;
    integer p8_update_base;
    reg [31:0] s0_final_mv;

    vc_mvp_dec_backend_top #(.MRG2MC_DW(MRG2MC_DW)) dut (
        .clk_vc                  (clk_vc),
        .vc_rst_z                (vc_rst_z),
        .codec_mode              (codec_mode),
        .reg_slice_go            (reg_slice_go),
        .ccu2irpu_valid          (ccu2irpu_valid),
        .irpu2ccu_rdy            (irpu2ccu_rdy),
        .ccu2irpu_mvd            (ccu2irpu_mvd),
        .ccu2irpu_ref_idx        (ccu2irpu_ref_idx),
        .ccu2irpu_is_skip        (ccu2irpu_is_skip),
        .ccu2irpu_part_mode      (ccu2irpu_part_mode),
        .ccu2irpu_sub_idx        (ccu2irpu_sub_idx),
        .dec_txn_cux             (dec_txn_cux),
        .dec_txn_cuy             (dec_txn_cuy),
        .dec_txn_a_avail         (dec_txn_a_avail),
        .dec_txn_b_avail         (dec_txn_b_avail),
        .dec_txn_ctux            (dec_txn_ctux),
        .dec_txn_ctuy            (dec_txn_ctuy),
        .reg_pic_width_ctu_m1    (reg_pic_width_ctu_m1),
        .cand_capture_done       (cand_capture_done),
        .dec_spatial_mvp         (dec_spatial_mvp),
        .dec_cand_start          (dec_cand_start),
        .dec_selected_cu_cmd     (dec_selected_cu_cmd),
        .amvp_neib_a             (amvp_neib_a),
        .amvp_neib_b             (amvp_neib_b),
        .irpu2neib_b_req         (irpu2neib_b_req),
        .irpu2neib_b_addr        (irpu2neib_b_addr),
        .neib_b2irpu_gnt         (neib_b2irpu_gnt),
        .neib_b2irpu_rd_lat      (neib_b2irpu_rd_lat),
        .neib_b2irpu_rd          (neib_b2irpu_rd),
        .irpu2neib_a_req         (irpu2neib_a_req),
        .irpu2neib_a_addr        (irpu2neib_a_addr),
        .neib_a2irpu_gnt         (neib_a2irpu_gnt),
        .neib_a2irpu_rd_lat      (neib_a2irpu_rd_lat),
        .neib_a2irpu_rd          (neib_a2irpu_rd),
        .irpu2col_req            (irpu2col_req),
        .irpu2col_addr           (irpu2col_addr),
        .col2irpu_gnt            (col2irpu_gnt),
        .col2irpu_rd_lat         (col2irpu_rd_lat),
        .col2irpu_rd             (col2irpu_rd),
        .irpu2ref_req            (irpu2ref_req),
        .irpu2ref_addr           (irpu2ref_addr),
        .ref2irpu_gnt            (ref2irpu_gnt),
        .ref2irpu_rd_lat         (ref2irpu_rd_lat),
        .ref2irpu_rd             (ref2irpu_rd),
        .mc2mrg_cand_ack         (mc2mrg_cand_ack),
        .dec_mrg2mc_cand_rdy     (dec_mrg2mc_cand_rdy),
        .dec_mrg2mc_cand_data    (dec_mrg2mc_cand_data),
        .dec_mrg2mc_cand_nb      (dec_mrg2mc_cand_nb),
        .dec_mrg2mc_cand_done    (dec_mrg2mc_cand_done),
        .dec_neib_start          (dec_neib_start),
        .dec_recon_start         (dec_recon_start),
        .recon_done              (recon_done),
        .dec_send                (dec_send),
        .mc_commit               (mc_commit),
        .dec_final_mv            (dec_final_mv),
        .dec_final_ref_idx       (dec_final_ref_idx),
        .dec_mvd                 (dec_mvd),
        .dec_ref_idx             (dec_ref_idx),
        .dec_is_skip             (dec_is_skip),
        .dec_part_mode           (dec_part_mode),
        .dec_sub_idx             (dec_sub_idx),
        .dec_cux                 (dec_cux),
        .dec_cuy                 (dec_cuy),
        .dec_ctux                (dec_ctux),
        .dec_ctuy                (dec_ctuy),
        .dec_is_pic_top16        (dec_is_pic_top16),
        .dec_is_pic_left16       (dec_is_pic_left16),
        .dec_a_avail             (dec_a_avail),
        .dec_b_avail             (dec_b_avail),
        .dec_expected_sub_idx    (dec_expected_sub_idx),
        .dec_busy                (dec_busy),
        .dbg_dec_fsm_cs          (dbg_dec_fsm_cs),
        .raw_neib_done_amvp      (raw_neib_done_amvp),
        .neib_done_amvp          (neib_done_amvp)
    );

    initial begin
        clk_vc = 1'b0;
        forever #5 clk_vc = ~clk_vc;
    end

    assign neib_a2irpu_gnt = |irpu2neib_a_req;
    assign neib_b2irpu_gnt = |irpu2neib_b_req;

    task check;
        input condition;
        input [8*120-1:0] message;
        begin
            if (condition !== 1'b1) begin
                $display("FAIL cycle=%0d: %0s", cycle_count, message);
                $fatal(1);
            end
        end
    endtask

    function [16:0] expected_cu_command;
        input skip_f;
        input part_f;
        input [1:0] sub_f;
        input [2:0] x_f;
        input [2:0] y_f;
        input [1:0] a_f;
        input [2:0] b_f;
        reg [2:0] physical_x_f;
        reg [2:0] physical_y_f;
        reg [2:0] size_f;
        begin
            if (part_f) begin
                physical_x_f = x_f + sub_f[0];
                physical_y_f = y_f + sub_f[1];
                size_f = 3'b001;
            end else begin
                physical_x_f = x_f;
                physical_y_f = y_f;
                size_f = 3'b010;
            end
            expected_cu_command = {size_f, 1'b0, skip_f, 1'b0,
                                   a_f, b_f, physical_y_f, physical_x_f};
        end
    endfunction

    function [MRG2MC_DW-1:0] expected_packet;
        input part_f;
        input [1:0] sub_f;
        input [2:0] x_f;
        input [2:0] y_f;
        input [6:0] ctu_x_f;
        input [6:0] ctu_y_f;
        input [1:0] ref_f;
        input [31:0] mv_f;
        reg [2:0] physical_x_f;
        reg [2:0] physical_y_f;
        reg [1:0] size_f;
        reg [11:0] pic_x_f;
        reg [11:0] pic_y_f;
        begin
            if (part_f) begin
                physical_x_f = x_f + sub_f[0];
                physical_y_f = y_f + sub_f[1];
                size_f = 2'd1;
            end else begin
                physical_x_f = {x_f[2:1], 1'b0};
                physical_y_f = {y_f[2:1], 1'b0};
                size_f = 2'd2;
            end
            pic_x_f = {ctu_x_f[5:0], physical_x_f, 3'b000};
            pic_y_f = {ctu_y_f[5:0], physical_y_f, 3'b000};
            expected_packet = {1'b1, pic_y_f, pic_x_f, size_f, size_f,
                               ref_f, mv_f};
        end
    endfunction

    // One-cycle response model with real request/grant/rd_lat plumbing.  All
    // memory words are zero so the P_SKIP A1/B1-zero cases use real neighbors.
    always @(posedge clk_vc or negedge vc_rst_z) begin
        if (!vc_rst_z) begin
            neib_a2irpu_rd_lat <= 1'b0;
            neib_b2irpu_rd_lat <= 1'b0;
            neib_a2irpu_rd <= 68'd0;
            neib_b2irpu_rd <= 68'd0;
        end else begin
            neib_a2irpu_rd_lat <= |irpu2neib_a_req;
            neib_b2irpu_rd_lat <= |irpu2neib_b_req;
            neib_a2irpu_rd <= 68'd0;
            neib_b2irpu_rd <= 68'd0;
        end
    end

    always @(posedge clk_vc or negedge vc_rst_z) begin
        if (!vc_rst_z) begin
            cycle_count = 0;
            a_req_count = 0;
            b_req_count = 0;
            col_req_count = 0;
            ref_req_count = 0;
            transfer_count = 0;
            commit_count = 0;
            done_count = 0;
            recon_done_count = 0;
            update_count = 0;
            lane_done_count0 = 0;
            lane_done_count1 = 0;
            lane_done_count2 = 0;
        end else begin
            cycle_count = cycle_count + 1;
            if (irpu2neib_a_req[0] && neib_a2irpu_gnt)
                a_req_count = a_req_count + 1;
            if (irpu2neib_b_req[0] && neib_b2irpu_gnt)
                b_req_count = b_req_count + 1;
            if (irpu2col_req)
                col_req_count = col_req_count + 1;
            if (irpu2ref_req)
                ref_req_count = ref_req_count + 1;

            check(mc_commit === (|(dec_mrg2mc_cand_rdy & mc2mrg_cand_ack)),
                  "mc_commit must equal selected-lane valid/ack handshake");
            check((^dec_mrg2mc_cand_rdy) !== 1'bx &&
                  (^dec_mrg2mc_cand_data) !== 1'bx,
                  "MC valid/data vectors must never contain X/Z");
            check((dec_send === 1'b0) || (dec_send === 1'b1),
                  "dec_send must never contain X/Z");
            check((recon_done === 1'b0) || (recon_done === 1'b1),
                  "recon_done must never contain X/Z");
            check((^irpu2neib_a_req) !== 1'bx &&
                  (^irpu2neib_b_req) !== 1'bx,
                  "A/B Neighbor request vectors must never contain X/Z");
            check(irpu2col_req === 1'b0 && irpu2ref_req === 1'b0,
                  "disabled Col/RefList requests must remain known low");
            check((^dec_mrg2mc_cand_done) !== 1'bx,
                  "MC done vector must never contain X/Z");
            check((rolling_update === 1'b0) || (rolling_update === 1'b1),
                  "rolling-update indication must never contain X/Z");
            check(dec_mrg2mc_cand_nb === 3'b000,
                  "unused merge-neighbor number must remain zero");
            if (mc_commit) begin
                transfer_count = transfer_count + 1;
                commit_count = commit_count + 1;
            end
            if (dec_mrg2mc_cand_done[0]) begin
                lane_done_count0 = lane_done_count0 + 1;
                done_count = done_count + 1;
            end
            if (dec_mrg2mc_cand_done[1]) begin
                lane_done_count1 = lane_done_count1 + 1;
                done_count = done_count + 1;
            end
            if (dec_mrg2mc_cand_done[2]) begin
                lane_done_count2 = lane_done_count2 + 1;
                done_count = done_count + 1;
            end
            if (rolling_update)
                update_count = update_count + 1;
            if (recon_done)
                recon_done_count = recon_done_count + 1;
            if (irpu2col_req || irpu2ref_req)
                $fatal(1, "disabled Col/RefList request observed");
        end
    end

    task prepare_to_send;
        input skip_f;
        input part_f;
        input [1:0] sub_f;
        input [2:0] x_f;
        input [2:0] y_f;
        input [6:0] ctu_x_f;
        input [6:0] ctu_y_f;
        input [1:0] a_f;
        input [2:0] b_f;
        input [15:0] mvd_x_f;
        input [15:0] mvd_y_f;
        input [31:0] mvp_f;
        input [31:0] final_mv_f;
        input [3:0] final_ref_f;
        integer cand_wait;
        integer send_wait;
        reg [16:0] command_f;
        begin
            check(irpu2ccu_rdy === 1'b1,
                  "controller must be ready before transaction acceptance");
            check(dec_expected_sub_idx === sub_f,
                  "P8 sub-index must match the last committed sub-index");
            check(dec_send === 1'b0 && mc_commit === 1'b0,
                  "new transaction must not overlap a prior MC send");
            @(negedge clk_vc);
            ccu2irpu_valid = 1'b1;
            ccu2irpu_mvd[0] = mvd_x_f;
            ccu2irpu_mvd[1] = mvd_y_f;
            ccu2irpu_ref_idx = 4'd0;
            ccu2irpu_is_skip = skip_f;
            ccu2irpu_part_mode = part_f;
            ccu2irpu_sub_idx = sub_f;
            dec_txn_cux = x_f;
            dec_txn_cuy = y_f;
            dec_txn_ctux = ctu_x_f;
            dec_txn_ctuy = ctu_y_f;
            dec_txn_a_avail = a_f;
            dec_txn_b_avail = b_f;
            @(posedge clk_vc);
            #1;
            check(dec_neib_start === 1'b1,
                  "accepted beat must launch the real Neighbor stage");
            check(dec_send === 1'b0,
                  "dec_send must remain low before reconstruction");
            @(negedge clk_vc);
            ccu2irpu_valid = 1'b0;

            begin : wait_for_candidate
                for (cand_wait = 0; cand_wait < 100; cand_wait = cand_wait + 1) begin
                    @(negedge clk_vc);
                    if (dec_cand_start === 1'b1)
                        disable wait_for_candidate;
                end
            end
            check(dec_cand_start === 1'b1,
                  "real Neighbor completion must reach Candidate seam");
            command_f = expected_cu_command(skip_f, part_f, sub_f,
                                             x_f, y_f, a_f, b_f);
            check(dec_selected_cu_cmd === command_f,
                  "Candidate seam must receive exact selected command");
            check((^amvp_neib_a) !== 1'bx && (^amvp_neib_b) !== 1'bx,
                  "real A/B Neighbor values must be known at Candidate seam");
            check(dec_ctux === ctu_x_f && dec_ctuy === ctu_y_f &&
                  dec_cux === x_f && dec_cuy === y_f,
                  "Candidate seam coordinates must be accepted transaction context");
            check(dec_is_pic_top16 === ({ctu_y_f, y_f[2:1]} == 0) &&
                  dec_is_pic_left16 === ({ctu_x_f, x_f} == 0),
                  "picture flags must use accepted CTU/CU coordinates");
            if (part_f && (sub_f == 2'd1) && (s0_final_mv != 32'd0))
                check(amvp_neib_a[1] === {2'b00, s0_final_mv},
                      "committed P8 S0 must appear in real rolling A1 for S1");
            if (skip_f && a_f[1]) begin
                check(dut.U_RECON.dec_skip_a1_mv === amvp_neib_a[1][31:0],
                      "P_SKIP A1 input must be the real amvp_neib_a[1] word");
                check(dut.U_RECON.dec_skip_a1_avail === a_f[1],
                      "P_SKIP A1 availability must be dec_a_avail[1]");
            end
            if (skip_f && b_f[1]) begin
                check(dut.U_RECON.dec_skip_b1_mv === amvp_neib_b[1][31:0],
                      "P_SKIP B1 input must be the real amvp_neib_b[1] word");
                check(dut.U_RECON.dec_skip_b1_avail === b_f[1],
                      "P_SKIP B1 availability must be dec_b_avail[1]");
            end

            dec_spatial_mvp = mvp_f;
            cand_capture_done = 1'b1;
            @(posedge clk_vc);
            #1;
            check(dec_recon_start === 1'b1,
                  "Candidate seam completion must launch reconstruction normally");
            cand_capture_done = 1'b0;
            check(dec_send === 1'b0,
                  "dec_send must remain low until real reconstruction completes");

            begin : wait_for_send
                for (send_wait = 0; send_wait < 20; send_wait = send_wait + 1) begin
                    @(negedge clk_vc);
                    if (dec_send === 1'b1)
                        disable wait_for_send;
                end
            end
            check(dec_send === 1'b1 && dec_busy === 1'b1,
                  "real recon_done must move the controller into DEC_SEND");
            check(dec_final_mv === final_mv_f,
                  "reconstruction must produce exact expected final MV");
            check(dec_final_ref_idx === final_ref_f,
                  "reconstruction must produce exact expected reference index");
            check(dec_ref_idx === 4'd0,
                  "Phase-1 held reference index must be zero");
            check(dec_expected_sub_idx === sub_f,
                  "expected P8 index must not advance before MC commit");
        end
    endtask

    task run_transaction;
        input skip_f;
        input part_f;
        input [1:0] sub_f;
        input [2:0] x_f;
        input [2:0] y_f;
        input [6:0] ctu_x_f;
        input [6:0] ctu_y_f;
        input [1:0] a_f;
        input [2:0] b_f;
        input [15:0] mvd_x_f;
        input [15:0] mvd_y_f;
        input [31:0] mvp_f;
        input [31:0] final_mv_f;
        input [3:0] final_ref_f;
        input integer stall_cycles;
        integer lane_f;
        integer next_sub_f;
        reg [MRG2MC_DW-1:0] packet_f;
        reg [16:0] command_f;
        reg [2:0] lane_mask_f;
        begin
            before_transfers = transfer_count;
            before_commits = commit_count;
            before_dones = done_count;
            before_updates = update_count;
            before_lane_done0 = lane_done_count0;
            before_lane_done1 = lane_done_count1;
            before_lane_done2 = lane_done_count2;
            lane_f = part_f ? 0 : 1;
            lane_mask_f = part_f ? 3'b001 : 3'b010;
            mc2mrg_cand_ack = (stall_cycles == 0) ? lane_mask_f : 3'b000;
            if (stall_cycles == 0) begin
                check(mc2mrg_cand_ack === lane_mask_f &&
                      dec_mrg2mc_cand_rdy === 3'b000 && mc_commit === 1'b0,
                      "immediate-ack case must present ack before DEC_SEND without early commit");
            end
            prepare_to_send(skip_f, part_f, sub_f, x_f, y_f,
                            ctu_x_f, ctu_y_f, a_f, b_f,
                            mvd_x_f, mvd_y_f, mvp_f,
                            final_mv_f, final_ref_f);
            command_f = expected_cu_command(skip_f, part_f, sub_f,
                                             x_f, y_f, a_f, b_f);
            packet_f = expected_packet(part_f, sub_f, x_f, y_f,
                                       ctu_x_f, ctu_y_f,
                                       final_ref_f[1:0], final_mv_f);
            check(dec_mrg2mc_cand_rdy === lane_mask_f,
                  "only the mode-selected MC lane may be valid");
            check(dec_mrg2mc_cand_data[lane_f] === packet_f,
                  "MC packet must match the real reconstructed MV and held context");
            check(dec_mrg2mc_cand_data[lane_f][37:36] === (part_f ? 2'd1 : 2'd2) &&
                  dec_mrg2mc_cand_data[lane_f][35:34] === (part_f ? 2'd1 : 2'd2),
                  "both packet size fields must match P8/P16/P_SKIP mode");
            if (part_f)
                check(dec_mrg2mc_cand_data[1] === {MRG2MC_DW{1'b0}} &&
                      dec_mrg2mc_cand_data[2] === {MRG2MC_DW{1'b0}},
                      "P8 unselected MC lanes must remain zero");
            else
                check(dec_mrg2mc_cand_data[0] === {MRG2MC_DW{1'b0}} &&
                      dec_mrg2mc_cand_data[2] === {MRG2MC_DW{1'b0}},
                      "P16/P_SKIP unselected MC lanes must remain zero");
            check(dec_mrg2mc_cand_nb === 3'b000,
                  "Decoder backend must not request an MRG neighbor number");
            check(dec_mrg2mc_cand_done === 3'b000,
                  "done must be low before the selected MC transfer edge");

            if (stall_cycles > 0) begin
                for (stall_i = 0; stall_i < stall_cycles; stall_i = stall_i + 1) begin
                    check(dec_send === 1'b1 && irpu2ccu_rdy === 1'b0,
                          "DEC_SEND must hold under MC backpressure");
                    check(dec_mrg2mc_cand_rdy === lane_mask_f,
                          "selected valid must remain asserted during backpressure");
                    check(dec_mrg2mc_cand_data[lane_f] === packet_f,
                          "MC packet must remain bit-stable during backpressure");
                    check(dec_final_mv === final_mv_f &&
                          dec_final_ref_idx === final_ref_f,
                          "final MV/ref must remain stable during backpressure");
                    check(dec_selected_cu_cmd === command_f &&
                          dec_ctux === ctu_x_f && dec_ctuy === ctu_y_f &&
                          dec_cux === x_f && dec_cuy === y_f &&
                          dec_is_skip === skip_f && dec_part_mode === part_f &&
                          dec_sub_idx === sub_f,
                          "command and all transaction coordinates/mode must hold");
                    check(mc_commit === 1'b0 && rolling_update === 1'b0 &&
                          dec_mrg2mc_cand_done === 3'b000,
                          "stall must not commit, update rolling state, or pulse done");

                    ccu2irpu_valid = 1'b0;
                    ccu2irpu_mvd = 32'hdead_beef;
                    ccu2irpu_ref_idx = 4'hf;
                    ccu2irpu_is_skip = ~skip_f;
                    ccu2irpu_part_mode = ~part_f;
                    ccu2irpu_sub_idx = ~sub_f;
                    dec_txn_cux = ~x_f;
                    dec_txn_cuy = ~y_f;
                    dec_txn_ctux = 7'h55;
                    dec_txn_ctuy = 7'h2a;
                    dec_txn_a_avail = ~a_f;
                    dec_txn_b_avail = ~b_f;
                    dec_spatial_mvp = ~mvp_f;
                    @(posedge clk_vc);
                    #1;
                    check(dec_send === 1'b1 && dec_mrg2mc_cand_rdy === lane_mask_f &&
                          dec_mrg2mc_cand_data[lane_f] === packet_f,
                          "send packet must hold across every stalled clock");
                    check(mc_commit === 1'b0 && rolling_update === 1'b0 &&
                          dec_mrg2mc_cand_done === 3'b000,
                          "stalled clock must not retire or pulse done/update");
                    check(dec_final_mv === final_mv_f &&
                          dec_selected_cu_cmd === command_f &&
                          dec_ctux === ctu_x_f && dec_ctuy === ctu_y_f,
                          "registered result and command context must ignore upstream changes");
                    @(negedge clk_vc);
                end
                mc2mrg_cand_ack = lane_mask_f;
                #1;
            end

            check(dec_send === 1'b1 &&
                  irpu2ccu_rdy === 1'b0 &&
                  dec_mrg2mc_cand_rdy === lane_mask_f &&
                  (|(dec_mrg2mc_cand_rdy & mc2mrg_cand_ack)) === 1'b1,
                  "selected lane must handshake only when valid and ack overlap");
            check(mc_commit === 1'b1,
                  "mc_commit must be generated by selected valid/ack handshake");
            @(posedge clk_vc);
            #1;
            check(dec_send === 1'b0 && dec_busy === 1'b0 &&
                  irpu2ccu_rdy === 1'b1,
                  "ready may reopen only after the MC acceptance edge");
            check(mc_commit === 1'b0 && dec_mrg2mc_cand_rdy === 3'b000,
                  "accepted packet must not transfer a second time");
            check(dec_mrg2mc_cand_done === lane_mask_f,
                  "MC done must pulse on exactly the selected lane after acceptance");
            check(dec_final_mv === final_mv_f &&
                  dec_final_ref_idx === final_ref_f,
                  "reconstruction result must remain held after send retires");
            next_sub_f = part_f ? ((sub_f == 2'd3) ? 0 : sub_f + 1) : 0;
            check(dec_expected_sub_idx === next_sub_f[1:0],
                  "P8 order advances only on MC commit");

            @(posedge clk_vc);
            #1;
            check(dec_mrg2mc_cand_done === 3'b000,
                  "MC done must be exactly one cycle");
            check(transfer_count == before_transfers + 1 &&
                  commit_count == before_commits + 1 &&
                  update_count == before_updates + 1,
                  "one accepted MC packet must cause one transfer/commit/update");
            check(done_count == before_dones + 1,
                  "one accepted MC packet must cause one done pulse");
            check(lane_done_count0 == before_lane_done0 + (part_f ? 1 : 0) &&
                  lane_done_count1 == before_lane_done1 + (part_f ? 0 : 1) &&
                  lane_done_count2 == before_lane_done2,
                  "done pulse must occur only on the selected block-size lane");
            mc2mrg_cand_ack = 3'b000;
            $display("T07-B MC TRACE: cycle=%0d lane=%0d packet=%h final_mv=%h backpressure=%0d commit=%0d done=%0d update=%0d",
                     cycle_count, lane_f, packet_f, final_mv_f, stall_cycles,
                     commit_count - before_commits, done_count - before_dones,
                     update_count - before_updates);
        end
    endtask

    task flush_send;
        input use_codec_flush;
        integer stale_lane;
        begin
            check(dec_send === 1'b1 && mc2mrg_cand_ack === 3'b000,
                  "flush test must be stalled in DEC_SEND with ack low");
            check(recon_done === 1'b0,
                  "recon_done must already be a one-cycle pulse before flush");
            stale_lane = dec_part_mode ? 0 : 1;
            @(negedge clk_vc);
            if (use_codec_flush)
                codec_mode = 1'b0;
            else
                reg_slice_go = 1'b1;
            #1;
            check(dec_mrg2mc_cand_rdy === 3'b000 &&
                  dec_mrg2mc_cand_data === '0,
                  "flush assertion must immediately suppress valid and packet");
            @(posedge clk_vc);
            #1;
            check(dec_send === 1'b0 && mc_commit === 1'b0 &&
                  dec_mrg2mc_cand_rdy === 3'b000 &&
                  dec_mrg2mc_cand_data === '0,
                  "flush edge must cancel send and zero the MC packet");
            check(dec_mrg2mc_cand_done === 3'b000 && rolling_update === 1'b0,
                  "flush must suppress stale done and rolling update");
            mc2mrg_cand_ack = (stale_lane == 0) ? 3'b001 : 3'b010;
            repeat (2) begin
                @(posedge clk_vc);
                #1;
                check(dec_send === 1'b0 && mc_commit === 1'b0 &&
                      dec_mrg2mc_cand_rdy === 3'b000 &&
                      dec_mrg2mc_cand_done === 3'b000 &&
                      rolling_update === 1'b0,
                      "stale ack after flush cannot retire or update cancelled work");
            end
            @(negedge clk_vc);
            mc2mrg_cand_ack = 3'b000;
            if (use_codec_flush)
                codec_mode = 1'b1;
            else
                reg_slice_go = 1'b0;
        end
    endtask

    initial begin
        errors = 0;
        vc_rst_z = 1'b0;
        codec_mode = 1'b1;
        reg_slice_go = 1'b0;
        ccu2irpu_valid = 1'b0;
        ccu2irpu_mvd = 32'd0;
        ccu2irpu_ref_idx = 4'd0;
        ccu2irpu_is_skip = 1'b0;
        ccu2irpu_part_mode = 1'b0;
        ccu2irpu_sub_idx = 2'd0;
        dec_txn_cux = 3'd0;
        dec_txn_cuy = 3'd0;
        dec_txn_a_avail = 2'd0;
        dec_txn_b_avail = 3'd0;
        dec_txn_ctux = 7'd0;
        dec_txn_ctuy = 7'd0;
        reg_pic_width_ctu_m1 = 7'd7;
        cand_capture_done = 1'b0;
        dec_spatial_mvp = 32'd0;
        col2irpu_gnt = 1'b0;
        col2irpu_rd_lat = 1'b0;
        col2irpu_rd = 84'd0;
        ref2irpu_gnt = 1'b0;
        ref2irpu_rd_lat = 1'b0;
        ref2irpu_rd = 33'd0;
        mc2mrg_cand_ack = 3'b000;
        s0_final_mv = 32'd0;
        repeat (2) @(posedge clk_vc);
        @(negedge clk_vc);
        check(dec_send === 1'b0 && dec_final_mv === 32'd0 &&
              dec_final_ref_idx === 4'd0 && recon_done === 1'b0,
              "asynchronous reset state must be clean");
        vc_rst_z = 1'b1;

        $display("CASE A: P16 non-skip, immediate MC acknowledge");
        run_transaction(1'b0, 1'b0, 2'd0, 3'd2, 3'd2,
                        7'd0, 7'd0, 2'b11, 3'b111,
                        16'h0005, 16'h0014, 32'hff9c0032,
                        32'hffb00037, 4'd0, 0);

        $display("CASE B: P16 non-skip, three-cycle MC backpressure");
        run_transaction(1'b0, 1'b0, 2'd0, 3'd2, 3'd2,
                        7'd3, 7'd1, 2'b00, 3'b000,
                        16'h0001, 16'h0002, 32'h00010002,
                        32'h00030003, 4'd0, 3);

        $display("CASE C: P8 S0 -> S1 -> S2 -> S3");
        p8_transfer_base = transfer_count;
        p8_commit_base = commit_count;
        p8_done_base = done_count;
        p8_update_base = update_count;
        run_transaction(1'b0, 1'b1, 2'd0, 3'd2, 3'd2,
                        7'd0, 7'd0, 2'b11, 3'b111,
                        16'd0, 16'd0, 32'h11110001,
                        32'h11110001, 4'd0, 0);
        s0_final_mv = 32'h11110001;
        run_transaction(1'b0, 1'b1, 2'd1, 3'd2, 3'd2,
                        7'd0, 7'd0, 2'b11, 3'b000,
                        16'd0, 16'd0, 32'h22220002,
                        32'h22220002, 4'd0, 0);
        check(amvp_neib_a[1] === {2'b00, s0_final_mv},
              "committed P8 S0 must be visible in following rolling Neighbor A1");
        run_transaction(1'b0, 1'b1, 2'd2, 3'd2, 3'd2,
                        7'd0, 7'd0, 2'b00, 3'b000,
                        16'd0, 16'd0, 32'h33330003,
                        32'h33330003, 4'd0, 0);
        run_transaction(1'b0, 1'b1, 2'd3, 3'd2, 3'd2,
                        7'd0, 7'd0, 2'b00, 3'b000,
                        16'd0, 16'd0, 32'h44440004,
                        32'h44440004, 4'd0, 0);
        check(transfer_count == p8_transfer_base + 4 &&
              commit_count == p8_commit_base + 4 &&
              done_count == p8_done_base + 4 &&
              update_count == p8_update_base + 4,
              "P8 S0-S3 must produce exactly four transfers/commits/dones/updates");

        $display("CASE D: P_SKIP picture-boundary and zero-neighbor rules");
        run_transaction(1'b1, 1'b0, 2'd0, 3'd4, 3'd0,
                        7'd1, 7'd0, 2'b00, 3'b000,
                        16'h1234, 16'h5678, 32'h12345678,
                        32'd0, 4'd0, 0);
        check(dec_is_pic_top16 === 1'b1,
              "P_SKIP top trigger must use accepted top-boundary context");
        run_transaction(1'b1, 1'b0, 2'd0, 3'd0, 3'd4,
                        7'd0, 7'd1, 2'b00, 3'b000,
                        16'h1234, 16'h5678, 32'h12345678,
                        32'd0, 4'd0, 0);
        check(dec_is_pic_left16 === 1'b1,
              "P_SKIP left trigger must use accepted left-boundary context");

        // Flush rolling state before each external zero-neighbor trigger.
        @(negedge clk_vc); reg_slice_go = 1'b1;
        @(posedge clk_vc); #1;
        @(negedge clk_vc); reg_slice_go = 1'b0;
        run_transaction(1'b1, 1'b0, 2'd0, 3'd4, 3'd4,
                        7'd1, 7'd1, 2'b10, 3'b000,
                        16'h2222, 16'h3333, 32'h12345678,
                        32'd0, 4'd0, 0);
        check(amvp_neib_a[1][31:0] === 32'd0,
              "P_SKIP A1-zero trigger must use zero from real Neighbor response");

        @(negedge clk_vc); reg_slice_go = 1'b1;
        @(posedge clk_vc); #1;
        @(negedge clk_vc); reg_slice_go = 1'b0;
        run_transaction(1'b1, 1'b0, 2'd0, 3'd4, 3'd4,
                        7'd1, 7'd1, 2'b00, 3'b010,
                        16'h2222, 16'h3333, 32'h12345678,
                        32'd0, 4'd0, 0);
        check(amvp_neib_b[1][31:0] === 32'd0,
              "P_SKIP B1-zero trigger must use zero from real Neighbor response");

        @(negedge clk_vc); reg_slice_go = 1'b1;
        @(posedge clk_vc); #1;
        @(negedge clk_vc); reg_slice_go = 1'b0;
        run_transaction(1'b1, 1'b0, 2'd0, 3'd2, 3'd2,
                        7'd0, 7'd0, 2'b00, 3'b000,
                        16'h1111, 16'h2222, 32'hfffe1234,
                        32'hfffe1234, 4'd0, 0);
        check(dec_is_pic_top16 === 1'b0 && dec_is_pic_left16 === 1'b0,
              "zero CTU with nonzero local CU X/Y must not assert picture boundaries");

        run_transaction(1'b1, 1'b0, 2'd0, 3'd2, 3'd0,
                        7'd0, 7'd0, 2'b00, 3'b000,
                        16'h1111, 16'h2222, 32'h76543210,
                        32'd0, 4'd0, 0);
        check(dec_is_pic_left16 === 1'b0,
              "CTU X zero with local CU X nonzero must remain non-left");
        run_transaction(1'b1, 1'b0, 2'd0, 3'd0, 3'd2,
                        7'd0, 7'd0, 2'b00, 3'b000,
                        16'h1111, 16'h2222, 32'h76543210,
                        32'd0, 4'd0, 0);
        check(dec_is_pic_top16 === 1'b0,
              "CTU Y zero with local CU Y[2:1] nonzero must remain non-top");

        $display("CASE F: reg_slice_go and codec_mode flush cancel DEC_SEND");
        mc2mrg_cand_ack = 3'b000;
        prepare_to_send(1'b0, 1'b0, 2'd0, 3'd2, 3'd2,
                        7'd0, 7'd0, 2'b00, 3'b000,
                        16'd0, 16'd0, 32'h01020304,
                        32'h01020304, 4'd0);
        flush_send(1'b0);
        prepare_to_send(1'b0, 1'b0, 2'd0, 3'd2, 3'd2,
                        7'd0, 7'd0, 2'b00, 3'b000,
                        16'd0, 16'd0, 32'h11112222,
                        32'h11112222, 4'd0);
        flush_send(1'b1);

        check(col_req_count == 0,
              "Col request count must remain zero across backend run");
        check(ref_req_count == 0,
              "RefList request count must remain zero across backend run");
        check(transfer_count == commit_count && commit_count == done_count &&
              commit_count == update_count,
              "all completed MC transfers must have one commit/done/update");
        check(transfer_count == 13 && commit_count == 13 &&
              done_count == 13 && update_count == 13,
              "expected thirteen completed non-flushed backend transactions");
        check(recon_done_count == 15,
              "real reconstruction must complete each accepted transaction once");
        check(lane_done_count0 == 4 && lane_done_count1 == 9 &&
              lane_done_count2 == 0,
              "P8 uses lane 0 and P16/P_SKIP use lane 1 for all completed transfers");
        $display("T07-B COUNTS: transfer=%0d commit=%0d done=%0d update=%0d lane_done={%0d,%0d,%0d}",
                 transfer_count, commit_count, done_count, update_count,
                 lane_done_count0, lane_done_count1, lane_done_count2);
        $display("T07-B REQUESTS: A=%0d B=%0d Col=%0d RefList=%0d",
                 a_req_count, b_req_count, col_req_count, ref_req_count);
        $display("T07-B BACKEND INTEGRATION RESULT: PASS");
        $finish;
    end

endmodule
