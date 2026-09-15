// T00 directed self-checking harness.
//
// Example compile/run command:
//   iverilog -g2012 -s tb_vc_mvp_dec_ctrl -o t00.vvp \
//       src_dec_dev/vc_mvp_dec_ctrl.v src_dec_dev/tb_vc_mvp_dec_ctrl.v
//   vvp t00.vvp
//
// Out-of-order P8 and illegal P_SKIP inputs intentionally emit the
// controller's simulation-only protocol errors.  They must not deadlock
// ready/valid admission.

`timescale 1ns/1ps

module tb_vc_mvp_dec_ctrl;

    reg                   clk_vc;
    reg                   vc_rst_z;
    reg                   codec_mode;
    reg                   reg_slice_go;
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
    reg                   mc_commit;
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
    integer i;
    reg [15:0] held_mvd0;
    reg [15:0] held_mvd1;
    reg [3:0]  held_ref;
    reg        held_skip;
    reg        held_part_mode;
    reg [1:0]  held_sub_idx;
    reg [2:0]  held_cux;
    reg [2:0]  held_cuy;

    vc_mvp_dec_ctrl dut (
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
            check(dec_busy && !irpu2ccu_rdy,
                  "accepted transaction must make controller busy");
            check(dec_mvd[0] == txn_mvx && dec_mvd[1] == txn_mvy,
                  "MVD must be latched on acceptance");
            check(dec_ref_idx == txn_ref && dec_is_skip == txn_skip,
                  "ref_idx and skip must be latched on acceptance");
            check(dec_part_mode == txn_part_mode && dec_sub_idx == txn_sub_idx,
                  "partition syntax must be latched on acceptance");
            check(dec_cux == txn_x && dec_cuy == txn_y,
                  "transaction coordinates must be latched on acceptance");
            @(negedge clk_vc);
            ccu2irpu_valid     = 1'b0;
            ccu2irpu_mvd       = 32'h0;
            ccu2irpu_ref_idx   = 4'h0;
            ccu2irpu_is_skip   = 1'b0;
            ccu2irpu_part_mode = 1'b0;
            ccu2irpu_sub_idx   = 2'd0;
            dec_txn_cux        = 3'd0;
            dec_txn_cuy        = 3'd0;
        end
    endtask

    task complete_transaction;
        input [1:0] expected_after;
        begin
            @(negedge clk_vc);
            neib_done_amvp = 1'b1;
            @(posedge clk_vc);
            #1;
            check(dec_cand_start && !dec_neib_start,
                  "neib_done must produce one cand_start pulse");

            @(negedge clk_vc);
            neib_done_amvp    = 1'b0;
            cand_capture_done = 1'b1;
            @(posedge clk_vc);
            #1;
            check(dec_recon_start && !dec_cand_start,
                  "candidate capture must produce one recon_start pulse");

            @(negedge clk_vc);
            cand_capture_done = 1'b0;
            recon_done        = 1'b1;
            @(posedge clk_vc);
            #1;
            check(dec_busy && !irpu2ccu_rdy && !dec_recon_start,
                  "recon_done must enter DEC_SEND while remaining busy");

            @(negedge clk_vc);
            recon_done = 1'b0;
            mc_commit  = 1'b1;
            @(posedge clk_vc);
            #1;
            check(!dec_busy && irpu2ccu_rdy,
                  "mc_commit must retire the transaction and reopen ready");
            check(dec_expected_sub_idx == expected_after,
                  "expected P8 sub-index must update at mc_commit");

            @(negedge clk_vc);
            mc_commit = 1'b0;
        end
    endtask

    task complete_to_send;
        begin
            @(negedge clk_vc);
            neib_done_amvp = 1'b1;
            @(posedge clk_vc);
            #1;
            check(dec_cand_start, "neib_done must start candidate stage");
            @(negedge clk_vc);
            neib_done_amvp = 1'b0;
            cand_capture_done = 1'b1;
            @(posedge clk_vc);
            #1;
            check(dec_recon_start, "candidate completion must start reconstruction");
            @(negedge clk_vc);
            cand_capture_done = 1'b0;
            recon_done = 1'b1;
            @(posedge clk_vc);
            #1;
            check(dec_busy && !irpu2ccu_rdy && !dec_recon_start,
                  "reconstruction completion must enter DEC_SEND");
            @(negedge clk_vc);
            recon_done = 1'b0;
        end
    endtask

    task mc_backpressure_case;
        begin
            accept_txn(1'b0, 1'b0, 2'd0, 3'd2, 3'd3,
                       16'h0101, 16'h0202, 4'd1);
            complete_to_send;

            held_mvd0      = dec_mvd[0];
            held_mvd1      = dec_mvd[1];
            held_ref       = dec_ref_idx;
            held_skip      = dec_is_skip;
            held_part_mode = dec_part_mode;
            held_sub_idx   = dec_sub_idx;
            held_cux       = dec_cux;
            held_cuy       = dec_cuy;

            for (i = 0; i < 3; i = i + 1) begin
                @(negedge clk_vc);
                @(posedge clk_vc);
                #1;
                check(dec_busy && !irpu2ccu_rdy,
                      "MC backpressure must hold DEC_SEND busy");
                check(dec_mvd[0] == held_mvd0 && dec_mvd[1] == held_mvd1 &&
                      dec_ref_idx == held_ref && dec_is_skip == held_skip &&
                      dec_part_mode == held_part_mode && dec_sub_idx == held_sub_idx &&
                      dec_cux == held_cux && dec_cuy == held_cuy,
                      "held transaction context must stay stable in DEC_SEND");
            end

            @(negedge clk_vc);
            mc_commit = 1'b1;
            @(posedge clk_vc);
            #1;
            check(!dec_busy && irpu2ccu_rdy,
                  "DEC_SEND must release only on mc_commit");
            @(negedge clk_vc);
            mc_commit = 1'b0;
        end
    endtask

    task slice_flush_case;
        begin
            accept_txn(1'b0, 1'b0, 2'd0, 3'd6, 3'd2,
                       16'h1111, 16'h2222, 4'd2);
            @(negedge clk_vc);
            neib_done_amvp = 1'b1;
            @(posedge clk_vc);
            #1;
            neib_done_amvp = 1'b0;
            check(dec_busy, "flush setup must be busy before flush");

            @(negedge clk_vc);
            reg_slice_go = 1'b1;
            @(posedge clk_vc);
            #1;
            check(!dec_busy && irpu2ccu_rdy,
                  "reg_slice_go must synchronously return controller to idle");
            check(dec_expected_sub_idx == 2'd0,
                  "reg_slice_go must reset expected P8 sub-index");
            check(!dec_neib_start && !dec_cand_start && !dec_recon_start,
                  "reg_slice_go must clear stale stage pulses");
            @(negedge clk_vc);
            reg_slice_go = 1'b0;
        end
    endtask

    task codec_mode_flush_case;
        begin
            accept_txn(1'b0, 1'b0, 2'd0, 3'd1, 3'd6,
                       16'h3333, 16'h4444, 4'd3);
            @(negedge clk_vc);
            codec_mode = 1'b0;
            check(!irpu2ccu_rdy, "ready must be low while codec_mode is zero");
            @(posedge clk_vc);
            #1;
            check(!dec_busy && !irpu2ccu_rdy,
                  "codec_mode deassertion must synchronously clear busy state");
            check(dec_expected_sub_idx == 2'd0 &&
                  !dec_neib_start && !dec_cand_start && !dec_recon_start,
                  "codec_mode flush must clear order state and stale pulses");
            @(negedge clk_vc);
            ccu2irpu_valid = 1'b1;
            check(!irpu2ccu_rdy, "codec_mode zero must block new admission");
            ccu2irpu_valid = 1'b0;
            codec_mode = 1'b1;
            #1;
            check(!dec_busy && irpu2ccu_rdy,
                  "codec_mode return must expose a clean idle controller");
        end
    endtask

    initial begin
        errors = 0;
        codec_mode = 1'b1;
        reg_slice_go = 1'b0;
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
        mc_commit = 1'b0;

        repeat (2) @(posedge clk_vc);
        @(negedge clk_vc);
        vc_rst_z = 1'b1;
        #1;
        check(irpu2ccu_rdy, "reset must leave controller ready in decoder mode");

        $display("CASE A: P16 normal transaction and mc_commit retirement");
        accept_txn(1'b0, 1'b0, 2'd0, 3'd1, 3'd2,
                   16'h1234, 16'h5678, 4'd3);
        complete_transaction(2'd0);

        $display("CASE B: MC backpressure and held-context stability");
        mc_backpressure_case;

        $display("CASE C: P8 S0 -> S1 -> S2 -> S3 commit ordering");
        accept_txn(1'b0, 1'b1, 2'd0, 3'd0, 3'd0,
                   16'h1000, 16'h2000, 4'd0);
        complete_transaction(2'd1);
        accept_txn(1'b0, 1'b1, 2'd1, 3'd1, 3'd0,
                   16'h1001, 16'h2001, 4'd0);
        complete_transaction(2'd2);
        accept_txn(1'b0, 1'b1, 2'd2, 3'd0, 3'd1,
                   16'h1002, 16'h2002, 4'd0);
        complete_transaction(2'd3);
        accept_txn(1'b0, 1'b1, 2'd3, 3'd1, 3'd1,
                   16'h1003, 16'h2003, 4'd0);
        complete_transaction(2'd0);

        $display("CASE D: out-of-order P8 input (expected protocol error)");
        accept_txn(1'b0, 1'b1, 2'd2, 3'd4, 3'd4,
                   16'h3000, 16'h4000, 4'd1);
        complete_transaction(2'd3);
        check(irpu2ccu_rdy, "out-of-order P8 must not deadlock ready");

        $display("CASE E: P_SKIP legality (illegal form emits error, legal form retires)");
        accept_txn(1'b1, 1'b0, 2'd1, 3'd5, 3'd1,
                   16'h0000, 16'h0000, 4'd0);
        complete_transaction(2'd0);
        accept_txn(1'b0, 1'b0, 2'd0, 3'd5, 3'd1,
                   16'h0000, 16'h0000, 4'd0);
        complete_transaction(2'd0);
        accept_txn(1'b1, 1'b0, 2'd0, 3'd5, 3'd1,
                   16'h0000, 16'h0000, 4'd0);
        complete_transaction(2'd0);

        $display("CASE F: reg_slice_go flush while busy");
        slice_flush_case;

        $display("CASE G: codec_mode deassertion flush and re-entry");
        codec_mode_flush_case;

        if (errors == 0)
            $display("T00 RESULT: PASS (Cases A-G; D and illegal P_SKIP emitted expected protocol errors)");
        else begin
            $display("T00 RESULT: FAIL (%0d self-check failures)", errors);
            $fatal(1);
        end
        $finish;
    end

endmodule
