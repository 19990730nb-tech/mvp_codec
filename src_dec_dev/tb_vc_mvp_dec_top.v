`timescale 1ns/1ps

module tb_vc_mvp_dec_top;
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
    wire dec_cand_start;
    wire cand_capture_done;
    wire cand_busy;
    wire [31:0] dec_spatial_mvp;
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
    wire [16:0] dec_selected_cu_cmd;
    wire [1:0][33:0] amvp_neib_a;
    wire [2:0][33:0] amvp_neib_b;
    wire [1:0] dec_a_avail;
    wire [2:0] dec_b_avail;
    wire [1:0] dec_expected_sub_idx;
    wire dec_busy;
    wire [5:0] dbg_dec_fsm_cs;
    wire raw_neib_done_amvp;
    wire neib_done_amvp;
    wire rolling_update = dut.U_BACKEND.U_NEIB_TOP.cur_cu_upd;

    reg [31:0] mem_a1;
    reg [31:0] mem_b0;
    reg [31:0] mem_b1;
    reg [31:0] mem_b2;
    integer b_response_index;
    integer cycle_count;
    integer accepted_count;
    integer candidate_count;
    integer recon_count;
    integer transfer_count;
    integer commit_count;
    integer done_count;
    integer update_count;
    integer lane_done0;
    integer lane_done1;
    integer lane_done2;
    integer a_request_count;
    integer b_request_count;
    integer col_request_count;
    integer ref_request_count;
    integer loop_i;
    integer before_commit;
    integer before_done;
    integer before_update;
    integer before_transfer;

    vc_mvp_dec_top #(.MRG2MC_DW(MRG2MC_DW)) dut (
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
        .dec_cand_start          (dec_cand_start),
        .cand_capture_done       (cand_capture_done),
        .cand_busy               (cand_busy),
        .dec_spatial_mvp         (dec_spatial_mvp),
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
        .dec_selected_cu_cmd     (dec_selected_cu_cmd),
        .amvp_neib_a             (amvp_neib_a),
        .amvp_neib_b             (amvp_neib_b),
        .dec_a_avail             (dec_a_avail),
        .dec_b_avail             (dec_b_avail),
        .dec_expected_sub_idx    (dec_expected_sub_idx),
        .dec_busy                (dec_busy),
        .dbg_dec_fsm_cs          (dbg_dec_fsm_cs),
        .raw_neib_done_amvp      (raw_neib_done_amvp),
        .neib_done_amvp          (neib_done_amvp)
    );

    always #5 clk_vc = ~clk_vc;

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

    function [16:0] expected_command;
        input skip_f;
        input part_f;
        input [1:0] sub_f;
        input [2:0] x_f;
        input [2:0] y_f;
        input [1:0] a_f;
        input [2:0] b_f;
        reg [2:0] px;
        reg [2:0] py;
        reg [2:0] size_f;
        begin
            if (part_f) begin
                px = x_f + sub_f[0];
                py = y_f + sub_f[1];
                size_f = 3'b001;
            end else begin
                px = x_f;
                py = y_f;
                size_f = 3'b010;
            end
            expected_command = {size_f, 1'b0,
                                skip_f, 1'b0, a_f, b_f, py, px};
        end
    endfunction

    function [MRG2MC_DW-1:0] expected_packet;
        input part_f;
        input [1:0] sub_f;
        input [2:0] x_f;
        input [2:0] y_f;
        input [6:0] ctu_x_f;
        input [6:0] ctu_y_f;
        input [31:0] mv_f;
        reg [2:0] px;
        reg [2:0] py;
        reg [1:0] size_f;
        reg [11:0] pic_x;
        reg [11:0] pic_y;
        begin
            if (part_f) begin
                px = x_f + sub_f[0];
                py = y_f + sub_f[1];
                size_f = 2'd1;
            end else begin
                px = {x_f[2:1], 1'b0};
                py = {y_f[2:1], 1'b0};
                size_f = 2'd2;
            end
            pic_x = {ctu_x_f[5:0], px, 3'b000};
            pic_y = {ctu_y_f[5:0], py, 3'b000};
            expected_packet = {1'b1, pic_y, pic_x, size_f, size_f,
                               2'b00, mv_f};
        end
    endfunction

    // One-cycle SRAM response model. At P16 coordinate (2,2), the real legacy
    // Neighbor mapper consumes B2/B1/B0 from the first/second/third B pair.
    always @(posedge clk_vc or negedge vc_rst_z) begin
        if (!vc_rst_z) begin
            neib_a2irpu_rd_lat <= 1'b0;
            neib_b2irpu_rd_lat <= 1'b0;
            neib_a2irpu_rd <= 68'd0;
            neib_b2irpu_rd <= 68'd0;
            b_response_index <= 0;
        end else begin
            neib_a2irpu_rd_lat <= |irpu2neib_a_req;
            neib_b2irpu_rd_lat <= |irpu2neib_b_req;
            if (|irpu2neib_a_req) begin
                neib_a2irpu_rd <= {2'b00, mem_a1, 2'b00, mem_a1};
            end else begin
                neib_a2irpu_rd <= 68'd0;
            end
            if (|irpu2neib_b_req) begin
                case (b_response_index % 3)
                    0: neib_b2irpu_rd <= {2'b00, mem_b2, 2'b00, mem_b2};
                    1: neib_b2irpu_rd <= {2'b00, mem_b1, 2'b00, mem_b1};
                    default: neib_b2irpu_rd <= {2'b00, mem_b0, 2'b00, mem_b0};
                endcase
                b_response_index <= b_response_index + 1;
            end else begin
                neib_b2irpu_rd <= 68'd0;
            end
        end
    end

    always @(posedge clk_vc or negedge vc_rst_z) begin
        if (!vc_rst_z) begin
            cycle_count <= 0;
            accepted_count <= 0;
            candidate_count <= 0;
            recon_count <= 0;
            transfer_count <= 0;
            commit_count <= 0;
            done_count <= 0;
            update_count <= 0;
            lane_done0 <= 0;
            lane_done1 <= 0;
            lane_done2 <= 0;
            a_request_count <= 0;
            b_request_count <= 0;
            col_request_count <= 0;
            ref_request_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
            if (ccu2irpu_valid && irpu2ccu_rdy)
                accepted_count <= accepted_count + 1;
            if (cand_capture_done)
                candidate_count <= candidate_count + 1;
            if (recon_done)
                recon_count <= recon_count + 1;
            if (irpu2neib_a_req[0] && neib_a2irpu_gnt)
                a_request_count <= a_request_count + 1;
            if (irpu2neib_b_req[0] && neib_b2irpu_gnt)
                b_request_count <= b_request_count + 1;
            if (irpu2col_req)
                col_request_count <= col_request_count + 1;
            if (irpu2ref_req)
                ref_request_count <= ref_request_count + 1;
            if (mc_commit) begin
                transfer_count <= transfer_count + 1;
                commit_count <= commit_count + 1;
            end
            if (rolling_update)
                update_count <= update_count + 1;
            if (dec_mrg2mc_cand_done[0]) begin
                done_count <= done_count + 1;
                lane_done0 <= lane_done0 + 1;
            end
            if (dec_mrg2mc_cand_done[1]) begin
                done_count <= done_count + 1;
                lane_done1 <= lane_done1 + 1;
            end
            if (dec_mrg2mc_cand_done[2]) begin
                done_count <= done_count + 1;
                lane_done2 <= lane_done2 + 1;
            end

            check((^dec_mrg2mc_cand_rdy) !== 1'bx &&
                  (^dec_mrg2mc_cand_data) !== 1'bx &&
                  (^dec_mrg2mc_cand_done) !== 1'bx,
                  "MC ready/data/done vectors must remain known");
            check((cand_capture_done === 1'b0) || (cand_capture_done === 1'b1),
                  "Candidate capture pulse must remain known");
            check((recon_done === 1'b0) || (recon_done === 1'b1),
                  "reconstruction done pulse must remain known");
            check((^irpu2neib_a_req) !== 1'bx &&
                  (^irpu2neib_b_req) !== 1'bx,
                  "Neighbor request vectors must remain known");
            check(irpu2col_req === 1'b0 && irpu2ref_req === 1'b0,
                  "Col and RefList must remain disabled");
            check(mc_commit === (|(dec_mrg2mc_cand_rdy & mc2mrg_cand_ack)),
                  "commit must equal selected-lane valid/ack handshake");
        end
    end

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
        input [31:0] expected_mvp_f;
        input [31:0] expected_final_f;
        input integer stall_cycles;
        input flush_f;
        integer wait_i;
        integer stall_i;
        reg [16:0] command_f;
        reg [MRG2MC_DW-1:0] packet_f;
        reg [2:0] lane_mask_f;
        begin
            check(irpu2ccu_rdy === 1'b1 && dec_busy === 1'b0,
                  "previous transaction must retire before accepting another");
            check(dec_expected_sub_idx === sub_f,
                  "P8 transactions must arrive in serial sub-block order");
            check(ccu2irpu_valid === 1'b0 && dec_send === 1'b0,
                  "no outstanding CCU valid or MC send at transaction start");

            @(negedge clk_vc);
            b_response_index = 0;
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
                  "accepted CCU beat must launch the real Neighbor hierarchy");
            @(negedge clk_vc);
            ccu2irpu_valid = 1'b0;

            begin : wait_candidate_start
                for (wait_i = 0; wait_i < 100; wait_i = wait_i + 1) begin
                    @(negedge clk_vc);
                    if (dec_cand_start === 1'b1)
                        disable wait_candidate_start;
                end
            end
            check(dec_cand_start === 1'b1 && cand_busy === 1'b0,
                  "real Neighbor completion must launch the real Candidate");
            command_f = expected_command(skip_f, part_f, sub_f,
                                         x_f, y_f, a_f, b_f);
            check(dec_selected_cu_cmd === command_f,
                  "real Neighbor adapter command must match accepted context");
            check(dec_ctux === ctu_x_f && dec_ctuy === ctu_y_f &&
                  dec_cux === x_f && dec_cuy === y_f,
                  "accepted coordinates must be held through Candidate");
            check(dec_is_pic_top16 === ({ctu_y_f, y_f[2:1]} == 0) &&
                  dec_is_pic_left16 === ({ctu_x_f, x_f} == 0),
                  "skip-boundary flags must use accepted picture coordinates");
            if (a_f[1])
                check((^amvp_neib_a[1]) !== 1'bx,
                      "available A1 must be known");
            if (b_f[0])
                check((^amvp_neib_b[0]) !== 1'bx,
                      "available B0 must be known");
            if (b_f[1])
                check((^amvp_neib_b[1]) !== 1'bx,
                      "available B1 must be known");
            if (b_f[2])
                check((^amvp_neib_b[2]) !== 1'bx,
                      "available B2 must be known");
            if (part_f && (sub_f == 2'd1) && a_f[1])
                check(amvp_neib_a[1] === {2'b00, expected_mvp_f},
                      "P8 S1 A1 must be the real committed S0 rolling-neighbor value");
            if (skip_f && a_f[1])
                check(dut.U_BACKEND.U_RECON.dec_skip_a1_avail === 1'b1 &&
                      dut.U_BACKEND.U_RECON.dec_skip_a1_mv === amvp_neib_a[1][31:0],
                      "P_SKIP reconstruction must consume the real A1 availability/value");
            if (skip_f && b_f[1])
                check(dut.U_BACKEND.U_RECON.dec_skip_b1_avail === 1'b1 &&
                      dut.U_BACKEND.U_RECON.dec_skip_b1_mv === amvp_neib_b[1][31:0],
                      "P_SKIP reconstruction must consume the real B1 availability/value");

            @(posedge clk_vc);
            #1;
            check(cand_capture_done === 1'b1 &&
                  dec_spatial_mvp === expected_mvp_f,
                  "real Candidate capture must produce the directed spatial MVP");
            check(dec_cand_start === 1'b0 && cand_busy === 1'b1,
                  "Candidate must be in its one-cycle DONE phase after capture");

            @(posedge clk_vc);
            #1;
            check(cand_capture_done === 1'b0 && dec_recon_start === 1'b1,
                  "Candidate capture must launch reconstruction exactly once");
            @(posedge clk_vc);
            #1;
            check(recon_done === 1'b1 && dec_send === 1'b0,
                  "real reconstruction must complete before MC send");
            check(dec_final_mv === expected_final_f &&
                  dec_final_ref_idx === 4'd0,
                  "reconstruction must produce expected final MV/ref index");
            @(posedge clk_vc);
            #1;
            check(recon_done === 1'b0 && dec_send === 1'b1 &&
                  dec_busy === 1'b1 && irpu2ccu_rdy === 1'b0,
                  "controller must hold transaction until MC commit");
            check(dec_final_mv === expected_final_f && dec_ref_idx === 4'd0,
                  "final motion result and legal ref_idx must remain held");

            lane_mask_f = part_f ? 3'b001 : 3'b010;
            packet_f = expected_packet(part_f, sub_f, x_f, y_f,
                                       ctu_x_f, ctu_y_f, expected_final_f);
            check(dec_mrg2mc_cand_rdy === lane_mask_f,
                  "P8 uses lane0; P16/P_SKIP use lane1");
            if (part_f) begin
                check(dec_mrg2mc_cand_data[0] === packet_f &&
                      dec_mrg2mc_cand_data[1] === {MRG2MC_DW{1'b0}} &&
                      dec_mrg2mc_cand_data[2] === {MRG2MC_DW{1'b0}},
                      "real P8 MC packet must occupy lane0 only");
            end else begin
                check(dec_mrg2mc_cand_data[1] === packet_f &&
                      dec_mrg2mc_cand_data[0] === {MRG2MC_DW{1'b0}} &&
                      dec_mrg2mc_cand_data[2] === {MRG2MC_DW{1'b0}},
                      "real P16/P_SKIP MC packet must occupy lane1 only");
            end
            check(dec_mrg2mc_cand_done === 3'b000 && dec_mrg2mc_cand_nb === 3'b000,
                  "done is low before transfer and MRG-neighbor index remains zero");

            for (stall_i = 0; stall_i < stall_cycles; stall_i = stall_i + 1) begin
                @(negedge clk_vc);
                ccu2irpu_valid = 1'b1;
                ccu2irpu_mvd = 32'hdeadbeef;
                ccu2irpu_ref_idx = 4'hf;
                check(irpu2ccu_rdy === 1'b0 && dec_send === 1'b1 &&
                      dec_mrg2mc_cand_rdy === lane_mask_f,
                      "no next transaction may be accepted during MC backpressure");
                if (part_f)
                    check(dec_mrg2mc_cand_data[0] === packet_f,
                          "lane0 packet must hold during backpressure");
                else
                    check(dec_mrg2mc_cand_data[1] === packet_f,
                          "lane1 packet must hold during backpressure");
                check(mc_commit === 1'b0 && rolling_update === 1'b0 &&
                      dec_mrg2mc_cand_done === 3'b000,
                      "backpressure must not commit, update, or pulse done");
                @(posedge clk_vc);
                #1;
                check(dec_send === 1'b1 && irpu2ccu_rdy === 1'b0 &&
                      dec_mrg2mc_cand_rdy === lane_mask_f,
                      "send ownership must remain held on every stalled edge");
                ccu2irpu_valid = 1'b0;
            end

            if (flush_f) begin
                @(negedge clk_vc);
                reg_slice_go = 1'b1;
                #1;
                check(dec_mrg2mc_cand_rdy === 3'b000 &&
                      dec_mrg2mc_cand_data === '0 && mc_commit === 1'b0,
                      "slice flush must immediately suppress the pending MC packet");
                @(posedge clk_vc);
                #1;
                check(dec_send === 1'b0 && cand_capture_done === 1'b0 &&
                      recon_done === 1'b0 && dec_mrg2mc_cand_done === 3'b000 &&
                      rolling_update === 1'b0,
                      "flush must cancel work without stale stage completion");
                mc2mrg_cand_ack = lane_mask_f;
                repeat (2) begin
                    @(posedge clk_vc);
                    #1;
                    check(dec_send === 1'b0 && mc_commit === 1'b0 &&
                          dec_mrg2mc_cand_done === 3'b000 &&
                          rolling_update === 1'b0 && cand_capture_done === 1'b0 &&
                          recon_done === 1'b0,
                          "stale ack after flush cannot complete cancelled work");
                end
                @(negedge clk_vc);
                mc2mrg_cand_ack = 3'b000;
                reg_slice_go = 1'b0;
                @(posedge clk_vc);
                #1;
                check(irpu2ccu_rdy === 1'b1 && !dec_busy,
                      "controller must re-enter idle after slice flush");
                $display("T07-C FLUSH TRACE: cycle=%0d candidate_mvp=%h final_mv=%h packet_cancelled=1 stale_ack_ignored=1",
                         cycle_count, expected_mvp_f, expected_final_f);
            end else begin
                before_transfer = transfer_count;
                before_commit = commit_count;
                before_done = done_count;
                before_update = update_count;
                @(negedge clk_vc);
                mc2mrg_cand_ack = lane_mask_f;
                check(mc_commit === 1'b1 && rolling_update === 1'b1,
                      "selected MC handshake must be the single rolling-update event");
                @(posedge clk_vc);
                #1;
                check(dec_send === 1'b0 && !dec_busy && irpu2ccu_rdy === 1'b1 &&
                      mc_commit === 1'b0,
                      "MC acknowledgement must retire the controller transaction");
                check(dec_mrg2mc_cand_done === lane_mask_f,
                      "MC done must pulse once on the selected lane");
                check(dec_final_mv === expected_final_f,
                      "final MV must remain held after retirement");
                @(posedge clk_vc);
                #1;
                check(dec_mrg2mc_cand_done === 3'b000,
                      "MC done must be exactly one cycle");
                check(transfer_count == before_transfer + 1 &&
                      commit_count == before_commit + 1 &&
                      done_count == before_done + 1 &&
                      update_count == before_update + 1,
                      "one accepted packet must cause one transfer/commit/done/update");
                mc2mrg_cand_ack = 3'b000;
                $display("T07-C TRACE: cycle=%0d skip=%0d part=%0d sub=%0d mvp=%h mvd={%h,%h} final=%h lane=%0d packet=%h ack=1 commit=1 done=1 update=1",
                         cycle_count, skip_f, part_f, sub_f, expected_mvp_f,
                         mvd_y_f, mvd_x_f, expected_final_f,
                         part_f ? 0 : 1, packet_f);
            end
        end
    endtask

    initial begin
        clk_vc = 1'b0;
        vc_rst_z = 1'b1;
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
        col2irpu_gnt = 1'b0;
        col2irpu_rd_lat = 1'b0;
        col2irpu_rd = 84'd0;
        ref2irpu_gnt = 1'b0;
        ref2irpu_rd_lat = 1'b0;
        ref2irpu_rd = 33'd0;
        mc2mrg_cand_ack = 3'b000;
        mem_a1 = 32'd0;
        mem_b0 = 32'd0;
        mem_b1 = 32'd0;
        mem_b2 = 32'd0;

        // Explicit asynchronous reset falling edge.
        #1 vc_rst_z = 1'b0;
        #2;
        check(!dec_busy && !cand_busy && dec_final_mv === 32'd0 &&
              dec_spatial_mvp === 32'd0 && !recon_done,
              "asynchronous reset must clear the complete integrated pipeline");
        repeat (2) @(posedge clk_vc);
        @(negedge clk_vc);
        vc_rst_z = 1'b1;

        $display("CASE A: P16 only A1 through real Neighbor and Candidate");
        mem_a1 = 32'hffff8001;
        run_transaction(1'b0, 1'b0, 2'd0, 3'd2, 3'd2, 7'd1, 7'd1,
                        2'b10, 3'b000, 16'h0005, 16'h0014,
                        32'hffff8001, 32'h00138006, 1, 1'b0);

        $display("CASE B: P16 only B1 kernel behavior");
        mem_b1 = 32'h81234567;
        run_transaction(1'b0, 1'b0, 2'd0, 3'd2, 3'd2, 7'd1, 7'd1,
                        2'b00, 3'b010, 16'h0001, 16'h0002,
                        32'h81234567, 32'h81254568, 0, 1'b0);

        $display("CASE C: P16 only C=B0, then C=B2 fallback");
        mem_b0 = 32'h89abcdef;
        run_transaction(1'b0, 1'b0, 2'd0, 3'd2, 3'd2, 7'd1, 7'd1,
                        2'b00, 3'b001, 16'd0, 16'd0,
                        32'h89abcdef, 32'h89abcdef, 0, 1'b0);
        mem_b2 = 32'hfedcba98;
        run_transaction(1'b0, 1'b0, 2'd0, 3'd2, 3'd2, 7'd1, 7'd1,
                        2'b00, 3'b100, 16'd0, 16'd0,
                        32'hfedcba98, 32'hfedcba98, 0, 1'b0);

        $display("CASE D: P16 signed ABC MED, B0 priority over available B2, signed MVD");
        mem_a1 = {16'd300, 16'd50};
        mem_b0 = {16'h8000, 16'h8000};
        mem_b1 = {16'hff9c, 16'd200};
        mem_b2 = {16'd100, 16'hffec};
        run_transaction(1'b0, 1'b0, 2'd0, 3'd2, 3'd2, 7'd1, 7'd1,
                        2'b10, 3'b111, 16'h0005, 16'h0014,
                        32'hff9c0032, 32'hffb00037, 2, 1'b0);

        $display("CASE E: serial P8 S0 -> S1 -> S2 -> S3; S1 consumes committed S0 via A1");
        mem_a1 = 32'd0;
        mem_b0 = 32'd0;
        mem_b1 = 32'd0;
        mem_b2 = 32'd0;
        run_transaction(1'b0, 1'b1, 2'd0, 3'd2, 3'd2, 7'd0, 7'd0,
                        2'b11, 3'b111, 16'h0001, 16'h1111,
                        32'd0, 32'h11110001, 0, 1'b0);
        mem_a1 = 32'd0;
        run_transaction(1'b0, 1'b1, 2'd1, 3'd2, 3'd2, 7'd0, 7'd0,
                        2'b10, 3'b000, 16'd0, 16'd0,
                        32'h11110001, 32'h11110001, 0, 1'b0);
        run_transaction(1'b0, 1'b1, 2'd2, 3'd2, 3'd2, 7'd0, 7'd0,
                        2'b00, 3'b000, 16'd0, 16'd0,
                        32'd0, 32'd0, 0, 1'b0);
        run_transaction(1'b0, 1'b1, 2'd3, 3'd2, 3'd2, 7'd0, 7'd0,
                        2'b00, 3'b000, 16'd0, 16'd0,
                        32'd0, 32'd0, 0, 1'b0);

        $display("CASE F: P_SKIP top/left, zero A1/B1, and nonzero spatial predictor");
        mem_a1 = 32'h12345678;
        run_transaction(1'b1, 1'b0, 2'd0, 3'd2, 3'd0, 7'd1, 7'd0,
                        2'b10, 3'b000, 16'h1234, 16'h5678,
                        32'h12345678, 32'd0, 0, 1'b0);
        check(dec_is_pic_top16 === 1'b1,
              "P_SKIP picture-top case must assert the top boundary");
        mem_a1 = 32'h87654321;
        run_transaction(1'b1, 1'b0, 2'd0, 3'd0, 3'd2, 7'd0, 7'd1,
                        2'b10, 3'b000, 16'h1234, 16'h5678,
                        32'h87654321, 32'd0, 0, 1'b0);
        check(dec_is_pic_left16 === 1'b1,
              "P_SKIP picture-left case must assert the left boundary");
        mem_a1 = 32'd0;
        run_transaction(1'b1, 1'b0, 2'd0, 3'd2, 3'd2, 7'd1, 7'd1,
                        2'b10, 3'b000, 16'h2222, 16'h3333,
                        32'd0, 32'd0, 0, 1'b0);
        mem_b1 = 32'd0;
        run_transaction(1'b1, 1'b0, 2'd0, 3'd2, 3'd2, 7'd1, 7'd1,
                        2'b00, 3'b010, 16'h2222, 16'h3333,
                        32'd0, 32'd0, 0, 1'b0);
        mem_a1 = 32'h00010002;
        run_transaction(1'b1, 1'b0, 2'd0, 3'd2, 3'd2, 7'd1, 7'd1,
                        2'b10, 3'b000, 16'h1111, 16'h2222,
                        32'h00010002, 32'h00010002, 0, 1'b0);

        $display("CASE G: slice flush while MC is stalled; stale acknowledgement is ignored");
        mem_a1 = 32'h01020304;
        run_transaction(1'b0, 1'b0, 2'd0, 3'd2, 3'd2, 7'd1, 7'd1,
                        2'b10, 3'b000, 16'd0, 16'd0,
                        32'h01020304, 32'h01020304, 2, 1'b1);

        check(accepted_count == 15 && candidate_count == 15 && recon_count == 15,
              "all fifteen accepted transactions must traverse Candidate and reconstruction");
        check(transfer_count == 14 && commit_count == 14 && done_count == 14 &&
              update_count == 14,
              "only fourteen non-flushed transactions may transfer/commit/done/update");
        check(lane_done0 == 4 && lane_done1 == 10 && lane_done2 == 0,
              "P8 must use lane0 and P16/P_SKIP lane1");
        check(a_request_count > 0 && b_request_count > 0,
              "directed real-neighbor cases must exercise both SRAM interfaces");
        check(col_request_count == 0 && ref_request_count == 0,
              "Col and RefList requests must remain zero");
        check(irpu2ccu_rdy === 1'b1 && dec_busy === 1'b0,
              "integration must finish idle");
        $display("T07-C COUNTS: accepted=%0d candidate=%0d recon_done=%0d transfer=%0d commit=%0d done=%0d update=%0d lane_done={%0d,%0d,%0d}",
                 accepted_count, candidate_count, recon_count,
                 transfer_count, commit_count, done_count, update_count,
                 lane_done0, lane_done1, lane_done2);
        $display("T07-C REQUESTS: A=%0d B=%0d Col=%0d RefList=%0d",
                 a_request_count, b_request_count,
                 col_request_count, ref_request_count);
        $display("T07-C DECODER MVP PIPELINE INTEGRATION RESULT: PASS");
        $finish;
    end
endmodule
