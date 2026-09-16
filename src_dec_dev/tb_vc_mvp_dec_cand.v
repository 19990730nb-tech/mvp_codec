`timescale 1ns/1ps

module tb_vc_mvp_dec_cand;

    reg clk_vc;
    reg vc_rst_z;
    reg reg_slice_go;
    reg dec_cand_start;
    reg [16:0] selected_cu_cmd;
    reg [2:0][33:0] amvp_neib_b;
    reg [1:0][33:0] amvp_neib_a;

    wire [31:0] dec_spatial_mvp;
    wire cand_capture_done;
    wire cand_busy;

    integer errors;
    integer case_count;
    reg [31:0] launch_mv;
    reg [31:0] held_mv;

    always #5 clk_vc = ~clk_vc;

    vc_mvp_dec_cand dut (
        .clk_vc           (clk_vc),
        .vc_rst_z         (vc_rst_z),
        .reg_slice_go     (reg_slice_go),
        .dec_cand_start   (dec_cand_start),
        .selected_cu_cmd  (selected_cu_cmd),
        .amvp_neib_b      (amvp_neib_b),
        .amvp_neib_a      (amvp_neib_a),
        .dec_spatial_mvp  (dec_spatial_mvp),
        .cand_capture_done(cand_capture_done),
        .cand_busy        (cand_busy)
    );

    task check;
        input condition;
        input [8*160-1:0] message;
        begin
            if (!condition) begin
                $display("FAIL: %0s (time=%0t)", message, $time);
                errors = errors + 1;
            end
        end
    endtask

    function [16:0] make_cmd;
        input [2:0] blk_encoding;
        input a0;
        input a1;
        input b0;
        input b1;
        input b2;
        input is_skip;
        begin
            make_cmd = 17'd0;
            make_cmd[16:14] = blk_encoding;
            make_cmd[12] = is_skip;
            make_cmd[10] = a1;
            make_cmd[9]  = a0;
            make_cmd[8]  = b2;
            make_cmd[7]  = b1;
            make_cmd[6]  = b0;
        end
    endfunction

    task load_neighbors;
        input [31:0] a0_mv;
        input [31:0] a1_mv;
        input [31:0] b0_mv;
        input [31:0] b1_mv;
        input [31:0] b2_mv;
        begin
            // Deliberately use nonzero incoming refs.  The wrapper must retain
            // each MV and sanitize all ref-index fields to List0/ref_idx 0.
            amvp_neib_a[0] = {2'b11, a0_mv};
            amvp_neib_a[1] = {2'b10, a1_mv};
            amvp_neib_b[0] = {2'b01, b0_mv};
            amvp_neib_b[1] = {2'b11, b1_mv};
            amvp_neib_b[2] = {2'b10, b2_mv};
        end
    endtask

    task run_case;
        input [8*72-1:0] label;
        input [16:0] command;
        input [31:0] expected_mv;
        begin
            @(negedge clk_vc);
            selected_cu_cmd = command;
            dec_cand_start = 1'b1;
            #1;
            case_count = case_count + 1;
            check(!cand_busy && dut.candidate_blk_idle,
                  "generator must be idle before launch");
            check(dut.candidate_start,
                  "wrapper must forward an accepted launch");
            check(dut.candidate_rdy[0],
                  "candidate0 must be valid in the launch cycle");
            check(!dut.candidate_rdy[1],
                  "candidate1 must remain disabled in AVC mode");
            check(!dut.candidate_blk_done,
                  "DONE must not be asserted in the launch cycle");
            check(dut.candidate_cu_cmd[9] == 1'b0,
                  "Candidate-only A0 availability mask must be zero");
            check(dut.candidate_cu_cmd[10] == command[10] &&
                  dut.candidate_cu_cmd[8:6] == command[8:6],
                  "A1/B0/B1/B2 availability must pass through unchanged");
            check(dut.candidate_neib_a[0][31:0] == amvp_neib_a[0][31:0] &&
                  dut.candidate_neib_a[1][31:0] == amvp_neib_a[1][31:0] &&
                  dut.candidate_neib_b[0][31:0] == amvp_neib_b[0][31:0] &&
                  dut.candidate_neib_b[1][31:0] == amvp_neib_b[1][31:0] &&
                  dut.candidate_neib_b[2][31:0] == amvp_neib_b[2][31:0],
                  "all Neighbor MV payloads must be preserved");
            check(dut.candidate_neib_a[0][33:32] == 2'b00 &&
                  dut.candidate_neib_a[1][33:32] == 2'b00 &&
                  dut.candidate_neib_b[0][33:32] == 2'b00 &&
                  dut.candidate_neib_b[1][33:32] == 2'b00 &&
                  dut.candidate_neib_b[2][33:32] == 2'b00,
                  "all Neighbor reference indexes must be sanitized to zero");
            launch_mv = dut.candidate_mv[0][31:0];
            check(launch_mv == expected_mv,
                  "combinational launch-cycle candidate must match expected MV");

            @(posedge clk_vc);
            #1;
            check(dec_spatial_mvp == expected_mv,
                  "registered MVP must capture candidate on launch edge");
            check(cand_capture_done,
                  "successful launch must produce capture-done pulse");
            check(cand_busy && dut.candidate_blk_done,
                  "generator must be in DONE after the capture edge");
            check(!dut.candidate_rdy[0] && !dut.candidate_rdy[1],
                  "candidate ready must be low in the DONE cycle");
            check(dec_spatial_mvp == launch_mv,
                  "captured result must equal pre-DONE launch-cycle data");

            @(negedge clk_vc);
            dec_cand_start = 1'b0;
            @(posedge clk_vc);
            #1;
            check(!cand_capture_done,
                  "cand_capture_done must be exactly one cycle");
            check(!cand_busy && dut.candidate_blk_idle,
                  "generator must return to IDLE after DONE");
            check(dec_spatial_mvp == expected_mv,
                  "registered MVP must remain stable after completion");
            $display("PASS CASE %0d: %0s => %h", case_count, label,
                     dec_spatial_mvp);
        end
    endtask

    initial begin
        clk_vc = 1'b0;
        vc_rst_z = 1'b0;
        reg_slice_go = 1'b0;
        dec_cand_start = 1'b0;
        selected_cu_cmd = 17'd0;
        amvp_neib_a = '0;
        amvp_neib_b = '0;
        errors = 0;
        case_count = 0;
        launch_mv = 32'd0;
        held_mv = 32'd0;

        #2;
        check(dec_spatial_mvp == 0 && !cand_capture_done && !cand_busy,
              "asynchronous reset must clear wrapper and generator state");
        @(negedge clk_vc);
        vc_rst_z = 1'b1;
        load_neighbors(32'h12345678, 32'h01020304,
                       32'h11112222, 32'h33334444, 32'h55556666);

        $display("CASE 1: no candidates => zero");
        run_case("none", make_cmd(3'b010, 0, 0, 0, 0, 0, 0), 32'd0);

        $display("CASE 2-3: only A1; raw A0 differs but is masked");
        load_neighbors(32'h7fff8000, 32'hffff8001,
                       32'h11112222, 32'h33334444, 32'h55556666);
        run_case("only A1 with raw A0 present", make_cmd(3'b010, 1, 1, 0, 0, 0, 0),
                 32'hffff8001);

        $display("CASE 4: only B1 => B1");
        load_neighbors(32'h0, 32'h0, 32'h0, 32'h81234567, 32'h0);
        run_case("only B1", make_cmd(3'b010, 0, 0, 0, 1, 0, 0), 32'h81234567);

        $display("CASE 5: only B0 => C=B0");
        load_neighbors(32'h0, 32'h0, 32'h89abcdef, 32'h0, 32'h0);
        run_case("only B0", make_cmd(3'b001, 0, 0, 1, 0, 0, 0), 32'h89abcdef);

        $display("CASE 6: B0 unavailable, B2 fallback => C=B2");
        load_neighbors(32'h0, 32'h0, 32'h01234567, 32'h0, 32'hfedcba98);
        run_case("only B2 fallback", make_cmd(3'b001, 0, 0, 0, 0, 1, 0),
                 32'hfedcba98);

        $display("CASE 7: A+B with C unavailable => MED(A,B,0)");
        load_neighbors(32'h0, {16'hff38,16'hff9c}, 32'h0,
                       {16'hffce,16'hffd8}, 32'h0);
        run_case("A+B signed MED with zero C",
                 make_cmd(3'b010, 0, 1, 0, 1, 0, 0), 32'hffceffd8);

        $display("CASE 8: A+C with B unavailable => MED(A,0,C)");
        load_neighbors(32'h0, {16'd80,16'd100}, {16'h8000,16'h8000},
                       32'h0, {16'd20,16'd50});
        run_case("A+C MED with zero B", make_cmd(3'b010, 0, 1, 0, 0, 1, 0),
                 32'h00140032);

        $display("CASE 9: B+C with A unavailable => MED(0,B,C)");
        load_neighbors(32'h0, 32'h0, {16'h8000,16'h8000},
                       {16'hffb0,16'hff9c}, {16'hffec,16'hffd8});
        run_case("B+C negative MED with zero A",
                 make_cmd(3'b001, 0, 0, 0, 1, 1, 0), 32'hffecffd8);

        $display("CASE 10: X and Y medians come from different operands");
        load_neighbors(32'h0, {16'd300,16'd50},
                       {16'h8000,16'h8000},
                       {16'hff9c,16'd200}, {16'd100,16'hffec});
        run_case("ABC cross-component median", make_cmd(3'b010, 0, 1, 1, 1, 1, 0),
                 32'h00640032);

        $display("CASE 11: signed negative component median");
        load_neighbors(32'h0, {16'hffe2,16'hfff7},
                       {16'hffce,16'hffe2},
                       {16'hfff6,16'hfff9}, {16'hffd8,16'hffec});
        run_case("negative ABC median", make_cmd(3'b001, 0, 1, 1, 1, 1, 0),
                 32'hffe2fff7);

        $display("CASE 12: equality/ties select an equal median operand");
        load_neighbors(32'h0, {16'hfffb,16'd5},
                       {16'd9,16'd9}, {16'hfffb,16'd5},
                       {16'h8000,16'h8000});
        run_case("A equals B below C", make_cmd(3'b010, 0, 1, 1, 1, 0, 0),
                 {16'hfffb,16'd5});
        load_neighbors(32'h0, {16'hfffb,16'd5},
                       {16'hfffb,16'd5}, {16'hfffb,16'd5}, 32'h0);
        run_case("all three equal", make_cmd(3'b010, 0, 1, 1, 1, 1, 0),
                 {16'hfffb,16'd5});

        $display("CASE 13: P8 and P16 encodings preserve spatial selection");
        load_neighbors(32'h0, {16'hff80,16'h0070},
                       {16'h0010,16'hff20}, {16'hff10,16'h0040},
                       {16'h0030,16'h0020});
        run_case("P16 full availability", make_cmd(3'b010, 0, 1, 1, 1, 1, 0),
                 32'hff800040);
        run_case("P8 full availability", make_cmd(3'b001, 0, 1, 1, 1, 1, 0),
                 32'hff800040);

        $display("CASE 14-16: launch capture, one-cycle done, stable result");
        held_mv = dec_spatial_mvp;
        selected_cu_cmd = make_cmd(3'b001, 0, 0, 0, 0, 0, 0);
        load_neighbors(32'hdeadbeef, 32'hcafef00d, 32'hffffffff,
                       32'h87654321, 32'h01010101);
        repeat (2) begin
            @(posedge clk_vc);
            #1;
            check(dec_spatial_mvp == held_mv && !cand_capture_done,
                  "MVP must hold when inputs change without a start");
        end

        $display("CASE 17: reg_slice_go clears registered MVP and pulse state");
        @(negedge clk_vc);
        reg_slice_go = 1'b1;
        @(posedge clk_vc);
        #1;
        check(dec_spatial_mvp == 0 && !cand_capture_done && !cand_busy,
              "reg_slice_go must clear wrapper state and keep generator idle");
        @(negedge clk_vc);
        reg_slice_go = 1'b0;

        $display("CASE 18: overlapping start is diagnosed and preserves prior result");
        load_neighbors(32'h0, {16'h1234,16'h5678}, 32'h0, 32'h0, 32'h0);
        @(negedge clk_vc);
        selected_cu_cmd = make_cmd(3'b010, 0, 1, 0, 0, 0, 0);
        dec_cand_start = 1'b1;
        @(posedge clk_vc);
        #1;
        check(dec_spatial_mvp == {16'h1234,16'h5678} &&
              cand_capture_done && cand_busy,
              "first transaction must capture before overlap test");
        held_mv = dec_spatial_mvp;
        @(negedge clk_vc);
        dec_cand_start = 1'b0;
        #1;
        dec_cand_start = 1'b1;
        @(posedge clk_vc);
        #1;
        dec_cand_start = 1'b0;
        check(dec_spatial_mvp == held_mv && !cand_capture_done,
              "busy start must not overwrite the previous candidate");
        check(!cand_busy && dut.candidate_blk_idle,
              "generator must return idle after rejecting overlap");
        $display("EXPECTED NEGATIVE-TEST DIAGNOSTIC: overlapping start rejected");

        $display("CASE 19: reset clears captured result and transaction state");
        @(negedge clk_vc);
        vc_rst_z = 1'b0;
        #1;
        check(dec_spatial_mvp == 0 && !cand_capture_done && !cand_busy,
              "asynchronous reset must clear result and transaction state");
        @(negedge clk_vc);
        vc_rst_z = 1'b1;

        $display("CASE 20: P_SKIP retains the spatial predictor (no skip override)");
        load_neighbors(32'h0, {16'd200,16'd100},
                       {16'h8000,16'h8000},
                       {16'd20,16'd40}, {16'h8000,16'h8000});
        run_case("P_SKIP uses spatial MED", make_cmd(3'b010, 0, 1, 0, 1, 0, 1),
                 {16'd20,16'd40});

        if (errors == 0) begin
            $display("T02-B1 RESULT: PASS (%0d candidate transactions)", case_count);
            $finish;
        end
        else begin
            $display("T02-B1 RESULT: FAIL (%0d self-check failures)", errors);
            $fatal(1);
        end
    end

endmodule
