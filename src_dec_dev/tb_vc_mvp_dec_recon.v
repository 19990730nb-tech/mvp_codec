`timescale 1ns/1ps

module tb_vc_mvp_dec_recon;
    reg clk_vc;
    reg vc_rst_z;
    reg codec_mode;
    reg reg_slice_go;
    reg dec_recon_start;
    reg dec_is_skip;
    reg dec_is_pic_top16;
    reg dec_is_pic_left16;
    reg dec_skip_a1_avail;
    reg dec_skip_b1_avail;
    reg [31:0] dec_skip_a1_mv;
    reg [31:0] dec_skip_b1_mv;
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
        .dec_is_skip        (dec_is_skip),
        .dec_is_pic_top16   (dec_is_pic_top16),
        .dec_is_pic_left16  (dec_is_pic_left16),
        .dec_skip_a1_avail  (dec_skip_a1_avail),
        .dec_skip_b1_avail  (dec_skip_b1_avail),
        .dec_skip_a1_mv     (dec_skip_a1_mv),
        .dec_skip_b1_mv     (dec_skip_b1_mv),
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
            dec_is_skip = 1'b0;
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

    task run_skip_case;
        input [31:0] spatial_mvp;
        input [15:0] mvd_x;
        input [15:0] mvd_y;
        input        pic_top16;
        input        pic_left16;
        input        a1_avail;
        input        b1_avail;
        input [31:0] a1_mv;
        input [31:0] b1_mv;
        input [31:0] expected_mv;
        input [8*160-1:0] name;
        reg [31:0] held_mv;
        begin
            @(negedge clk_vc);
            dec_is_skip = 1'b1;
            dec_spatial_mvp = spatial_mvp;
            dec_mvd[0] = mvd_x;
            dec_mvd[1] = mvd_y;
            dec_ref_idx = 4'hd;
            dec_is_pic_top16 = pic_top16;
            dec_is_pic_left16 = pic_left16;
            dec_skip_a1_avail = a1_avail;
            dec_skip_b1_avail = b1_avail;
            dec_skip_a1_mv = a1_mv;
            dec_skip_b1_mv = b1_mv;
            dec_recon_start = 1'b1;

            @(posedge clk_vc);
            #1;
            check(recon_done === 1'b1, {name, " done must assert after acceptance"});
            check(dec_final_mv === expected_mv, {name, " final MV"});
            check(dec_final_ref_idx === 4'd0, {name, " skip ref_idx forced to zero"});
            held_mv = dec_final_mv;
            dec_recon_start = 1'b0;

            @(posedge clk_vc);
            #1;
            check(recon_done === 1'b0, {name, " done must be one cycle"});
            check(dec_final_mv === held_mv && dec_final_ref_idx === 4'd0,
                  {name, " result holds after done"});

            @(posedge clk_vc);
            #1;
            check(recon_done === 1'b0, {name, " done remains low"});
            check(dec_final_mv === held_mv && dec_final_ref_idx === 4'd0,
                  {name, " result remains stable for multiple cycles"});
        end
    endtask

    initial begin
        clk_vc = 1'b0;
        vc_rst_z = 1'b1;
        codec_mode = 1'b1;
        reg_slice_go = 1'b0;
        dec_recon_start = 1'b0;
        dec_is_skip = 1'b0;
        dec_is_pic_top16 = 1'b0;
        dec_is_pic_left16 = 1'b0;
        dec_skip_a1_avail = 1'b0;
        dec_skip_b1_avail = 1'b0;
        dec_skip_a1_mv = 32'd0;
        dec_skip_b1_mv = 32'd0;
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

        run_skip_case(32'h12345678, 16'h0001, 16'h0002, 1'b1, 1'b0,
                      1'b1, 1'b1, 32'h11111111, 32'h22222222, 32'd0,
                      "skip at picture top");
        run_skip_case(32'h23456789, 16'h0001, 16'h0002, 1'b0, 1'b1,
                      1'b1, 1'b1, 32'h11111111, 32'h22222222, 32'd0,
                      "skip at picture left");
        run_skip_case(32'h3456789a, 16'h0001, 16'h0002, 1'b0, 1'b0,
                      1'b1, 1'b1, 32'd0, 32'h22222222, 32'd0,
                      "available A1 zero MV");
        run_skip_case(32'h456789ab, 16'h0001, 16'h0002, 1'b0, 1'b0,
                      1'b1, 1'b1, 32'h11111111, 32'd0, 32'd0,
                      "available B1 zero MV");
        run_skip_case(32'h56789abc, 16'h0001, 16'h0002, 1'b0, 1'b0,
                      1'b1, 1'b1, 32'h11111111, 32'h22222222,
                      32'h56789abc, "available nonzero A1 B1 pass predictor");
        run_skip_case(32'h6789abcd, 16'h0001, 16'h0002, 1'b0, 1'b0,
                      1'b0, 1'b0, 32'd0, 32'd0, 32'h6789abcd,
                      "both unavailable pass predictor");
        run_skip_case(32'h789abcde, 16'h0001, 16'h0002, 1'b0, 1'b0,
                      1'b0, 1'b1, 32'd0, 32'h22222222, 32'h789abcde,
                      "unavailable zero A1 does not force zero");
        run_skip_case(32'h89abcdef, 16'h0001, 16'h0002, 1'b0, 1'b0,
                      1'b1, 1'b0, 32'h11111111, 32'd0, 32'h89abcdef,
                      "unavailable zero B1 does not force zero");
        run_skip_case(32'h9abcdef0, 16'h0001, 16'h0002, 1'b0, 1'b0,
                      1'b0, 1'b1, 32'd0, 32'h22222222, 32'h9abcdef0,
                      "unavailable zero A1 and available nonzero B1");
        run_skip_case(32'habcdef01, 16'h7fff, 16'h8000, 1'b0, 1'b0,
                      1'b1, 1'b1, 32'h11111111, 32'h22222222,
                      32'habcdef01, "skip ignores overflow-inducing MVD");

        // A start coincident with slice flush must be discarded.
        @(negedge clk_vc);
        reg_slice_go = 1'b1;
        dec_is_skip = 1'b1;
        dec_is_pic_top16 = 1'b0;
        dec_is_pic_left16 = 1'b0;
        dec_skip_a1_avail = 1'b1;
        dec_skip_b1_avail = 1'b1;
        dec_skip_a1_mv = 32'h11111111;
        dec_skip_b1_mv = 32'h22222222;
        dec_recon_start = 1'b1;
        @(posedge clk_vc);
        #1;
        check(dec_final_mv === 32'd0 && dec_final_ref_idx === 4'd0 &&
              recon_done === 1'b0, "reg_slice_go flush wins over start");
        @(negedge clk_vc);
        reg_slice_go = 1'b0;
        dec_recon_start = 1'b0;
        run_skip_case(32'h13572468, 16'h7fff, 16'h8000, 1'b0, 1'b0,
                      1'b1, 1'b1, 32'h11111111, 32'h22222222,
                      32'h13572468, "clean skip re-entry after slice flush");

        // Codec-mode deassertion also flushes, including a coincident start.
        @(negedge clk_vc);
        codec_mode = 1'b0;
        dec_is_skip = 1'b1;
        dec_is_pic_top16 = 1'b0;
        dec_is_pic_left16 = 1'b0;
        dec_skip_a1_avail = 1'b1;
        dec_skip_b1_avail = 1'b1;
        dec_skip_a1_mv = 32'h11111111;
        dec_skip_b1_mv = 32'h22222222;
        dec_recon_start = 1'b1;
        @(posedge clk_vc);
        #1;
        check(dec_final_mv === 32'd0 && dec_final_ref_idx === 4'd0 &&
              recon_done === 1'b0, "codec_mode flush wins over start");
        @(negedge clk_vc);
        codec_mode = 1'b1;
        dec_recon_start = 1'b0;
        run_case(16'h0007, 16'h0009, 16'h0001, 16'h0002, 4'h0,
                 32'h000b0008, "clean non-skip re-entry after codec flush");

        if (errors == 0) begin
            $display("T04 P_SKIP RECON RESULT: PASS");
            $finish;
        end
        else begin
            $display("T03-B RECON RESULT: FAIL (%0d errors)", errors);
            $fatal(1);
        end
    end
endmodule
