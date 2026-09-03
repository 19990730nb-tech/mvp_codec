// T00 directed self-checking harness.
//
// Example compile/run command:
//   iverilog -g2012 -s tb_vc_mvp_dec_ctrl -o t00.vvp \
//       src_dec_dev/vc_mvp_dec_ctrl.v src_dec_dev/tb_vc_mvp_dec_ctrl.v
//   vvp t00.vvp
//
// Case D intentionally causes the controller's simulation-only protocol
// error for the out-of-order P8 sub-index; the test itself must continue and
// demonstrate that ready does not deadlock.

`timescale 1ns/1ps

module tb_vc_mvp_dec_ctrl;

    reg                   clk_vc;
    reg                   vc_rst_z;
    reg                   codec_mode;
    reg                   ccu2irpu_valid;
    wire                  irpu2ccu_rdy;
    reg      [1:0][15:0]  ccu2irpu_mvd;
    reg      [3:0]        ccu2irpu_ref_idx;
    reg                   ccu2irpu_is_skip;
    reg                   ccu2irpu_part_mode;
    reg      [1:0]        ccu2irpu_sub_idx;
    reg      [2:0]        dec_txn_cux;
    reg      [2:0]        dec_txn_cuy;
    reg                   neib_done_amvp;
    reg                   cand_capture_done;
    reg                   recon_done;
    reg                   result_accept;
    reg                   cur_cu_upd;
    reg      [1:0]        cur_cu_upd_sz;
    reg      [2:0]        cur_cu_upd_x;
    reg      [2:0]        cur_cu_upd_y;
    wire                  dec_neib_start;
    wire                  dec_cand_start;
    wire                  dec_recon_start;
    wire     [1:0][15:0]  dec_mvd;
    wire     [3:0]        dec_ref_idx;
    wire                  dec_is_skip;
    wire                  dec_part_mode;
    wire     [1:0]        dec_sub_idx;
    wire     [2:0]        dec_cux;
    wire     [2:0]        dec_cuy;
    wire     [1:0]        dec_expected_sub_idx;
    wire                  dec_busy;
    wire     [5:0]        dbg_dec_fsm_cs;

    integer errors;

    vc_mvp_dec_ctrl dut (
        .clk_vc               (clk_vc),
        .vc_rst_z             (vc_rst_z),
        .codec_mode           (codec_mode),
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
        .result_accept        (result_accept),
        .cur_cu_upd            (cur_cu_upd),
        .cur_cu_upd_sz         (cur_cu_upd_sz),
        .cur_cu_upd_x          (cur_cu_upd_x),
        .cur_cu_upd_y          (cur_cu_upd_y),
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

    initial begin
        clk_vc = 1'b0;
        forever #5 clk_vc = ~clk_vc;
    end

    task check;
        input condition;
        input [8*96-1:0] message;
        begin
            if (!condition) begin
                $display("FAIL: %0s (t=%0t)", message, $time);
                errors = errors + 1;
            end
        end
    endtask

    task accept_txn;
        input              txn_skip;
        input              txn_part_mode;
        input      [1:0]   txn_sub_idx;
        input      [2:0]   txn_x;
        input      [2:0]   txn_y;
        input      [15:0]  txn_mvx;
        input      [15:0]  txn_mvy;
        input      [3:0]   txn_ref;
        begin
            @(negedge clk_vc);
            ccu2irpu_valid     = 1'b1;
            ccu2irpu_is_skip   = txn_skip;
            ccu2irpu_part_mode = txn_part_mode;
            ccu2irpu_sub_idx   = txn_sub_idx;
            ccu2irpu_mvd[0]    = txn_mvx;
            ccu2irpu_mvd[1]    = txn_mvy;
            ccu2irpu_ref_idx   = txn_ref;
            dec_txn_cux        = txn_x;
            dec_txn_cuy        = txn_y;
            check(irpu2ccu_rdy, "ready must be high before acceptance");
            @(posedge clk_vc);
            #1;
            check(dec_neib_start, "accept must produce one-cycle delayed neib_start");
            check(dec_busy && !irpu2ccu_rdy, "accepted transaction must make controller busy");
            check(dec_mvd[0] == txn_mvx && dec_mvd[1] == txn_mvy,
                  "MVD must be latched on acceptance");
            check(dec_ref_idx == txn_ref && dec_is_skip == txn_skip,
                  "ref_idx and skip must be latched on acceptance");
            check(dec_part_mode == txn_part_mode && dec_sub_idx == txn_sub_idx,
                  "partition syntax must be latched on acceptance");
            check(dec_cux == txn_x && dec_cuy == txn_y,
                  "transaction coordinates must be latched on acceptance");
            @(negedge clk_vc);
            ccu2irpu_valid = 1'b0;
            ccu2irpu_mvd  = 32'h0;
            ccu2irpu_ref_idx = 4'h0;
            ccu2irpu_is_skip = 1'b0;
            ccu2irpu_part_mode = 1'b0;
            ccu2irpu_sub_idx = 2'd0;
            dec_txn_cux = 3'd0;
            dec_txn_cuy = 3'd0;
        end
    endtask

    task finish_transaction;
        input       [2:0] txn_x;
        input       [2:0] txn_y;
        input       [1:0] commit_sz;
        input             txn_part_mode;
        input       [1:0] txn_sub_idx;
        input             include_unrelated;
        reg         [1:0] expected_after;
        begin
            @(negedge clk_vc);
            neib_done_amvp = 1'b1;
            @(posedge clk_vc);
            #1;
            check(dec_cand_start && !dec_neib_start,
                  "neib_done must produce one cand_start pulse");

            @(negedge clk_vc);
            neib_done_amvp = 1'b0;
            cand_capture_done = 1'b1;
            @(posedge clk_vc);
            #1;
            check(dec_recon_start && !dec_cand_start,
                  "candidate capture must produce one recon_start pulse");

            @(negedge clk_vc);
            cand_capture_done = 1'b0;
            recon_done = 1'b1;
            @(posedge clk_vc);
            #1;
            check(!dec_recon_start && dec_busy && !irpu2ccu_rdy,
                  "recon_done must advance to SEND while remaining busy");

            @(negedge clk_vc);
            recon_done = 1'b0;
            result_accept = 1'b1;
            @(posedge clk_vc);
            #1;
            check(dec_busy && !irpu2ccu_rdy,
                  "result acceptance must enter DEC_WAIT_UPD");

            @(negedge clk_vc);
            result_accept = 1'b0;
            if (include_unrelated) begin
                cur_cu_upd    = 1'b1;
                cur_cu_upd_sz = commit_sz;
                cur_cu_upd_x  = txn_x ^ 3'b001;
                cur_cu_upd_y  = txn_y;
                @(posedge clk_vc);
                #1;
                check(dec_busy && !irpu2ccu_rdy,
                      "unrelated cur_cu_upd must not release DEC_WAIT_UPD");
                @(negedge clk_vc);
            end

            cur_cu_upd    = 1'b1;
            cur_cu_upd_sz = commit_sz;
            cur_cu_upd_x  = txn_x;
            cur_cu_upd_y  = txn_y;
            @(posedge clk_vc);
            #1;
            if (txn_part_mode)
                expected_after = (txn_sub_idx == 2'd3) ? 2'd0 : txn_sub_idx + 2'd1;
            else
                expected_after = 2'd0;
            check(!dec_busy && irpu2ccu_rdy,
                  "matching cur_cu_upd must release the transaction");
            check(dec_expected_sub_idx == expected_after,
                  "expected P8 sub-index must advance only on commit");

            @(negedge clk_vc);
            cur_cu_upd    = 1'b0;
            cur_cu_upd_sz = 2'd0;
            cur_cu_upd_x  = 3'd0;
            cur_cu_upd_y  = 3'd0;
        end
    endtask

    task backpressure_case;
        integer i;
        begin
            accept_txn(1'b0, 1'b0, 2'd0, 3'd2, 3'd3, 16'h0101, 16'h0202, 4'd1);

            // Hold DEC_NEIB.
            for (i = 0; i < 3; i = i + 1) begin
                @(negedge clk_vc);
                @(posedge clk_vc);
                #1;
                check(dec_busy && !irpu2ccu_rdy && !dec_cand_start,
                      "neib backpressure must hold DEC_NEIB");
            end

            @(negedge clk_vc);
            neib_done_amvp = 1'b1;
            @(posedge clk_vc);
            #1;
            check(dec_cand_start, "backpressure case must eventually start candidate stage");

            // Hold DEC_MVP.
            @(negedge clk_vc);
            neib_done_amvp = 1'b0;
            for (i = 0; i < 3; i = i + 1) begin
                @(posedge clk_vc);
                #1;
                check(dec_busy && !irpu2ccu_rdy && !dec_recon_start,
                      "candidate backpressure must hold DEC_MVP");
            end

            @(negedge clk_vc);
            cand_capture_done = 1'b1;
            @(posedge clk_vc);
            #1;
            check(dec_recon_start, "backpressure case must eventually start reconstruction");

            // Hold DEC_RECON.
            @(negedge clk_vc);
            cand_capture_done = 1'b0;
            for (i = 0; i < 3; i = i + 1) begin
                @(posedge clk_vc);
                #1;
                check(dec_busy && !irpu2ccu_rdy,
                      "reconstruction backpressure must hold DEC_RECON");
            end

            @(negedge clk_vc);
            recon_done = 1'b1;
            @(posedge clk_vc);
            #1;

            // Hold DEC_SEND.
            @(negedge clk_vc);
            recon_done = 1'b0;
            for (i = 0; i < 3; i = i + 1) begin
                @(posedge clk_vc);
                #1;
                check(dec_busy && !irpu2ccu_rdy,
                      "result backpressure must hold DEC_SEND");
            end

            @(negedge clk_vc);
            result_accept = 1'b1;
            @(posedge clk_vc);
            #1;

            // Hold DEC_WAIT_UPD.
            @(negedge clk_vc);
            result_accept = 1'b0;
            for (i = 0; i < 3; i = i + 1) begin
                @(posedge clk_vc);
                #1;
                check(dec_busy && !irpu2ccu_rdy,
                      "update backpressure must hold DEC_WAIT_UPD");
            end

            @(negedge clk_vc);
            cur_cu_upd = 1'b1;
            cur_cu_upd_sz = 2'd2;
            cur_cu_upd_x = 3'd2;
            cur_cu_upd_y = 3'd3;
            @(posedge clk_vc);
            #1;
            check(!dec_busy && irpu2ccu_rdy,
                  "backpressure case must release on matching update");
            @(negedge clk_vc);
            cur_cu_upd = 1'b0;
            cur_cu_upd_sz = 2'd0;
            cur_cu_upd_x = 3'd0;
            cur_cu_upd_y = 3'd0;
        end
    endtask

    initial begin
        errors = 0;
        codec_mode = 1'b1;
        vc_rst_z = 1'b0;
        ccu2irpu_valid = 1'b0;
        ccu2irpu_mvd = 32'd0;
        ccu2irpu_ref_idx = 4'd0;
        ccu2irpu_is_skip = 1'b0;
        ccu2irpu_part_mode = 1'b0;
        ccu2irpu_sub_idx = 2'd0;
        dec_txn_cux = 3'd0;
        dec_txn_cuy = 3'd0;
        neib_done_amvp = 1'b0;
        cand_capture_done = 1'b0;
        recon_done = 1'b0;
        result_accept = 1'b0;
        cur_cu_upd = 1'b0;
        cur_cu_upd_sz = 2'd0;
        cur_cu_upd_x = 3'd0;
        cur_cu_upd_y = 3'd0;

        repeat (2) @(posedge clk_vc);
        @(negedge clk_vc);
        vc_rst_z = 1'b1;
        #1;
        check(irpu2ccu_rdy, "reset must leave controller ready in decoder mode");

        $display("CASE A: P16 normal");
        accept_txn(1'b0, 1'b0, 2'd0, 3'd1, 3'd2, 16'h1234, 16'h5678, 4'd3);
        finish_transaction(3'd1, 3'd2, 2'd2, 1'b0, 2'd0, 1'b1);

        $display("CASE B: P8 S0 -> S3");
        accept_txn(1'b0, 1'b1, 2'd0, 3'd0, 3'd0, 16'h1000, 16'h2000, 4'd0);
        finish_transaction(3'd0, 3'd0, 2'd1, 1'b1, 2'd0, 1'b0);
        accept_txn(1'b0, 1'b1, 2'd1, 3'd1, 3'd0, 16'h1001, 16'h2001, 4'd0);
        finish_transaction(3'd1, 3'd0, 2'd1, 1'b1, 2'd1, 1'b0);
        accept_txn(1'b0, 1'b1, 2'd2, 3'd0, 3'd1, 16'h1002, 16'h2002, 4'd0);
        finish_transaction(3'd0, 3'd1, 2'd1, 1'b1, 2'd2, 1'b0);
        accept_txn(1'b0, 1'b1, 2'd3, 3'd1, 3'd1, 16'h1003, 16'h2003, 4'd0);
        finish_transaction(3'd1, 3'd1, 2'd1, 1'b1, 2'd3, 1'b0);
        check(dec_expected_sub_idx == 2'd0, "P8 S3 commit must wrap expected index to zero");

        $display("CASE C: backpressure at every stage");
        backpressure_case;

        $display("CASE D: invalid P8 order (expected controller protocol error)");
        accept_txn(1'b0, 1'b1, 2'd2, 3'd4, 3'd4, 16'h3000, 16'h4000, 4'd1);
        finish_transaction(3'd4, 3'd4, 2'd1, 1'b1, 2'd2, 1'b0);
        check(dec_expected_sub_idx == 2'd3,
              "invalid P8 transaction must not deadlock tracker progress");

        $display("CASE E: P_SKIP");
        accept_txn(1'b1, 1'b0, 2'd0, 3'd5, 3'd1, 16'h0000, 16'h0000, 4'd0);
        finish_transaction(3'd5, 3'd1, 2'd2, 1'b0, 2'd0, 1'b0);
        check(dec_expected_sub_idx == 2'd0, "P_SKIP completion must leave expected index at zero");

        if (errors == 0)
            $display("T00 RESULT: PASS (Cases A-E; Case D emitted the expected protocol error)");
        else begin
            $display("T00 RESULT: FAIL (%0d self-check failures)", errors);
            $fatal(1);
        end
        $finish;
    end

endmodule
