// T01-B1 directed checks for Decoder command, coordinate, lane, and pulse adaptation.

`timescale 1ns/1ps

module tb_vc_mvp_dec_neib_adapter;

    reg                   clk_vc;
    reg                   codec_mode;
    reg                   dec_neib_start;
    reg                   dec_part_mode;
    reg                   dec_is_skip;
    reg      [1:0]        dec_sub_idx;
    reg      [2:0]        dec_cux;
    reg      [2:0]        dec_cuy;
    reg      [1:0]        dec_a_avail;
    reg      [2:0]        dec_b_avail;

    wire                  amvp_cu_start;
    wire     [2:0][13:0]  amvp_cmd_out;
    wire     [1:0][2:0]   cmdq_empty_n;
    wire     [2:0]        amvp_blk_sz;
    wire     [2:0]        n_blk_sz_amvp;
    wire                  blk_sz_lat_amvp;

    integer errors;

    vc_mvp_dec_neib_adapter dut (
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

    function [13:0] expected_cmd;
        input [2:0] x;
        input [2:0] y;
        input [1:0] a;
        input [2:0] b;
        input        skip;
        begin
            expected_cmd = {1'b0, skip, 1'b0, a, b, y, x};
        end
    endfunction

    task check_common_size;
        input [2:0] expected_size;
        begin
            check(amvp_blk_sz == expected_size && n_blk_sz_amvp == expected_size,
                  "block-size outputs must match the selected one-hot mode");
            check(cmdq_empty_n[0] == 3'b000 && cmdq_empty_n[1] == expected_size,
                  "only cmdq_empty_n[1] may identify the active transaction size");
        end
    endtask

    task check_launch_pulses;
        begin
            check(amvp_cu_start && blk_sz_lat_amvp,
                  "Neighbor start must accompany the block-size capture pulse");
            @(negedge clk_vc);
            dec_neib_start = 1'b0;
            #1;
            check(!amvp_cu_start && !blk_sz_lat_amvp,
                  "Neighbor launch and capture signals must be one-cycle pulses");
        end
    endtask

    integer sub;
    reg [2:0] expected_x;
    reg [2:0] expected_y;
    integer error_count_before;

    initial begin
        errors = 0;
        codec_mode = 1'b1;
        dec_neib_start = 1'b0;
        dec_part_mode = 1'b0;
        dec_is_skip = 1'b0;
        dec_sub_idx = 2'd0;
        dec_cux = 3'd0;
        dec_cuy = 3'd0;
        dec_a_avail = 2'd0;
        dec_b_avail = 3'd0;

        #1;
        $display("CASE A: normal P16 lane and command adaptation");
        dec_part_mode = 1'b0;
        dec_is_skip = 1'b0;
        dec_sub_idx = 2'd0;
        dec_cux = 3'd2;
        dec_cuy = 3'd3;
        dec_a_avail = 2'b10;
        dec_b_avail = 3'b101;
        dec_neib_start = 1'b1;
        #1;
        check(amvp_cmd_out[0] == expected_cmd(3'd2, 3'd3, 2'b10, 3'b101, 1'b0),
              "P16 lane0 command must pack base coordinate and availability");
        check(amvp_cmd_out[1] == amvp_cmd_out[0],
              "P16 lane1 must duplicate lane0 command for AVC blk16 availability");
        check(amvp_cmd_out[2] == 14'd0, "P16 lane2 must be deterministic zero");
        check_common_size(3'b010);
        check(amvp_cmd_out[0][13:11] == 3'b000,
              "normal P16 command metadata must be 000");
        check_launch_pulses;

        $display("CASE B: P8 S0 through S3 coordinate mapping and lanes");
        dec_part_mode = 1'b1;
        dec_is_skip = 1'b0;
        dec_cux = 3'd1;
        dec_cuy = 3'd2;
        dec_a_avail = 2'b01;
        dec_b_avail = 3'b110;
        for (sub = 0; sub < 4; sub = sub + 1) begin
            dec_sub_idx = sub[1:0];
            dec_neib_start = 1'b1;
            #1;
            expected_x = 3'd1 + sub[0];
            expected_y = 3'd2 + sub[1];
            check(amvp_cmd_out[0] == expected_cmd(expected_x, expected_y,
                                                   2'b01, 3'b110, 1'b0),
                  "P8 command must use base coordinate plus sub_idx mapping");
            check(amvp_cmd_out[1] == 14'd0 && amvp_cmd_out[2] == 14'd0,
                  "P8 inactive command lanes must be deterministic zero");
            check_common_size(3'b001);
            check(amvp_cmd_out[0][13:11] == 3'b000,
                  "normal P8 command metadata must be 000");
            check(amvp_cu_start && blk_sz_lat_amvp,
                  "P8 launch must assert both one-cycle handoff pulses");
            @(negedge clk_vc);
            dec_neib_start = 1'b0;
            #1;
            check(!amvp_cu_start && !blk_sz_lat_amvp,
                  "P8 handoff pulses must deassert after launch");
        end

        $display("CASE C: P_SKIP metadata and blk16 lane adaptation");
        dec_part_mode = 1'b0;
        dec_is_skip = 1'b1;
        dec_sub_idx = 2'd0;
        dec_cux = 3'd5;
        dec_cuy = 3'd6;
        dec_a_avail = 2'b11;
        dec_b_avail = 3'b011;
        dec_neib_start = 1'b1;
        #1;
        check(amvp_cmd_out[0] == expected_cmd(3'd5, 3'd6, 2'b11, 3'b011, 1'b1),
              "P_SKIP command must retain skip metadata");
        check(amvp_cmd_out[1] == amvp_cmd_out[0] && amvp_cmd_out[2] == 14'd0,
              "P_SKIP must use duplicated blk16 lanes with lane2 inactive");
        check_common_size(3'b010);
        check(amvp_cmd_out[0][13:11] == 3'b010,
              "P_SKIP command metadata must be 010");
        check_launch_pulses;

        $display("CASE D: codec_mode suppresses launches and data");
        codec_mode = 1'b0;
        dec_neib_start = 1'b1;
        #1;
        check(!amvp_cu_start && !blk_sz_lat_amvp,
              "codec_mode zero must suppress launch and capture pulses");
        check(amvp_cmd_out == 42'd0 && cmdq_empty_n == 6'd0 &&
              amvp_blk_sz == 3'd0 && n_blk_sz_amvp == 3'd0,
              "codec_mode zero must clear adapter outputs");
        dec_neib_start = 1'b0;
        codec_mode = 1'b1;

        $display("CASE E: invalid P8 coordinate emits simulation protocol error");
        dec_part_mode = 1'b1;
        dec_is_skip = 1'b0;
        dec_sub_idx = 2'd1;
        dec_cux = 3'd7;
        dec_cuy = 3'd0;
        error_count_before = dut.p8_coord_error_count;
        dec_neib_start = 1'b1;
        @(posedge clk_vc);
        #1;
        check(dut.p8_coord_error_count == error_count_before + 1,
              "P8 coordinate overflow must trigger a simulation protocol error");
        @(negedge clk_vc);
        dec_neib_start = 1'b0;

        if (errors == 0)
            $display("T01-B1 ADAPTER RESULT: PASS");
        else begin
            $display("T01-B1 ADAPTER RESULT: FAIL (%0d self-check failures)", errors);
            $fatal(1);
        end
        $finish;
    end

endmodule
