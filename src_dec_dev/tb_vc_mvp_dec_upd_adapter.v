`timescale 1ns/1ps

module tb_vc_mvp_dec_upd_adapter;
    reg clk_vc;
    reg vc_rst_z;
    reg codec_mode;
    reg reg_slice_go;
    reg mc_commit;
    reg dec_part_mode;
    reg dec_is_skip;
    reg [1:0] dec_sub_idx;
    reg [2:0] dec_cux;
    reg [2:0] dec_cuy;
    reg [31:0] dec_final_mv;
    reg [3:0] dec_final_ref_idx;

    wire cur_cu_upd;
    wire [1:0] cur_cu_upd_sz;
    wire [2:0] cur_cu_upd_x;
    wire [2:0] cur_cu_upd_y;
    wire [15:0] cur_cu_upd_mvx;
    wire [15:0] cur_cu_upd_mvy;
    wire [1:0] cur_cu_upd_refidx;

    integer errors;
    integer checks;

    vc_mvp_dec_upd_adapter dut (
        .clk_vc             (clk_vc),
        .vc_rst_z           (vc_rst_z),
        .codec_mode         (codec_mode),
        .reg_slice_go       (reg_slice_go),
        .mc_commit          (mc_commit),
        .dec_part_mode      (dec_part_mode),
        .dec_is_skip        (dec_is_skip),
        .dec_sub_idx        (dec_sub_idx),
        .dec_cux            (dec_cux),
        .dec_cuy            (dec_cuy),
        .dec_final_mv       (dec_final_mv),
        .dec_final_ref_idx  (dec_final_ref_idx),
        .cur_cu_upd          (cur_cu_upd),
        .cur_cu_upd_sz       (cur_cu_upd_sz),
        .cur_cu_upd_x        (cur_cu_upd_x),
        .cur_cu_upd_y        (cur_cu_upd_y),
        .cur_cu_upd_mvx      (cur_cu_upd_mvx),
        .cur_cu_upd_mvy      (cur_cu_upd_mvy),
        .cur_cu_upd_refidx   (cur_cu_upd_refidx)
    );

    always #5 clk_vc = ~clk_vc;

    task check;
        input condition;
        input [8*120-1:0] label;
        begin
            checks = checks + 1;
            if (condition !== 1'b1) begin
                $display("FAIL: %0s (time=%0t)", label, $time);
                errors = errors + 1;
            end
        end
    endtask

    task check_zero;
        input [8*120-1:0] label;
        begin
            check(cur_cu_upd === 1'b0, label);
            check(cur_cu_upd_sz === 2'd0, label);
            check(cur_cu_upd_x === 3'd0, label);
            check(cur_cu_upd_y === 3'd0, label);
            check(cur_cu_upd_mvx === 16'd0, label);
            check(cur_cu_upd_mvy === 16'd0, label);
            check(cur_cu_upd_refidx === 2'd0, label);
        end
    endtask

    task check_update;
        input [1:0] expected_sz;
        input [2:0] expected_x;
        input [2:0] expected_y;
        input [15:0] expected_mvx;
        input [15:0] expected_mvy;
        input [1:0] expected_refidx;
        input [8*120-1:0] label;
        begin
            check(cur_cu_upd === 1'b1, label);
            check(cur_cu_upd_sz === expected_sz, label);
            check(cur_cu_upd_x === expected_x, label);
            check(cur_cu_upd_y === expected_y, label);
            check(cur_cu_upd_mvx === expected_mvx, label);
            check(cur_cu_upd_mvy === expected_mvy, label);
            check(cur_cu_upd_refidx === expected_refidx, label);
        end
    endtask

    task run_legal;
        input part_mode;
        input is_skip;
        input [1:0] sub_idx;
        input [2:0] cux;
        input [2:0] cuy;
        input [31:0] final_mv;
        input [3:0] final_refidx;
        input [1:0] expected_sz;
        input [2:0] expected_x;
        input [2:0] expected_y;
        input [8*120-1:0] label;
        begin
            @(negedge clk_vc);
            dec_part_mode = part_mode;
            dec_is_skip = is_skip;
            dec_sub_idx = sub_idx;
            dec_cux = cux;
            dec_cuy = cuy;
            dec_final_mv = final_mv;
            dec_final_ref_idx = final_refidx;
            mc_commit = 1'b1;
            #1;
            // This check is deliberately before the next rising edge. A
            // registered or delayed update must fail here.
            check_update(expected_sz, expected_x, expected_y,
                         final_mv[15:0], final_mv[31:16], final_refidx[1:0], label);
            @(posedge clk_vc);
            #1;
            check_update(expected_sz, expected_x, expected_y,
                         final_mv[15:0], final_mv[31:16], final_refidx[1:0], label);
            @(negedge clk_vc);
            mc_commit = 1'b0;
            #1;
            check_zero({label, " immediate commit deassertion"});
        end
    endtask

`ifndef SYNTHESIS
    task run_invalid_diagnostic;
        input part_mode;
        input is_skip;
        input [1:0] sub_idx;
        input [2:0] cux;
        input [2:0] cuy;
        input [31:0] final_mv;
        input [3:0] final_refidx;
        input [1:0] expected_sz;
        input [2:0] expected_x;
        input [2:0] expected_y;
        input [8*120-1:0] label;
        begin
            $display("EXPECT SIMULATION DIAGNOSTIC: %0s", label);
            @(negedge clk_vc);
            dec_part_mode = part_mode;
            dec_is_skip = is_skip;
            dec_sub_idx = sub_idx;
            dec_cux = cux;
            dec_cuy = cuy;
            dec_final_mv = final_mv;
            dec_final_ref_idx = final_refidx;
            mc_commit = 1'b1;
            #1;
            check_update(expected_sz, expected_x, expected_y,
                         final_mv[15:0], final_mv[31:16], final_refidx[1:0], label);
            @(posedge clk_vc);
            #1;
            check_update(expected_sz, expected_x, expected_y,
                         final_mv[15:0], final_mv[31:16], final_refidx[1:0], label);
            @(negedge clk_vc);
            mc_commit = 1'b0;
            #1;
            check_zero({label, " diagnostic transaction retired"});
        end
    endtask
