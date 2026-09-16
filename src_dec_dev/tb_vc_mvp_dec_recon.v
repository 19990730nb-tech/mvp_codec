`timescale 1ns/1ps

module tb_vc_mvp_dec_recon;
    reg clk_vc;
    reg vc_rst_z;
    reg codec_mode;
    reg reg_slice_go;
    reg dec_recon_start;
    reg [31:0] dec_spatial_mvp;
    reg [1:0][15:0] dec_mvd;
    reg [3:0] dec_ref_idx;

    wire [31:0] dec_final_mv;
    wire [3:0] dec_final_ref_idx;
    wire recon_done;

    integer errors;

    vc_mvp_dec_recon dut (
        .clk_vc             (clk_vc),
        .vc_rst_z           (vc_rst_z),
        .codec_mode         (codec_mode),
        .reg_slice_go       (reg_slice_go),
        .dec_recon_start    (dec_recon_start),
        .dec_spatial_mvp    (dec_spatial_mvp),
        .dec_mvd            (dec_mvd),
        .dec_ref_idx        (dec_ref_idx),
        .dec_final_mv       (dec_final_mv),
        .dec_final_ref_idx  (dec_final_ref_idx),
        .recon_done         (recon_done)
    );

    always #5 clk_vc = ~clk_vc;

    task check;
        input condition;
        input [8*160-1:0] message;
        begin
            if (condition !== 1'b1) begin
                $display("FAIL: %0s (time=%0t)", message, $time);
                errors = errors + 1;
            end
        end
    endtask

    task run_case;
        input [15:0] mvp_x;
        input [15:0] mvp_y;
        input [15:0] mvd_x;
        input [15:0] mvd_y;
        input [3:0]  ref_idx;
        input [31:0] expected_mv;
        input [8*160-1:0] name;
        reg [31:0] held_mv;
        reg [3:0] held_ref_idx;
        begin
            @(negedge clk_vc);
            dec_spatial_mvp = {mvp_y, mvp_x};
            dec_mvd[0] = mvd_x;
            dec_mvd[1] = mvd_y;
            dec_ref_idx = ref_idx;
            dec_recon_start = 1'b1;

            @(posedge clk_vc);
            #1;
            check(recon_done === 1'b1, {name, " done must assert after acceptance"});
            check(dec_final_mv === expected_mv, {name, " final MV"});
            check(dec_final_ref_idx === ref_idx, {name, " ref_idx pass-through"});
            held_mv = dec_final_mv;
            held_ref_idx = dec_final_ref_idx;
            dec_recon_start = 1'b0;

            @(posedge clk_vc);
            #1;
            check(recon_done === 1'b0, {name, " done must be one cycle"});
            check(dec_final_mv === held_mv && dec_final_ref_idx === held_ref_idx,
                  {name, " result holds after done"});

            @(posedge clk_vc);
            #1;
            check(recon_done === 1'b0, {name, " done remains low"});
            check(dec_final_mv === held_mv && dec_final_ref_idx === held_ref_idx,
                  {name, " result remains stable for multiple cycles"});
        end
    endtask

    initial begin
        clk_vc = 1'b0;
        vc_rst_z = 1'b1;
        codec_mode = 1'b1;
        reg_slice_go = 1'b0;
        dec_recon_start = 1'b0;
        dec_spatial_mvp = 32'd0;
        dec_mvd = 32'd0;
        dec_ref_idx = 4'd0;
        errors = 0;

        // Explicit asynchronous reset falling edge.
        #1;
        vc_rst_z = 1'b0;
        #1;
        check(dec_final_mv === 32'd0 && dec_final_ref_idx === 4'd0 &&
              recon_done === 1'b0, "asynchronous reset clears outputs");
        @(negedge clk_vc);
        vc_rst_z = 1'b1;

        run_case(16'h0000, 16'h0000, 16'h0000, 16'h0000, 4'h0,
                 32'h00000000, "zero plus zero");
        run_case(16'h0012, 16'h0004, 16'h0023, 16'h0009, 4'h0,
                 32'h000d0035, "positive plus positive");
        run_case(16'hfff6, 16'hffe8, 16'hfffb, 16'hfffc, 4'h0,
                 32'hffe4fff1, "negative plus negative");
        run_case(16'h000a, 16'hfff6, 16'hfff8, 16'h0003, 4'h0,
                 32'hfff90002, "mixed-sign component sums");
        run_case(16'hfff0, 16'h0010, 16'h0005, 16'hfffc, 4'h0,
                 32'h000cfff5, "independent X and Y values");
        run_case(16'h0001, 16'h0002, 16'h0003, 16'h0004, 4'ha,
                 32'h00060004, "distinct ref_idx pass-through");

        $display("CASE: positive invalid boundary; expect X overflow diagnostic");
        run_case(16'h7fff, 16'h0000, 16'h0001, 16'h0001, 4'h0,
                 32'h00018000, "positive overflow low-bit fallback");

        $display("CASE: negative invalid boundary; expect X overflow diagnostic");
        run_case(16'h8000, 16'h1000, 16'hffff, 16'hffff, 4'h0,
                 32'h0fff7fff, "negative overflow low-bit fallback");

        // A start coincident with slice flush must be discarded.
        @(negedge clk_vc);
        reg_slice_go = 1'b1;
        dec_recon_start = 1'b1;
        @(posedge clk_vc);
        #1;
        check(dec_final_mv === 32'd0 && dec_final_ref_idx === 4'd0 &&
              recon_done === 1'b0, "reg_slice_go flush wins over start");
        @(negedge clk_vc);
        reg_slice_go = 1'b0;
        dec_recon_start = 1'b0;
        run_case(16'h0003, 16'h0005, 16'h0004, 16'h0006, 4'h0,
                 32'h000b0007, "clean re-entry after slice flush");

        // Codec-mode deassertion also flushes, including a coincident start.
        @(negedge clk_vc);
        codec_mode = 1'b0;
        dec_recon_start = 1'b1;
        @(posedge clk_vc);
        #1;
        check(dec_final_mv === 32'd0 && dec_final_ref_idx === 4'd0 &&
              recon_done === 1'b0, "codec_mode flush wins over start");
        @(negedge clk_vc);
        codec_mode = 1'b1;
        dec_recon_start = 1'b0;
        run_case(16'h0007, 16'h0009, 16'h0001, 16'h0002, 4'h0,
                 32'h000b0008, "clean re-entry after codec flush");

        if (errors == 0) begin
            $display("T03-B RECON RESULT: PASS");
            $finish;
        end
        else begin
            $display("T03-B RECON RESULT: FAIL (%0d errors)", errors);
            $fatal(1);
        end
    end
endmodule
