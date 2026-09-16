// T01-B2 directed public-port integration checks for the Decoder Neighbor path.

`timescale 1ns/1ps

module tb_vc_mvp_dec_neib_top;

    localparam [33:0] A_WORD        = 34'h123456789;
    localparam [33:0] B_WORD        = 34'h2ABCDEFFF;
    localparam [33:0] INTERNAL_WORD = 34'h15555555;

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
    reg      [1:0]        dec_txn_a_avail;
    reg      [2:0]        dec_txn_b_avail;
    reg      [6:0]        dec_txn_ctux;
    reg      [6:0]        reg_pic_width_ctu_m1;

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
    wire     [1:0]        dec_a_avail;
    wire     [2:0]        dec_b_avail;
    wire     [1:0]        dec_expected_sub_idx;
    wire                  dec_busy;
    wire     [5:0]        dbg_dec_fsm_cs;

    reg                   cur_cu_upd;
    reg      [1:0]        cur_cu_upd_sz;
    reg      [2:0]        cur_cu_upd_x;
    reg      [2:0]        cur_cu_upd_y;
    reg      [15:0]       cur_cu_upd_mvx;
    reg      [15:0]       cur_cu_upd_mvy;
    reg      [1:0]        cur_cu_upd_refidx;

    wire     [4:0]        irpu2neib_b_req;
    wire     [4:0]        irpu2neib_b_addr;
    wire                  neib_b2irpu_gnt;
    reg                   neib_b2irpu_rd_lat;
    reg      [67:0]       neib_b2irpu_rd;
    wire     [1:0]        irpu2neib_a_req;
    wire     [1:0]        irpu2neib_a_addr;
    wire                  neib_a2irpu_gnt;
    reg                   neib_a2irpu_rd_lat;
    reg      [67:0]       neib_a2irpu_rd;

    wire                  irpu2col_req;
    wire     [4:0]        irpu2col_addr;
    reg                   col2irpu_gnt;
    reg                   col2irpu_rd_lat;
    reg      [83:0]       col2irpu_rd;
    wire                  irpu2ref_req;
    wire     [3:0]        irpu2ref_addr;
    reg                   ref2irpu_gnt;
    reg                   ref2irpu_rd_lat;
    reg      [32:0]       ref2irpu_rd;

    wire                  raw_neib_done_amvp;
    wire                  neib_done_amvp;
    wire                  neib_pending;
    wire     [2:0][33:0]  amvp_neib_b;
    wire     [1:0][33:0]  amvp_neib_a;

    integer errors;
    integer cycle_count;
    integer a_req_count;
    integer b_req_count;
    integer col_req_count;
    integer ref_req_count;
    integer launch_cycle;
    integer raw_done_cycle;
    integer qualified_cycle;
    integer a_count_before;
    integer b_count_before;
    integer k;
    reg     a_req_d;
    reg     b_req_d;
    integer first_a_req_cycle;
    integer first_b_req_cycle;
    integer first_a_rd_lat_cycle;
    integer first_b_rd_lat_cycle;
    integer last_a_rd_lat_cycle;
    integer last_b_rd_lat_cycle;
    integer monitor_a_req_count;
    integer monitor_b_req_count;
    integer stale_a_rd_lat_count;
    integer stale_b_rd_lat_count;
    reg     [4:0] first_b_addr;
    reg     monitor_active;
    reg     monitor_raw_seen_low;
    reg     monitor_raw_high_at_launch;
    reg     stale_a_event_d;
    reg     stale_b_event_d;

    vc_mvp_dec_neib_top dut (
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
        .dec_txn_a_avail      (dec_txn_a_avail),
        .dec_txn_b_avail      (dec_txn_b_avail),
        .dec_txn_ctux         (dec_txn_ctux),
        .reg_pic_width_ctu_m1 (reg_pic_width_ctu_m1),
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
        .dec_a_avail          (dec_a_avail),
        .dec_b_avail          (dec_b_avail),
        .dec_expected_sub_idx (dec_expected_sub_idx),
        .dec_busy             (dec_busy),
        .dbg_dec_fsm_cs       (dbg_dec_fsm_cs),
        .cur_cu_upd           (cur_cu_upd),
        .cur_cu_upd_sz        (cur_cu_upd_sz),
        .cur_cu_upd_x         (cur_cu_upd_x),
        .cur_cu_upd_y         (cur_cu_upd_y),
        .cur_cu_upd_mvx       (cur_cu_upd_mvx),
        .cur_cu_upd_mvy       (cur_cu_upd_mvy),
        .cur_cu_upd_refidx    (cur_cu_upd_refidx),
        .irpu2neib_b_req     (irpu2neib_b_req),
        .irpu2neib_b_addr    (irpu2neib_b_addr),
        .neib_b2irpu_gnt     (neib_b2irpu_gnt),
        .neib_b2irpu_rd_lat  (neib_b2irpu_rd_lat),
        .neib_b2irpu_rd      (neib_b2irpu_rd),
        .irpu2neib_a_req     (irpu2neib_a_req),
        .irpu2neib_a_addr    (irpu2neib_a_addr),
        .neib_a2irpu_gnt     (neib_a2irpu_gnt),
        .neib_a2irpu_rd_lat  (neib_a2irpu_rd_lat),
        .neib_a2irpu_rd      (neib_a2irpu_rd),
        .irpu2col_req        (irpu2col_req),
        .irpu2col_addr       (irpu2col_addr),
        .col2irpu_gnt        (col2irpu_gnt),
        .col2irpu_rd_lat     (col2irpu_rd_lat),
        .col2irpu_rd         (col2irpu_rd),
        .irpu2ref_req        (irpu2ref_req),
        .irpu2ref_addr       (irpu2ref_addr),
        .ref2irpu_gnt        (ref2irpu_gnt),
        .ref2irpu_rd_lat     (ref2irpu_rd_lat),
        .ref2irpu_rd         (ref2irpu_rd),
        .raw_neib_done_amvp  (raw_neib_done_amvp),
        .neib_done_amvp      (neib_done_amvp),
        .neib_pending        (neib_pending),
        .amvp_neib_b         (amvp_neib_b),
        .amvp_neib_a         (amvp_neib_a)
    );

    initial begin
        clk_vc = 1'b0;
        forever #5 clk_vc = ~clk_vc;
    end

    // The legacy engines expose scalar grant/latency handshakes despite the
    // packed request/address widths at this boundary.  Return two words per
    // accepted request after one deterministic pipeline cycle.
    assign neib_a2irpu_gnt = |irpu2neib_a_req;
    assign neib_b2irpu_gnt = |irpu2neib_b_req;

    always @(posedge clk_vc or negedge vc_rst_z) begin
        if (~vc_rst_z) begin
            cycle_count        = 0;
            a_req_count        = 0;
            b_req_count        = 0;
            col_req_count      = 0;
            ref_req_count      = 0;
            a_req_d            <= 1'b0;
            b_req_d            <= 1'b0;
            stale_a_rd_lat_count = 0;
            stale_b_rd_lat_count = 0;
            stale_a_event_d     = 1'b0;
            stale_b_event_d     = 1'b0;
            neib_a2irpu_rd_lat <= 1'b0;
            neib_b2irpu_rd_lat <= 1'b0;
            neib_a2irpu_rd     <= 68'd0;
            neib_b2irpu_rd     <= 68'd0;
        end
        else begin
            cycle_count = cycle_count + 1;
            if (irpu2neib_a_req[0] && neib_a2irpu_gnt) a_req_count = a_req_count + 1;
            if (irpu2neib_b_req[0] && neib_b2irpu_gnt) b_req_count = b_req_count + 1;
            if (irpu2col_req)       col_req_count = col_req_count + 1;
            if (irpu2ref_req)       ref_req_count = ref_req_count + 1;

            // A response seen with a zero Decoder-side count is a stale
            // response from work discarded by a flush.  Record it separately;
            // the wrapper must leave the count at zero rather than wrap.
            stale_a_event_d = neib_a2irpu_rd_lat &&
                              (dut.neib_a_read_pending_q == 4'd0);
            stale_b_event_d = neib_b2irpu_rd_lat &&
                              (dut.neib_b_read_pending_q == 4'd0);
            if (stale_a_event_d) begin
                stale_a_rd_lat_count = stale_a_rd_lat_count + 1;
                $display("Neighbor monitor: stale A rd_lat cycle=%0d pending remains zero",
                         cycle_count);
            end
            if (stale_b_event_d) begin
                stale_b_rd_lat_count = stale_b_rd_lat_count + 1;
                $display("Neighbor monitor: stale B rd_lat cycle=%0d pending remains zero",
                         cycle_count);
            end

            if (irpu2col_req) begin
                $display("FAIL: unexpected Col request at cycle %0d", cycle_count);
                errors = errors + 1;
            end
            if (irpu2ref_req) begin
                $display("FAIL: unexpected RefList request at cycle %0d", cycle_count);
                errors = errors + 1;
            end

            neib_a2irpu_rd_lat <= a_req_d;
            neib_b2irpu_rd_lat <= b_req_d;
            if (a_req_d) neib_a2irpu_rd <= {A_WORD, A_WORD};
            if (b_req_d) neib_b2irpu_rd <= {B_WORD, B_WORD};
            a_req_d <= |irpu2neib_a_req;
            b_req_d <= |irpu2neib_b_req;
        end
    end

    // Persistent transaction monitor.  This runs independently of the task
    // boundaries, which is required because start_transaction() consumes the
    // negedge immediately following the launch pulse.
    always @(negedge clk_vc or negedge vc_rst_z) begin
        if (~vc_rst_z) begin
            launch_cycle              = -1;
            first_a_req_cycle         = -1;
            first_b_req_cycle         = -1;
            first_a_rd_lat_cycle      = -1;
            first_b_rd_lat_cycle      = -1;
            last_a_rd_lat_cycle       = -1;
            last_b_rd_lat_cycle       = -1;
            raw_done_cycle             = -1;
            qualified_cycle            = -1;
            first_b_addr               = 5'd0;
            monitor_active             = 1'b0;
            monitor_raw_seen_low       = 1'b0;
            monitor_raw_high_at_launch = 1'b0;
            monitor_a_req_count        = 0;
            monitor_b_req_count        = 0;
        end
        else begin
            if (stale_a_event_d && (dut.neib_a_read_pending_q != 4'd0))
                begin
                    $display("FAIL: A pending counter changed on stale rd_lat (t=%0t)", $time);
                    errors = errors + 1;
                end
            if (stale_b_event_d && (dut.neib_b_read_pending_q != 4'd0))
                begin
                    $display("FAIL: B pending counter changed on stale rd_lat (t=%0t)", $time);
                    errors = errors + 1;
                end
            if (dec_neib_start) begin
                launch_cycle              = cycle_count;
                first_a_req_cycle         = -1;
                first_b_req_cycle         = -1;
                first_a_rd_lat_cycle      = -1;
                first_b_rd_lat_cycle      = -1;
                last_a_rd_lat_cycle       = -1;
                last_b_rd_lat_cycle       = -1;
                raw_done_cycle             = -1;
                qualified_cycle            = -1;
                first_b_addr               = 5'd0;
                monitor_active             = 1'b1;
                monitor_raw_seen_low       = 1'b0;
                monitor_raw_high_at_launch = raw_neib_done_amvp;
                monitor_a_req_count        = 0;
                monitor_b_req_count        = 0;
            end

            if (monitor_active || dec_neib_start) begin
                if ((first_a_req_cycle < 0) && irpu2neib_a_req[0] &&
                    neib_a2irpu_gnt) begin
                    first_a_req_cycle = cycle_count;
                end
                if (irpu2neib_a_req[0] && neib_a2irpu_gnt)
                    monitor_a_req_count = monitor_a_req_count + 1;
                if ((first_b_req_cycle < 0) && irpu2neib_b_req[0] &&
                    neib_b2irpu_gnt) begin
                    first_b_req_cycle = cycle_count;
                    first_b_addr       = irpu2neib_b_addr;
                end
                if (irpu2neib_b_req[0] && neib_b2irpu_gnt)
                    monitor_b_req_count = monitor_b_req_count + 1;
                if ((first_a_req_cycle == cycle_count) &&
                    (irpu2neib_a_req[0] && neib_a2irpu_gnt))
                    $display("Neighbor monitor: first A request handshake cycle=%0d addr=%0d",
                             cycle_count, irpu2neib_a_addr);
                if ((first_b_req_cycle == cycle_count) &&
                    (irpu2neib_b_req[0] && neib_b2irpu_gnt))
                    $display("Neighbor monitor: first B request handshake cycle=%0d addr=%0d",
                             cycle_count, irpu2neib_b_addr);
                if (neib_a2irpu_rd_lat) begin
                    if (first_a_rd_lat_cycle < 0)
                        first_a_rd_lat_cycle = cycle_count;
                    last_a_rd_lat_cycle = cycle_count;
                    $display("Neighbor monitor: A rd_lat cycle=%0d", cycle_count);
                end
                if (neib_b2irpu_rd_lat) begin
                    if (first_b_rd_lat_cycle < 0)
                        first_b_rd_lat_cycle = cycle_count;
                    last_b_rd_lat_cycle = cycle_count;
                    $display("Neighbor monitor: B rd_lat cycle=%0d", cycle_count);
                end
                if (!raw_neib_done_amvp)
                    monitor_raw_seen_low = 1'b1;
                if (monitor_raw_seen_low && raw_neib_done_amvp &&
                    (raw_done_cycle < 0))
                    raw_done_cycle = cycle_count;
                if (neib_done_amvp && (qualified_cycle < 0)) begin
                    qualified_cycle = cycle_count;
                    $display("Neighbor monitor: launch=%0d raw_high_at_launch=%0d first_A_req=%0d first_B_req=%0d A_req_count=%0d B_req_count=%0d A_rd_lat=%0d..%0d B_rd_lat=%0d..%0d raw_seen_low=%0d raw_done=%0d qualified_done=%0d",
                             launch_cycle, monitor_raw_high_at_launch,
                             first_a_req_cycle, first_b_req_cycle,
                             monitor_a_req_count, monitor_b_req_count,
                             first_a_rd_lat_cycle, last_a_rd_lat_cycle,
                             first_b_rd_lat_cycle, last_b_rd_lat_cycle,
                             monitor_raw_seen_low,
                             raw_done_cycle, qualified_cycle);
                    if (monitor_raw_high_at_launch && !monitor_raw_seen_low)
                        $display("Neighbor monitor: no post-read raw-done transition occurred");
                    monitor_active = 1'b0;
                end
            end
        end
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

    // vc_mvp_rd_mem forms the first B read as follows.  The public wrapper
    // exposes full_addr[5:1], because each SRAM word contains two neighbors.
    function [4:0] expected_first_b_addr;
        input [2:0] txn_ctux_f;
        input [2:0] txn_cux_f;
        input [2:0] txn_cuy_f;
        reg   [2:0] neib_b_addr_f;
        reg   [5:0] full_addr_f;
        begin
            neib_b_addr_f = {((reg_pic_width_ctu_m1[2]) ? txn_ctux_f[2] :
                              (txn_ctux_f[2] ^ txn_cuy_f[1])), txn_ctux_f[1:0]};
            if (txn_cux_f == 3'd0) begin
                // Match vc_mvp_rd_mem's field-wise wrap, not a packed
                // subtraction: the low field is explicitly all ones.
                full_addr_f[5:3] = neib_b_addr_f - 3'd1;
                full_addr_f[2:0] = 3'b111;
            end
            else begin
                full_addr_f[5:3] = neib_b_addr_f;
                full_addr_f[2:0] = txn_cux_f - 3'd1;
            end
            expected_first_b_addr = full_addr_f[5:1];
        end
    endfunction

    task start_transaction;
        input              txn_skip;
        input              txn_part_mode;
        input      [1:0]   txn_sub_idx;
        input      [2:0]   txn_x;
        input      [2:0]   txn_y;
        input      [1:0]   txn_a;
        input      [2:0]   txn_b;
        input      [6:0]   txn_ctux;
        begin
            @(negedge clk_vc);
            ccu2irpu_valid     = 1'b1;
            ccu2irpu_mvd      = 32'd0;
            ccu2irpu_ref_idx  = 4'd0;
            ccu2irpu_is_skip  = txn_skip;
            ccu2irpu_part_mode= txn_part_mode;
            ccu2irpu_sub_idx  = txn_sub_idx;
            dec_txn_cux       = txn_x;
            dec_txn_cuy       = txn_y;
            dec_txn_a_avail   = txn_a;
            dec_txn_b_avail   = txn_b;
            dec_txn_ctux      = txn_ctux;
            check(irpu2ccu_rdy, "controller must be ready before Neighbor launch");
            @(posedge clk_vc);
            #1;
            check(dec_neib_start, "accepted transaction must launch Neighbor stage");
            check(!neib_pending && !neib_done_amvp,
                  "qualified done must remain low before pending is armed");
            @(negedge clk_vc);
            ccu2irpu_valid = 1'b0;
        end
    endtask

    task wait_for_neighbor;
        begin : wait_loop
            for (k = 0; k < 80; k = k + 1) begin
                @(negedge clk_vc);
                if (qualified_cycle >= 0)
                    disable wait_loop;
            end
        end
        check(launch_cycle >= 0, "Neighbor launch must be observed");
        check(qualified_cycle >= 0, "qualified Neighbor completion must occur");
    endtask

    task retire_controller;
        begin
            @(posedge clk_vc);
            #1;
            check(dec_cand_start && !neib_done_amvp,
                  "qualified Neighbor completion must produce one candidate pulse");
            check(!neib_pending, "pending must clear when qualified completion is consumed");
            @(negedge clk_vc);
            cand_capture_done = 1'b1;
            @(posedge clk_vc);
            #1;
            check(dec_recon_start, "candidate completion must produce recon pulse");
            @(negedge clk_vc);
            cand_capture_done = 1'b0;
            recon_done = 1'b1;
            @(posedge clk_vc);
            #1;
            check(dec_busy && !irpu2ccu_rdy,
                  "controller must hold the transaction before MC commit");
            @(negedge clk_vc);
            recon_done = 1'b0;
            mc_commit = 1'b1;
            @(posedge clk_vc);
            #1;
            check(!dec_busy && irpu2ccu_rdy,
                  "MC commit must retire the integrated transaction");
            @(negedge clk_vc);
            mc_commit = 1'b0;
        end
    endtask

    task send_neighbor_update;
        begin
            @(negedge clk_vc);
            cur_cu_upd = 1'b1;
            cur_cu_upd_sz = 2'd1;
            cur_cu_upd_x = 3'd2;
            cur_cu_upd_y = 3'd2;
            cur_cu_upd_mvx = 16'h5555;
            cur_cu_upd_mvy = 16'h1555;
            cur_cu_upd_refidx = 2'd0;
            @(posedge clk_vc);
            @(negedge clk_vc);
            cur_cu_upd = 1'b0;
        end
    endtask

    task flush_pending;
        input use_codec_mode;
        begin : pending_loop
            for (k = 0; k < 30; k = k + 1) begin
                @(negedge clk_vc);
                if (neib_pending && !raw_neib_done_amvp)
                    disable pending_loop;
            end
        end
        check(neib_pending, "flush setup must reach an in-flight Neighbor transaction");
        @(negedge clk_vc);
        if (use_codec_mode)
            codec_mode = 1'b0;
        else
            reg_slice_go = 1'b1;
        @(posedge clk_vc);
        #1;
        check(!neib_pending && !neib_done_amvp,
              "flush must clear pending and qualified completion");
        check(!dec_busy && !dec_cand_start,
              "flush must prevent stale Neighbor completion reaching controller");
        @(negedge clk_vc);
        if (use_codec_mode) begin
            codec_mode = 1'b1;
        end
        else begin
            reg_slice_go = 1'b0;
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
        dec_txn_a_avail = 2'd0;
        dec_txn_b_avail = 3'd0;
        dec_txn_ctux = 7'd0;
        reg_pic_width_ctu_m1 = 7'd7;
        cand_capture_done = 1'b0;
        recon_done = 1'b0;
        mc_commit = 1'b0;
        cur_cu_upd = 1'b0;
        cur_cu_upd_sz = 2'd0;
        cur_cu_upd_x = 3'd0;
        cur_cu_upd_y = 3'd0;
        cur_cu_upd_mvx = 16'd0;
        cur_cu_upd_mvy = 16'd0;
        cur_cu_upd_refidx = 2'd0;
        col2irpu_gnt = 1'b0;
        col2irpu_rd_lat = 1'b0;
        col2irpu_rd = 84'd0;
        ref2irpu_gnt = 1'b0;
        ref2irpu_rd_lat = 1'b0;
        ref2irpu_rd = 33'd0;

        repeat (2) @(posedge clk_vc);
        @(negedge clk_vc);
        vc_rst_z = 1'b1;

        $display("CASE A: P16 external A/B reads and qualified completion");
        a_count_before = a_req_count;
        b_count_before = b_req_count;
        start_transaction(1'b0, 1'b0, 2'd0, 3'd2, 3'd2, 2'b11, 3'b111, 7'd0);
        wait_for_neighbor;
        check(a_req_count > a_count_before && b_req_count > b_count_before,
              "P16 A/B availability must launch SRAM reads");
        check(qualified_cycle >= last_a_rd_lat_cycle &&
              qualified_cycle >= last_b_rd_lat_cycle,
              "P16 completion must not precede the final A/B rd_lat");
        check(amvp_neib_a[0] == A_WORD && amvp_neib_a[1] == A_WORD,
              "P16 A result must contain returned SRAM data");
        check(amvp_neib_b[0] == B_WORD && amvp_neib_b[1] == B_WORD &&
              amvp_neib_b[2] == B_WORD,
              "P16 B result must contain returned SRAM data");
        retire_controller;

        $display("CASE B: P8 S0 external reads");
        a_count_before = a_req_count;
        b_count_before = b_req_count;
        start_transaction(1'b0, 1'b1, 2'd0, 3'd2, 3'd2, 2'b11, 3'b111, 7'd0);
        wait_for_neighbor;
        check(a_req_count > a_count_before && b_req_count > b_count_before,
              "P8 S0 must launch external A/B reads");
        check(amvp_neib_a[0] == A_WORD && amvp_neib_b[0] == B_WORD,
              "P8 S0 must expose returned Neighbor data");
        retire_controller;

        $display("CASE C: P8 S1 internal A/no-read path");
        send_neighbor_update;
        a_count_before = a_req_count;
        b_count_before = b_req_count;
        start_transaction(1'b0, 1'b1, 2'd1, 3'd2, 3'd2, 2'b11, 3'b000, 7'd0);
        wait_for_neighbor;
        check(a_req_count == a_count_before && b_req_count == b_count_before,
              "P8 S1 selected case must require no SRAM reads");
        check(amvp_neib_a[1] == INTERNAL_WORD,
              "P8 S1 must use the locally updated rolling A neighbor");
        check(amvp_neib_b[0] == B_WORD && amvp_neib_b[1] == B_WORD &&
              amvp_neib_b[2] == B_WORD,
              "P8 S1 must retain the prior internal B neighbor view");
        retire_controller;

        $display("CASE D: P_SKIP retains spatial Neighbor acquisition");
        a_count_before = a_req_count;
        b_count_before = b_req_count;
        start_transaction(1'b1, 1'b0, 2'd0, 3'd4, 3'd4, 2'b11, 3'b111, 7'd0);
        wait_for_neighbor;
        check(a_req_count > a_count_before && b_req_count > b_count_before,
              "P_SKIP must not suppress blk16 A/B reads");
        retire_controller;

        $display("CASE E: reg_slice_go clears pending transaction");
        start_transaction(1'b0, 1'b0, 2'd0, 3'd2, 3'd2, 2'b11, 3'b111, 7'd0);
        flush_pending(1'b0);

        $display("CASE F: codec_mode clears pending transaction");
        start_transaction(1'b0, 1'b0, 2'd0, 3'd2, 3'd2, 2'b11, 3'b111, 7'd0);
        flush_pending(1'b1);

        $display("CASE G: non-zero CTU X address context 1");
        start_transaction(1'b0, 1'b0, 2'd0, 3'd2, 3'd2, 2'b11, 3'b111, 7'd1);
        wait_for_neighbor;
        check(first_b_req_cycle >= 0, "non-zero CTU case must issue a B request");
        check(first_b_addr == expected_first_b_addr(3'd1, 3'd2, 3'd2),
              "CTU X=1 B address must match vc_mvp_rd_mem formula");
        check(stale_a_rd_lat_count > 0 && stale_b_rd_lat_count > 0,
              "flush regression must observe stale A/B rd_lat responses");
        check(monitor_a_req_count == 2 && monitor_b_req_count == 3,
              "fresh P16 transaction must count only its own A/B requests");
        check(qualified_cycle >= last_a_rd_lat_cycle &&
              qualified_cycle >= last_b_rd_lat_cycle,
              "fresh external completion must follow its final A/B rd_lat");
        retire_controller;

        $display("CASE H: non-zero CTU X address context 3");
        start_transaction(1'b0, 1'b0, 2'd0, 3'd2, 3'd2, 2'b11, 3'b111, 7'd3);
        wait_for_neighbor;
        check(first_b_req_cycle >= 0, "second non-zero CTU case must issue a B request");
        check(first_b_addr == expected_first_b_addr(3'd3, 3'd2, 3'd2),
              "CTU X=3 B address must match vc_mvp_rd_mem formula");
        check(first_b_addr != 5'd0, "non-zero CTU address must not use CTU-0 address");
        retire_controller;

        $display("CASE I: cux=0 exact B address field-wise wrap");
        start_transaction(1'b0, 1'b0, 2'd0, 3'd0, 3'd2, 2'b00, 3'b111, 7'd3);
        wait_for_neighbor;
        check(first_b_req_cycle >= 0, "cux=0 case must issue a B request");
        check(first_b_addr == expected_first_b_addr(3'd3, 3'd0, 3'd2),
              "cux=0 B address must match field-wise vc_mvp_rd_mem wrap");
        retire_controller;

        $display("CASE J: fresh P8 S0 external transaction after stale response");
        start_transaction(1'b0, 1'b1, 2'd0, 3'd2, 3'd2, 2'b11, 3'b111, 7'd3);
        wait_for_neighbor;
        check(monitor_a_req_count > 0 && monitor_b_req_count > 0,
              "fresh P8 S0 must issue A/B requests");
        retire_controller;

        $display("CASE K: fresh P8 S1 no-read transaction after stale response");
        send_neighbor_update;
        a_count_before = a_req_count;
        b_count_before = b_req_count;
        start_transaction(1'b0, 1'b1, 2'd1, 3'd2, 3'd2, 2'b11, 3'b000, 7'd3);
        wait_for_neighbor;
        check(a_req_count == a_count_before && b_req_count == b_count_before,
              "fresh P8 S1 must issue no A/B SRAM request");
        check(monitor_a_req_count == 0 && monitor_b_req_count == 0,
              "fresh P8 S1 monitor must count zero A/B requests");
        check(amvp_neib_a[1] == INTERNAL_WORD,
              "fresh P8 S1 must retain its local rolling A Neighbor");
        check(amvp_neib_b[0] == B_WORD && amvp_neib_b[1] == B_WORD &&
              amvp_neib_b[2] == B_WORD,
              "fresh P8 S1 must not consume stale B data");
        retire_controller;

        check(col_req_count == 0, "no Col requests are legal in Decoder mode");
        check(ref_req_count == 0, "no RefList requests are legal in Decoder mode");
        $display("Request counts: A=%0d B=%0d Col=%0d RefList=%0d",
                 a_req_count, b_req_count, col_req_count, ref_req_count);
        $display("Stale response counts: A=%0d B=%0d",
                 stale_a_rd_lat_count, stale_b_rd_lat_count);

        if (errors == 0)
            $display("T01-B2 RESULT: PASS");
        else begin
            $display("T01-B2 RESULT: FAIL (%0d self-check failures)", errors);
            $fatal(1);
        end
        $finish;
    end

endmodule