`endif

    initial begin
        clk_vc = 1'b0;
        vc_rst_z = 1'b1;
        codec_mode = 1'b1;
        reg_slice_go = 1'b0;
        mc_commit = 1'b0;
        dec_part_mode = 1'b0;
        dec_is_skip = 1'b0;
        dec_sub_idx = 2'b00;
        dec_cux = 3'd0;
        dec_cuy = 3'd0;
        dec_final_mv = 32'd0;
        dec_final_ref_idx = 4'd0;
        errors = 0;
        checks = 0;

        // Explicit asynchronous reset assertion while a commit is presented.
        mc_commit = 1'b1;
        #2 vc_rst_z = 1'b0;
        #1;
        check_zero("asynchronous reset suppresses update and payload");
        #2 vc_rst_z = 1'b1;
        #1;
        check_update(2'd2, 3'd0, 3'd0, 16'd0, 16'd0, 2'd0,
                     "combinational clean operation after reset release");

        // No commit means no write even when metadata is otherwise valid.
        mc_commit = 1'b0;
        #1;
        check_zero("mc_commit low");

        // Suppression is combinational, and normal operation resumes cleanly.
        codec_mode = 1'b0;
        mc_commit = 1'b1;
        #1;
        check_zero("non-AVC mode suppresses update");
        codec_mode = 1'b1;
        #1;
        check_update(2'd2, 3'd0, 3'd0, 16'd0, 16'd0, 2'd0,
                     "mode re-entry has no added latency");
        reg_slice_go = 1'b1;
        #1;
        check_zero("reg_slice_go suppresses update");
        reg_slice_go = 1'b0;
        #1;
        check_update(2'd2, 3'd0, 3'd0, 16'd0, 16'd0, 2'd0,
                     "slice-flush re-entry has no added latency");
        mc_commit = 1'b0;
        #1;
        check_zero("commit deassertion clears all payload immediately");

        // P8 S0/S1/S2/S3 coordinate mapping and distinct signed-looking MVs.
        run_legal(1'b1, 1'b0, 2'b00, 3'd2, 3'd4, 32'h1234_5678, 4'h1,
                  2'd1, 3'd2, 3'd4, "P8 S0");
        run_legal(1'b1, 1'b0, 2'b01, 3'd2, 3'd4, 32'hfffe_0003, 4'h0,
                  2'd1, 3'd3, 3'd4, "P8 S1 X+1 negative Y");
        run_legal(1'b1, 1'b0, 2'b10, 3'd2, 3'd4, 32'h8001_f234, 4'h2,
                  2'd1, 3'd2, 3'd5, "P8 S2 Y+1 negative MV components");
        run_legal(1'b1, 1'b0, 2'b11, 3'd2, 3'd4, 32'h7fff_8000, 4'h3,
                  2'd1, 3'd3, 3'd5, "P8 S3 X+1 Y+1");

        run_legal(1'b0, 1'b0, 2'b00, 3'd6, 3'd4, 32'hfedc_0123, 4'h1,
                  2'd2, 3'd6, 3'd4, "P16 aligned size 2");
        run_legal(1'b0, 1'b1, 2'b00, 3'd6, 3'd4, 32'h8000_ffff, 4'h0,
                  2'd2, 3'd6, 3'd4, "P_SKIP aligned size 2");

`ifndef SYNTHESIS
        run_invalid_diagnostic(1'b1, 1'b0, 2'b01, 3'd7, 3'd2,
            32'h8000_fffe, 4'h1, 2'd1, 3'd0, 3'd2, "P8 X overflow");
        run_invalid_diagnostic(1'b1, 1'b0, 2'b10, 3'd2, 3'd7,
            32'hffff_0001, 4'h2, 2'd1, 3'd2, 3'd0, "P8 Y overflow");
        run_invalid_diagnostic(1'b0, 1'b0, 2'b01, 3'd6, 3'd4,
            32'h1234_8000, 4'h0, 2'd2, 3'd6, 3'd4, "P16 nonzero sub-index");
        run_invalid_diagnostic(1'b0, 1'b1, 2'b10, 3'd6, 3'd4,
            32'h8000_ffff, 4'h1, 2'd2, 3'd6, 3'd4, "P_SKIP nonzero sub-index");
        run_invalid_diagnostic(1'b0, 1'b0, 2'b00, 3'd7, 3'd5,
            32'h0001_ffff, 4'h2, 2'd2, 3'd6, 3'd4, "P16 unaligned base");
        run_invalid_diagnostic(1'b1, 1'b1, 2'b00, 3'd2, 3'd4,
            32'h1234_5678, 4'h1, 2'd1, 3'd2, 3'd4, "P_SKIP with P8 mode");
        run_invalid_diagnostic(1'b0, 1'b0, 2'b00, 3'd6, 3'd4,
            32'hfedc_0123, 4'h5, 2'd2, 3'd6, 3'd4, "reference-index upper bits");
`endif

        if (errors == 0) begin
            $display("T06-A UPDATE ADAPTER RESULT: PASS");
        end else begin
            $display("T06-A UPDATE ADAPTER RESULT: FAIL (%0d errors, %0d checks)", errors, checks);
            $fatal(1, "tb_vc_mvp_dec_upd_adapter failed");
        end
        $finish;
    end
endmodule
