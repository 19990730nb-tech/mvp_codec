`timescale 1ns/1ps

module tb_vc_mvp_dec_mc_adapter;
    localparam VC_CTU_X_NB = 7;
    localparam VC_CTU_Y_NB = 7;
    localparam VC_PIC_X_NB = 12;
    localparam VC_PIC_Y_NB = 12;
    localparam MRG2MC_DW = VC_PIC_X_NB + VC_PIC_Y_NB + 39;

    reg clk_vc;
    reg vc_rst_z;
    reg codec_mode;
    reg reg_slice_go;
    reg dec_send;
    reg [31:0] dec_final_mv;
    reg [3:0] dec_final_ref_idx;
    reg dec_part_mode;
    reg dec_is_skip;
    reg [1:0] dec_sub_idx;
    reg [2:0] dec_cux;
    reg [2:0] dec_cuy;
    reg [VC_CTU_X_NB-1:0] dec_ctux;
    reg [VC_CTU_Y_NB-1:0] dec_ctuy;
    reg [2:0] mc2mrg_cand_ack;

    wire [2:0] dec_mrg2mc_cand_rdy;
    wire [2:0][MRG2MC_DW-1:0] dec_mrg2mc_cand_data;
    wire [2:0] dec_mrg2mc_cand_nb;
    wire [2:0] dec_mrg2mc_cand_done;
    wire mc_commit;

    integer errors;
    integer checks;

    vc_mvp_dec_mc_adapter #(
        .VC_CTU_X_NB (VC_CTU_X_NB),
        .VC_CTU_Y_NB (VC_CTU_Y_NB),
        .VC_PIC_X_NB (VC_PIC_X_NB),
        .VC_PIC_Y_NB (VC_PIC_Y_NB),
        .MRG2MC_DW   (MRG2MC_DW)
    ) dut (
        .clk_vc                 (clk_vc),
        .vc_rst_z               (vc_rst_z),
        .codec_mode             (codec_mode),
        .reg_slice_go           (reg_slice_go),
        .dec_send               (dec_send),
        .dec_final_mv           (dec_final_mv),
        .dec_final_ref_idx      (dec_final_ref_idx),
        .dec_part_mode          (dec_part_mode),
        .dec_is_skip            (dec_is_skip),
        .dec_sub_idx            (dec_sub_idx),
        .dec_cux                (dec_cux),
        .dec_cuy                (dec_cuy),
        .dec_ctux               (dec_ctux),
        .dec_ctuy               (dec_ctuy),
        .mc2mrg_cand_ack         (mc2mrg_cand_ack),
        .dec_mrg2mc_cand_rdy     (dec_mrg2mc_cand_rdy),
        .dec_mrg2mc_cand_data    (dec_mrg2mc_cand_data),
        .dec_mrg2mc_cand_nb      (dec_mrg2mc_cand_nb),
        .dec_mrg2mc_cand_done    (dec_mrg2mc_cand_done),
        .mc_commit               (mc_commit)
    );

    always #5 clk_vc = ~clk_vc;

    function [MRG2MC_DW-1:0] make_packet;
        input [VC_PIC_Y_NB-1:0] pic_y;
        input [VC_PIC_X_NB-1:0] pic_x;
        input [1:0] size_code;
        input [1:0] ref_idx;
        input [31:0] final_mv;
        begin
            make_packet = {1'b1, pic_y, pic_x, size_code, size_code,
                           ref_idx, final_mv};
        end
    endfunction

    task check;
        input condition;
        input [8*180-1:0] message;
        begin
            checks = checks + 1;
            if (condition !== 1'b1) begin
                $display("FAIL: %0s (time=%0t)", message, $time);
                errors = errors + 1;
            end
        end
    endtask

    task check_idle;
        input [2:0] expected_done;
        input [8*120-1:0] label;
        begin
            check(dec_mrg2mc_cand_rdy === 3'b000, {label, " rdy idle"});
            check(dec_mrg2mc_cand_data === {3{ {MRG2MC_DW{1'b0}} }},
                  {label, " data idle"});
            check(dec_mrg2mc_cand_nb === 3'b000, {label, " nb tied low"});
            check(dec_mrg2mc_cand_done === expected_done, {label, " done"});
            check(mc_commit === 1'b0, {label, " commit low"});
        end
    endtask

    task check_packet;
        input [2:0] expected_rdy;
        input [MRG2MC_DW-1:0] expected_packet;
        input [8*120-1:0] label;
        reg [2:0][MRG2MC_DW-1:0] expected_data;
        begin
            expected_data = '0;
            if (expected_rdy[0]) expected_data[0] = expected_packet;
            if (expected_rdy[1]) expected_data[1] = expected_packet;
            check(dec_mrg2mc_cand_rdy === expected_rdy, {label, " lane ready"});
            check(dec_mrg2mc_cand_data === expected_data, {label, " packed packet/lane"});
            check(dec_mrg2mc_cand_nb === 3'b000, {label, " nb is zero"});
            check(dec_mrg2mc_cand_data[2] === {MRG2MC_DW{1'b0}}, {label, " lane2 data zero"});
            if (expected_rdy[0]) begin
                check(dec_mrg2mc_cand_data[0][MRG2MC_DW-1] === 1'b1,
                      {label, " candidate selector top bit"});
                check(dec_mrg2mc_cand_data[0][31:0] === expected_packet[31:0],
                      {label, " final MV low field"});
                check(dec_mrg2mc_cand_data[0][33:32] === expected_packet[33:32],
                      {label, " ref_idx field"});
                check(dec_mrg2mc_cand_data[0][35:34] === expected_packet[35:34],
                      {label, " X size field"});
                check(dec_mrg2mc_cand_data[0][37:36] === expected_packet[37:36],
                      {label, " Y size field"});
            end
            if (expected_rdy[1]) begin
                check(dec_mrg2mc_cand_data[1][MRG2MC_DW-1] === 1'b1,
                      {label, " candidate selector top bit"});
                check(dec_mrg2mc_cand_data[1][31:0] === expected_packet[31:0],
                      {label, " final MV low field"});
                check(dec_mrg2mc_cand_data[1][33:32] === expected_packet[33:32],
                      {label, " ref_idx field"});
                check(dec_mrg2mc_cand_data[1][35:34] === expected_packet[35:34],
                      {label, " X size field"});
                check(dec_mrg2mc_cand_data[1][37:36] === expected_packet[37:36],
                      {label, " Y size field"});
            end
        end
    endtask

    task run_noack;
        input part_mode;
        input is_skip;
        input [1:0] sub_idx;
        input [2:0] cux;
        input [2:0] cuy;
        input [2:0] expected_rdy;
        input [MRG2MC_DW-1:0] expected_packet;
        input [8*120-1:0] label;
        begin
            @(negedge clk_vc);
            dec_part_mode = part_mode;
            dec_is_skip = is_skip;
            dec_sub_idx = sub_idx;
            dec_cux = cux;
            dec_cuy = cuy;
            dec_send = 1'b1;
            mc2mrg_cand_ack = 3'b000;
            #1;
            check_packet(expected_rdy, expected_packet, label);
            check(mc_commit === 1'b0, {label, " no ack means no commit"});
            check(dec_mrg2mc_cand_done === 3'b000, {label, " no ack means no done"});
            @(posedge clk_vc);
            #1;
            check(dec_mrg2mc_cand_done === 3'b000, {label, " no handshake pulse"});
            @(negedge clk_vc);
            dec_send = 1'b0;
            @(posedge clk_vc);
            #1;
            check_idle(3'b000, label);
        end
    endtask

    task run_backpressure_then_handshake;
        input [2:0] expected_rdy;
        input [MRG2MC_DW-1:0] expected_packet;
        input integer wait_cycles;
        input [8*120-1:0] label;
        reg [31:0] held_mv;
        reg [3:0] held_ref_idx;
        reg held_part_mode;
        reg held_is_skip;
        reg [1:0] held_sub_idx;
        reg [2:0] held_cux;
        reg [2:0] held_cuy;
        reg [VC_CTU_X_NB-1:0] held_ctux;
        reg [VC_CTU_Y_NB-1:0] held_ctuy;
        integer n;
        begin
            @(negedge clk_vc);
            dec_part_mode = 1'b1;
            dec_is_skip = 1'b0;
            dec_sub_idx = 2'b11;
            dec_cux = 3'd2;
            dec_cuy = 3'd4;
            dec_send = 1'b1;
            mc2mrg_cand_ack = 3'b000;
            held_mv = dec_final_mv;
            held_ref_idx = dec_final_ref_idx;
            held_part_mode = dec_part_mode;
            held_is_skip = dec_is_skip;
            held_sub_idx = dec_sub_idx;
            held_cux = dec_cux;
            held_cuy = dec_cuy;
            held_ctux = dec_ctux;
            held_ctuy = dec_ctuy;
            #1;
            check_packet(expected_rdy, expected_packet, label);
            for (n = 0; n < wait_cycles; n = n + 1) begin
                @(posedge clk_vc);
                #1;
                check_packet(expected_rdy, expected_packet, {label, " held stable"});
                check((dec_final_mv === held_mv) &&
                      (dec_final_ref_idx === held_ref_idx) &&
                      (dec_part_mode === held_part_mode) &&
                      (dec_is_skip === held_is_skip) &&
                      (dec_sub_idx === held_sub_idx) &&
                      (dec_cux === held_cux) && (dec_cuy === held_cuy) &&
                      (dec_ctux === held_ctux) && (dec_ctuy === held_ctuy) &&
                      (dec_send === 1'b1),
                      {label, " controller/context inputs held stable"});
                check(mc_commit === 1'b0, {label, " backpressure"});
                check(dec_mrg2mc_cand_done === 3'b000, {label, " no early done"});
            end
            @(negedge clk_vc);
            mc2mrg_cand_ack = expected_rdy;
            #1;
            check(mc_commit === 1'b1, {label, " selected lane handshake"});
            check(dec_mrg2mc_cand_done === 3'b000, {label, " done not combinational"});
            @(posedge clk_vc);
            #1;
            check(dec_mrg2mc_cand_done === expected_rdy, {label, " registered done next cycle"});
            dec_send = 1'b0;
            mc2mrg_cand_ack = 3'b000;
            #1;
            check(dec_mrg2mc_cand_done === expected_rdy, {label, " done held for one cycle"});
            check(mc_commit === 1'b0, {label, " retirement drops commit"});
            @(posedge clk_vc);
            #1;
            check(dec_mrg2mc_cand_done === 3'b000, {label, " done exactly one cycle"});
            check_idle(3'b000, label);
        end
    endtask

    task run_immediate_handshake;
        input [2:0] expected_rdy;
        input [MRG2MC_DW-1:0] expected_packet;
        input [8*120-1:0] label;
        begin
            @(negedge clk_vc);
            dec_part_mode = 1'b0;
            dec_is_skip = 1'b0;
            dec_sub_idx = 2'b00;
            dec_cux = 3'd6;
            dec_cuy = 3'd4;
            dec_send = 1'b1;
            mc2mrg_cand_ack = expected_rdy;
            #1;
            check_packet(expected_rdy, expected_packet, label);
            check(mc_commit === 1'b1, {label, " immediate ack commits"});
            check(dec_mrg2mc_cand_done === 3'b000, {label, " done delayed"});
            @(posedge clk_vc);
            #1;
            check(dec_mrg2mc_cand_done === expected_rdy, {label, " done next cycle"});
            dec_send = 1'b0;
            mc2mrg_cand_ack = 3'b000;
            #1;
            check(mc_commit === 1'b0, {label, " retirement drops commit"});
            @(posedge clk_vc);
            #1;
            check(dec_mrg2mc_cand_done === 3'b000, {label, " one-cycle done"});
            check_idle(3'b000, label);
        end
    endtask

    task run_invalid_diagnostic;
        input part_mode;
        input is_skip;
        input [1:0] sub_idx;
        input [2:0] cux;
        input [2:0] cuy;
        input [3:0] ref_idx;
        input [2:0] expected_rdy;
        input [MRG2MC_DW-1:0] expected_packet;
        input [8*120-1:0] diagnostic_name;
        begin
            $display("EXPECT SIMULATION DIAGNOSTIC: %0s", diagnostic_name);
            @(negedge clk_vc);
            dec_part_mode = part_mode;
            dec_is_skip = is_skip;
            dec_sub_idx = sub_idx;
            dec_cux = cux;
            dec_cuy = cuy;
            dec_final_ref_idx = ref_idx;
            dec_send = 1'b1;
            mc2mrg_cand_ack = 3'b000;
            #1;
            check_packet(expected_rdy, expected_packet, diagnostic_name);
            @(posedge clk_vc);
            #1;
            check(dec_mrg2mc_cand_done === 3'b000, {diagnostic_name, " diagnostic does not handshake"});
            @(negedge clk_vc);
            dec_send = 1'b0;
            dec_final_ref_idx = 4'h1;
            @(posedge clk_vc);
            #1;
            check_idle(3'b000, diagnostic_name);
        end
    endtask

    task flush_backpressured_transaction;
        input flush_mode;
        input [8*120-1:0] label;
        begin
            @(negedge clk_vc);
            dec_part_mode = 1'b1;
            dec_is_skip = 1'b0;
            dec_sub_idx = 2'b00;
            dec_cux = 3'd2;
            dec_cuy = 3'd4;
            dec_send = 1'b1;
            mc2mrg_cand_ack = 3'b000;
            #1;
            check(dec_mrg2mc_cand_rdy === 3'b001, {label, " setup valid"});
            @(posedge clk_vc);
            #1;
            @(negedge clk_vc);
            if (flush_mode)
                codec_mode = 1'b0;
            else
                reg_slice_go = 1'b1;
            #1;
            check(dec_mrg2mc_cand_rdy === 3'b000, {label, " ready suppressed immediately"});
            check(dec_mrg2mc_cand_data === {3{ {MRG2MC_DW{1'b0}} }}, {label, " data suppressed immediately"});
            check(mc_commit === 1'b0, {label, " no flush commit"});
            check(dec_mrg2mc_cand_done === 3'b000, {label, " no stale done"});
            @(posedge clk_vc);
            #1;
            check(dec_mrg2mc_cand_done === 3'b000, {label, " pending state cleared"});
            @(negedge clk_vc);
            dec_send = 1'b0;
            if (flush_mode)
                codec_mode = 1'b1;
            else
                reg_slice_go = 1'b0;
            @(posedge clk_vc);
            #1;
            check_idle(3'b000, label);
        end
    endtask

    initial begin
        clk_vc = 1'b0;
        vc_rst_z = 1'b1;
        codec_mode = 1'b0;
        reg_slice_go = 1'b0;
        dec_send = 1'b0;
        dec_final_mv = 32'h1234_abcd;
        dec_final_ref_idx = 4'h1;
        dec_part_mode = 1'b0;
        dec_is_skip = 1'b0;
        dec_sub_idx = 2'b00;
        dec_cux = 3'b000;
        dec_cuy = 3'b000;
        dec_ctux = 7'd5;
        dec_ctuy = 7'd3;
        mc2mrg_cand_ack = 3'b000;
        errors = 0;
        checks = 0;

        #2 vc_rst_z = 1'b0;
        #1;
        check_idle(3'b000, "asynchronous reset asserted");
        #2 vc_rst_z = 1'b1;
        @(negedge clk_vc);
        codec_mode = 1'b1;
        @(posedge clk_vc);
        #1;
        check_idle(3'b000, "reset release");

        run_noack(1'b1, 1'b0, 2'b00, 3'd2, 3'd4, 3'b001,
                  make_packet(12'h0e0, 12'h150, 2'd1, 2'd1, 32'h1234_abcd), "P8 S0");
        run_noack(1'b1, 1'b0, 2'b01, 3'd2, 3'd4, 3'b001,
                  make_packet(12'h0e0, 12'h158, 2'd1, 2'd1, 32'h1234_abcd), "P8 S1");
        run_noack(1'b1, 1'b0, 2'b10, 3'd2, 3'd4, 3'b001,
                  make_packet(12'h0e8, 12'h150, 2'd1, 2'd1, 32'h1234_abcd), "P8 S2");
        run_noack(1'b1, 1'b0, 2'b11, 3'd2, 3'd4, 3'b001,
                  make_packet(12'h0e8, 12'h158, 2'd1, 2'd1, 32'h1234_abcd), "P8 S3");
        run_noack(1'b0, 1'b0, 2'b00, 3'd6, 3'd4, 3'b010,
                  make_packet(12'h0e0, 12'h170, 2'd2, 2'd1, 32'h1234_abcd), "P16 lane1");
        run_noack(1'b0, 1'b1, 2'b00, 3'd6, 3'd4, 3'b010,
                  make_packet(12'h0e0, 12'h170, 2'd2, 2'd1, 32'h1234_abcd), "P_SKIP lane1");

        run_backpressure_then_handshake(3'b001,
            make_packet(12'h0e8, 12'h158, 2'd1, 2'd1, 32'h1234_abcd),
            3, "P8 backpressure then handshake");

        // Acknowledging the wrong lane cannot commit or raise done.
        @(negedge clk_vc);
        dec_part_mode = 1'b1;
        dec_is_skip = 1'b0;
        dec_sub_idx = 2'b00;
        dec_cux = 3'd2;
        dec_cuy = 3'd4;
        dec_send = 1'b1;
        mc2mrg_cand_ack = 3'b010;
        #1;
        check(dec_mrg2mc_cand_rdy === 3'b001, "wrong-lane ack P8 ready");
        check(mc_commit === 1'b0, "wrong-lane ack cannot commit");
        @(posedge clk_vc);
        #1;
        check(dec_mrg2mc_cand_done === 3'b000, "wrong-lane ack cannot raise done");
        @(negedge clk_vc);
        dec_send = 1'b0;
        mc2mrg_cand_ack = 3'b000;
        @(posedge clk_vc);
        #1;
        check_idle(3'b000, "wrong-lane ack cleanup");

        run_immediate_handshake(3'b010,
            make_packet(12'h0e0, 12'h170, 2'd2, 2'd1, 32'h1234_abcd),
            "P16 immediate handshake");

        flush_backpressured_transaction(1'b0, "reg_slice_go flush");
        run_noack(1'b1, 1'b0, 2'b01, 3'd2, 3'd4, 3'b001,
                  make_packet(12'h0e0, 12'h158, 2'd1, 2'd1, 32'h1234_abcd), "P8 re-entry after slice flush");
        flush_backpressured_transaction(1'b1, "codec_mode flush");
        run_noack(1'b0, 1'b0, 2'b00, 3'd6, 3'd4, 3'b010,
                  make_packet(12'h0e0, 12'h170, 2'd2, 2'd1, 32'h1234_abcd), "P16 re-entry after mode flush");

        // Verify asynchronous reset cancels a pending registered done pulse.
        @(negedge clk_vc);
        dec_part_mode = 1'b1;
        dec_is_skip = 1'b0;
        dec_sub_idx = 2'b00;
        dec_cux = 3'd2;
        dec_cuy = 3'd4;
        dec_send = 1'b1;
        mc2mrg_cand_ack = 3'b001;
        #1;
        check(mc_commit === 1'b1, "reset test handshake presented");
        @(posedge clk_vc);
        #1;
        check(dec_mrg2mc_cand_done === 3'b001, "reset test done pending");
        #1 vc_rst_z = 1'b0;
        #1;
        check_idle(3'b000, "asynchronous reset cancels done");
        dec_send = 1'b0;
        mc2mrg_cand_ack = 3'b000;
        @(negedge clk_vc);
        vc_rst_z = 1'b1;
        codec_mode = 1'b1;
        @(posedge clk_vc);
        #1;
        check_idle(3'b000, "post-reset clean idle");
        run_noack(1'b1, 1'b0, 2'b10, 3'd2, 3'd4, 3'b001,
                  make_packet(12'h0e8, 12'h150, 2'd1, 2'd1, 32'h1234_abcd), "clean re-entry after reset");

`ifndef SYNTHESIS
        run_invalid_diagnostic(1'b1, 1'b0, 2'b01, 3'd7, 3'd4, 4'h1, 3'b001,
            make_packet(12'h0e0, 12'h140, 2'd1, 2'd1, 32'h1234_abcd), "P8 X coordinate overflow");
        run_invalid_diagnostic(1'b1, 1'b0, 2'b10, 3'd2, 3'd7, 4'h1, 3'b001,
            make_packet(12'h0c0, 12'h150, 2'd1, 2'd1, 32'h1234_abcd), "P8 Y coordinate overflow");
        run_invalid_diagnostic(1'b0, 1'b0, 2'b01, 3'd6, 3'd4, 4'h1, 3'b010,
            make_packet(12'h0e0, 12'h170, 2'd2, 2'd1, 32'h1234_abcd), "P16 nonzero sub-index");
        run_invalid_diagnostic(1'b0, 1'b1, 2'b10, 3'd6, 3'd4, 4'h1, 3'b010,
            make_packet(12'h0e0, 12'h170, 2'd2, 2'd1, 32'h1234_abcd), "P_SKIP nonzero sub-index");
        run_invalid_diagnostic(1'b0, 1'b0, 2'b00, 3'd7, 3'd4, 4'h1, 3'b010,
            make_packet(12'h0e0, 12'h170, 2'd2, 2'd1, 32'h1234_abcd), "unaligned P16 base");
        run_invalid_diagnostic(1'b1, 1'b1, 2'b00, 3'd2, 3'd4, 4'h1, 3'b001,
            make_packet(12'h0e0, 12'h150, 2'd1, 2'd1, 32'h1234_abcd), "P_SKIP with P8 mode");
        run_invalid_diagnostic(1'b0, 1'b0, 2'b00, 3'd6, 3'd4, 4'h5, 3'b010,
            make_packet(12'h0e0, 12'h170, 2'd2, 2'd1, 32'h1234_abcd), "ref_idx upper bits nonzero");
`endif

        if (errors == 0) begin
            $display("T05-B MC ADAPTER RESULT: PASS");
            $display("T05-B checks completed: %0d", checks);
        end else begin
            $display("T05-B MC ADAPTER RESULT: FAIL (%0d errors, %0d checks)", errors, checks);
            $fatal(1, "tb_vc_mvp_dec_mc_adapter failed");
        end
        $finish;
    end
endmodule
