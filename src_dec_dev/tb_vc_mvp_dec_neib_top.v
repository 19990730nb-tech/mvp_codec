// T01-B2/T06-B directed integration checks for the real Decoder Neighbor
// hierarchy, including same-edge MC retirement into rolling A/B state.

`timescale 1ns/1ps

module tb_vc_mvp_dec_neib_top;

    localparam [33:0] A_WORD        = 34'h123456789;
    localparam [33:0] B_WORD        = 34'h2ABCDEFFF;
    localparam [33:0] INTERNAL_WORD = 34'h15555555;
    localparam [33:0] OLD_STALE_A   = 34'h3ABCDE123;
    localparam [33:0] OLD_STALE_B   = 34'h2FEDCBA98;
    localparam [33:0] FRESH_LOCAL_A    = 34'h0A5A5A5A5;
    localparam [33:0] FRESH_LOCAL_B    = 34'h055AA55AA;
    localparam [31:0] S0_COMMITTED_MV  = 32'h1555_5555;
    localparam integer RESPONSE_SLOTS = 8;

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
    reg      [31:0]       dec_final_mv;
    reg      [3:0]        dec_final_ref_idx;
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

    wire                  cur_cu_upd = dut.cur_cu_upd;
    wire     [1:0]        cur_cu_upd_sz = dut.cur_cu_upd_sz;
    wire     [2:0]        cur_cu_upd_x = dut.cur_cu_upd_x;
    wire     [2:0]        cur_cu_upd_y = dut.cur_cu_upd_y;
    wire     [15:0]       cur_cu_upd_mvx = dut.cur_cu_upd_mvx;
    wire     [15:0]       cur_cu_upd_mvy = dut.cur_cu_upd_mvy;
    wire     [1:0]        cur_cu_upd_refidx = dut.cur_cu_upd_refidx;

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
    integer mc_commit_count;
    integer update_sample_count;
    integer s0_commit_cycle;
    integer s1_accept_cycle;
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
    integer response_delay_cycles;
    reg     [33:0] response_word_a;
    reg     [33:0] response_word_b;
    reg     response_valid_a [0:RESPONSE_SLOTS-1];
    reg     response_valid_b [0:RESPONSE_SLOTS-1];
    integer response_delay_a [0:RESPONSE_SLOTS-1];
    integer response_delay_b [0:RESPONSE_SLOTS-1];
    reg     [33:0] response_data_a [0:RESPONSE_SLOTS-1];
    reg     [33:0] response_data_b [0:RESPONSE_SLOTS-1];
    integer i;
    integer response_slot;
    integer free_slot;
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
    integer overlap_a_cycle;
    integer overlap_b_cycle;
    integer overlap_a_pending_before;
    integer overlap_b_pending_before;
    integer overlap_a_pending_after;
    integer overlap_b_pending_after;
    reg     overlap_monitor_active;
    integer audit_phase;
    integer audit_old_a_rd_cycle;
    integer audit_old_b_rd_cycle;
    integer audit_fresh_a_req_cycle;
    integer audit_fresh_b_req_cycle;
    integer audit_fresh_launch_cycle;
    integer audit_pending_before;
    integer audit_pending_after;
    integer audit_req_hs_at_event;
    integer audit_c_a_pending_before;
    integer audit_c_a_pending_after;
    integer audit_c_b_pending_before;
    integer audit_c_b_pending_after;
    reg     [33:0] audit_c_a_before;
    reg     [33:0] audit_c_b_before;
    integer audit_c_qualified_cycle;
    reg     audit_event_d;
    reg     audit_c_a_event_d;
    reg     audit_c_b_event_d;
    reg     audit_c_snapshot_d;
    reg     audit_old_response_seen;
    integer barrier_flush_cycle;
    integer barrier_a_at_flush;
    integer barrier_b_at_flush;
    integer barrier_a_zero_cycle;
    integer barrier_b_zero_cycle;
    integer barrier_ready_reopen_cycle;
    integer barrier_fresh_accept_cycle;
    integer barrier_fresh_neib_start_cycle;
    integer barrier_first_fresh_req_cycle;
    integer barrier_stale_a_last_cycle;
    integer barrier_stale_b_last_cycle;
    integer barrier_hold_accept_count;
    integer barrier_drain_cycles;
    reg     barrier_test_active;
    reg     barrier_drain_violation;
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
        .dec_final_mv         (dec_final_mv),
        .dec_final_ref_idx    (dec_final_ref_idx),
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

    // Sample the shared MC-retirement/update event on the same active edge
    // used by the real U_GET_NEIB rolling-state writer.
    always @(posedge clk_vc) begin
        if (!vc_rst_z) begin
            mc_commit_count = 0;
            update_sample_count = 0;
            if (cur_cu_upd !== 1'b0) begin
                $display("FAIL: rolling update asserted during reset");
                errors = errors + 1;
            end
        end else begin
            if (mc_commit) begin
                mc_commit_count = mc_commit_count + 1;
                if (cur_cu_upd === 1'b1)
                    update_sample_count = update_sample_count + 1;
                else begin
                    $display("FAIL: mc_commit was not sampled as cur_cu_upd at cycle %0d",
                             cycle_count);
                    errors = errors + 1;
                end
            end else if (cur_cu_upd !== 1'b0) begin
                $display("FAIL: rolling update sampled without mc_commit at cycle %0d",
                         cycle_count);
                errors = errors + 1;
            end
            if ((!codec_mode || reg_slice_go) && (cur_cu_upd !== 1'b0)) begin
                $display("FAIL: rolling update asserted during mode/slice flush at cycle %0d",
                         cycle_count);
                errors = errors + 1;
            end
        end
    end

    // The legacy engines expose scalar grant/latency handshakes despite the
    // packed request/address widths at this boundary.  The slot model keeps
    // accepted requests alive after a flush so this TB can deliberately
    // return old responses while a later Decoder transaction is active.
    assign neib_a2irpu_gnt = |irpu2neib_a_req;
    assign neib_b2irpu_gnt = |irpu2neib_b_req;

    always @(posedge clk_vc or negedge vc_rst_z) begin
        if (~vc_rst_z) begin
            cycle_count        = 0;
            a_req_count        = 0;
            b_req_count        = 0;
            col_req_count      = 0;
            ref_req_count      = 0;
            stale_a_rd_lat_count = 0;
            stale_b_rd_lat_count = 0;
            stale_a_event_d     = 1'b0;
            stale_b_event_d     = 1'b0;
            audit_event_d       = 1'b0;
            audit_c_a_event_d   = 1'b0;
            audit_c_b_event_d   = 1'b0;
            audit_old_response_seen = 1'b0;
            neib_a2irpu_rd_lat <= 1'b0;
            neib_b2irpu_rd_lat <= 1'b0;
            neib_a2irpu_rd     <= 68'd0;
            neib_b2irpu_rd     <= 68'd0;
            for (i = 0; i < RESPONSE_SLOTS; i = i + 1) begin
                response_valid_a[i] = 1'b0;
                response_valid_b[i] = 1'b0;
                response_delay_a[i] = 0;
                response_delay_b[i] = 0;
                response_data_a[i] = 34'd0;
                response_data_b[i] = 34'd0;
            end
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
                              ((dut.neib_a_read_pending_q == 4'd0) ||
                               (neib_a2irpu_rd[33:0] == OLD_STALE_A));
            stale_b_event_d = neib_b2irpu_rd_lat &&
                              ((dut.neib_b_read_pending_q == 4'd0) ||
                               (neib_b2irpu_rd[33:0] == OLD_STALE_B));
            if (stale_a_event_d) begin
                stale_a_rd_lat_count = stale_a_rd_lat_count + 1;
                $display("Neighbor monitor: late/stale A rd_lat cycle=%0d",
                         cycle_count);
            end
            if (stale_b_event_d) begin
                stale_b_rd_lat_count = stale_b_rd_lat_count + 1;
                $display("Neighbor monitor: late/stale B rd_lat cycle=%0d",
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

            if (barrier_test_active) begin
                if (neib_a2irpu_rd_lat &&
                    (neib_a2irpu_rd[33:0] == OLD_STALE_A)) begin
                    barrier_stale_a_last_cycle = cycle_count;
                    $display("BARRIER: stale A rd_lat cycle=%0d pending_before=%0d",
                             cycle_count, dut.neib_a_read_pending_q);
                end
                if (neib_b2irpu_rd_lat &&
                    (neib_b2irpu_rd[33:0] == OLD_STALE_B)) begin
                    barrier_stale_b_last_cycle = cycle_count;
                    $display("BARRIER: stale B rd_lat cycle=%0d pending_before=%0d",
                             cycle_count, dut.neib_b_read_pending_q);
                end
                if ((barrier_fresh_accept_cycle < 0) &&
                    !dut.neib_mem_quiescent &&
                    irpu2neib_a_req[0] && neib_a2irpu_gnt) begin
                    $display("FAIL: fresh A request during Neighbor drain at cycle %0d",
                             cycle_count);
                    barrier_drain_violation = 1'b1;
                    errors = errors + 1;
                end
                if ((barrier_fresh_accept_cycle < 0) &&
                    !dut.neib_mem_quiescent &&
                    irpu2neib_b_req[0] && neib_b2irpu_gnt) begin
                    $display("FAIL: fresh B request during Neighbor drain at cycle %0d",
                             cycle_count);
                    barrier_drain_violation = 1'b1;
                    errors = errors + 1;
                end
                if (ccu2irpu_valid && irpu2ccu_rdy) begin
                    barrier_fresh_accept_cycle = cycle_count;
                    barrier_hold_accept_count = barrier_hold_accept_count + 1;
                    $display("BARRIER: fresh external accept cycle=%0d",
                             cycle_count);
                end
            end

            neib_a2irpu_rd_lat <= 1'b0;
            neib_b2irpu_rd_lat <= 1'b0;

            response_slot = -1;
            for (i = 0; i < RESPONSE_SLOTS; i = i + 1)
                if ((response_slot < 0) && response_valid_a[i] &&
                    (response_delay_a[i] <= 0))
                    response_slot = i;
            if (response_slot >= 0) begin
                neib_a2irpu_rd_lat <= 1'b1;
                neib_a2irpu_rd <= {response_data_a[response_slot],
                                    response_data_a[response_slot]};
                response_valid_a[response_slot] = 1'b0;
            end
            response_slot = -1;
            for (i = 0; i < RESPONSE_SLOTS; i = i + 1)
                if ((response_slot < 0) && response_valid_b[i] &&
                    (response_delay_b[i] <= 0))
                    response_slot = i;
            if (response_slot >= 0) begin
                neib_b2irpu_rd_lat <= 1'b1;
                neib_b2irpu_rd <= {response_data_b[response_slot],
                                    response_data_b[response_slot]};
                response_valid_b[response_slot] = 1'b0;
            end

            for (i = 0; i < RESPONSE_SLOTS; i = i + 1) begin
                if (response_valid_a[i] && (response_delay_a[i] > 0))
                    response_delay_a[i] = response_delay_a[i] - 1;
                if (response_valid_b[i] && (response_delay_b[i] > 0))
                    response_delay_b[i] = response_delay_b[i] - 1;
            end

            if (irpu2neib_a_req[0] && neib_a2irpu_gnt) begin
                free_slot = -1;
                for (i = 0; i < RESPONSE_SLOTS; i = i + 1)
                    if ((free_slot < 0) && !response_valid_a[i]) free_slot = i;
                if (free_slot < 0) begin
                    $display("FAIL: A response queue overflow at cycle %0d", cycle_count);
                    errors = errors + 1;
                end
                else begin
                    response_valid_a[free_slot] = 1'b1;
                    response_delay_a[free_slot] = response_delay_cycles;
                    response_data_a[free_slot] = response_word_a;
                end
            end
            if (irpu2neib_b_req[0] && neib_b2irpu_gnt) begin
                free_slot = -1;
                for (i = 0; i < RESPONSE_SLOTS; i = i + 1)
                    if ((free_slot < 0) && !response_valid_b[i]) free_slot = i;
                if (free_slot < 0) begin
                    $display("FAIL: B response queue overflow at cycle %0d", cycle_count);
                    errors = errors + 1;
                end
                else begin
                    response_valid_b[free_slot] = 1'b1;
                    response_delay_b[free_slot] = response_delay_cycles;
                    response_data_b[free_slot] = response_word_b;
                end
            end

            // Capture the audit event at the edge where the DUT consumes the
            // response.  The following negedge records the post-edge count.
            if (audit_phase == 1 && irpu2neib_a_req[0] && neib_a2irpu_gnt &&
                neib_a2irpu_rd_lat &&
                (neib_a2irpu_rd[33:0] == OLD_STALE_A)) begin
                audit_fresh_a_req_cycle = cycle_count;
                audit_pending_before = dut.neib_a_read_pending_q;
                audit_req_hs_at_event = 1;
                audit_event_d = 1'b1;
                audit_old_a_rd_cycle = cycle_count;
                audit_old_response_seen = 1'b1;
                $display("AUDIT A: old stale A rd_lat + fresh A req_hs cycle=%0d pending_before=%0d",
                         cycle_count, audit_pending_before);
            end
            if (audit_phase == 2 && neib_b2irpu_rd_lat &&
                (neib_b2irpu_rd[33:0] == OLD_STALE_B) &&
                (dut.neib_b_read_pending_q != 4'd0)) begin
                audit_old_b_rd_cycle = cycle_count;
                audit_pending_before = dut.neib_b_read_pending_q;
                audit_req_hs_at_event = irpu2neib_b_req[0] && neib_b2irpu_gnt;
                audit_event_d = 1'b1;
                audit_old_response_seen = 1'b1;
                $display("AUDIT B: old stale B rd_lat while fresh pending cycle=%0d req_hs=%0d pending_before=%0d",
                         cycle_count, audit_req_hs_at_event, audit_pending_before);
            end
            if ((audit_phase == 2) && irpu2neib_b_req[0] &&
                neib_b2irpu_gnt && (audit_fresh_b_req_cycle < 0))
                audit_fresh_b_req_cycle = cycle_count;
            if (audit_phase == 3 && dec_neib_start && dec_part_mode &&
                (dec_a_avail == 2'b00) && (dec_b_avail == 3'b000)) begin
                audit_fresh_launch_cycle = cycle_count;
                audit_c_snapshot_d = 1'b1;
                $display("AUDIT C: fresh P8/internal launch cycle=%0d raw_high=%0d",
                         cycle_count, raw_neib_done_amvp);
            end
            if (audit_phase == 3 && (audit_old_a_rd_cycle < 0) &&
                neib_a2irpu_rd_lat &&
                (neib_a2irpu_rd[33:0] == OLD_STALE_A)) begin
                audit_old_a_rd_cycle = cycle_count;
                audit_c_a_pending_before = dut.neib_a_read_pending_q;
                audit_c_a_event_d = 1'b1;
                audit_old_response_seen = 1'b1;
                $display("AUDIT C: old stale A rd_lat during fresh transaction cycle=%0d pending_before=%0d",
                         cycle_count, audit_c_a_pending_before);
            end
            if (audit_phase == 3 && (audit_old_b_rd_cycle < 0) &&
                neib_b2irpu_rd_lat &&
                (neib_b2irpu_rd[33:0] == OLD_STALE_B)) begin
                audit_old_b_rd_cycle = cycle_count;
                audit_c_b_pending_before = dut.neib_b_read_pending_q;
                audit_c_b_event_d = 1'b1;
                audit_old_response_seen = 1'b1;
                $display("AUDIT C: old stale B rd_lat during fresh transaction cycle=%0d pending_before=%0d",
                         cycle_count, audit_c_b_pending_before);
            end
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
            audit_phase               = 0;
            audit_old_a_rd_cycle      = -1;
            audit_old_b_rd_cycle      = -1;
            audit_fresh_a_req_cycle   = -1;
            audit_fresh_b_req_cycle   = -1;
            audit_fresh_launch_cycle  = -1;
            audit_pending_before      = -1;
            audit_pending_after       = -1;
            audit_req_hs_at_event     = 0;
            audit_c_a_pending_before  = -1;
            audit_c_a_pending_after   = -1;
            audit_c_b_pending_before  = -1;
            audit_c_b_pending_after   = -1;
            audit_event_d             = 1'b0;
            audit_c_a_event_d         = 1'b0;
            audit_c_b_event_d         = 1'b0;
            audit_c_snapshot_d        = 1'b0;
            audit_old_response_seen   = 1'b0;
            barrier_flush_cycle       = -1;
            barrier_a_at_flush        = -1;
            barrier_b_at_flush        = -1;
            barrier_a_zero_cycle      = -1;
            barrier_b_zero_cycle      = -1;
            barrier_ready_reopen_cycle= -1;
            barrier_fresh_accept_cycle= -1;
            barrier_fresh_neib_start_cycle = -1;
            barrier_first_fresh_req_cycle = -1;
            barrier_stale_a_last_cycle = -1;
            barrier_stale_b_last_cycle = -1;
            barrier_hold_accept_count = 0;
            barrier_drain_cycles      = 0;
            barrier_test_active       = 1'b0;
            barrier_drain_violation   = 1'b0;
        end
        else begin
            if (barrier_test_active) begin
                if ((barrier_fresh_accept_cycle < 0) &&
                    !dut.neib_mem_quiescent) begin
                    if (irpu2ccu_rdy) begin
                        $display("FAIL: irpu2ccu_rdy rose during Neighbor drain at cycle %0d",
                                 cycle_count);
                        barrier_drain_violation = 1'b1;
                        errors = errors + 1;
                    end
                    if (dec_neib_start) begin
                        $display("FAIL: dec_neib_start asserted during drain at cycle %0d",
                                 cycle_count);
                        barrier_drain_violation = 1'b1;
                        errors = errors + 1;
                    end
                    if ((barrier_hold_accept_count == 0) &&
                        !ccu2irpu_valid) begin
                        $display("FAIL: held ccu2irpu_valid dropped during drain at cycle %0d",
                                 cycle_count);
                        barrier_drain_violation = 1'b1;
                        errors = errors + 1;
                    end
                    if (neib_done_amvp || dec_cand_start) begin
                        $display("FAIL: stale drain produced Neighbor completion activity at cycle %0d",
                                 cycle_count);
                        barrier_drain_violation = 1'b1;
                        errors = errors + 1;
                    end
                    barrier_drain_cycles = barrier_drain_cycles + 1;
                    if (dut.dec_ctux_q == 7'd5) begin
                        $display("FAIL: fresh CTU-X context latched during drain at cycle %0d",
                                 cycle_count);
                        barrier_drain_violation = 1'b1;
                        errors = errors + 1;
                    end
                end
                if (barrier_a_zero_cycle < 0 &&
                    (dut.neib_a_read_pending_q == 4'd0)) begin
                    barrier_a_zero_cycle = cycle_count;
                    $display("BARRIER: A outstanding reached zero cycle=%0d",
                             cycle_count);
                end
                if (barrier_b_zero_cycle < 0 &&
                    (dut.neib_b_read_pending_q == 4'd0)) begin
                    barrier_b_zero_cycle = cycle_count;
                    $display("BARRIER: B outstanding reached zero cycle=%0d",
                             cycle_count);
                end
                if (barrier_ready_reopen_cycle < 0 &&
                    dut.neib_mem_quiescent && irpu2ccu_rdy) begin
                    barrier_ready_reopen_cycle = cycle_count;
                    $display("BARRIER: ready reopened cycle=%0d",
                             cycle_count);
                end
                if (dec_neib_start && (barrier_fresh_accept_cycle >= 0) &&
                    (barrier_fresh_neib_start_cycle < 0)) begin
                    barrier_fresh_neib_start_cycle = cycle_count;
                    $display("BARRIER: fresh dec_neib_start cycle=%0d",
                             cycle_count);
                end
            end
            if (audit_event_d) begin
                audit_pending_after = dut.neib_a_read_pending_q;
                if (audit_phase == 2)
                    audit_pending_after = dut.neib_b_read_pending_q;
                $display("AUDIT %0s: pending_after=%0d",
                         (audit_phase == 1) ? "A" :
                         ((audit_phase == 2) ? "B" : "C"),
                         audit_pending_after);
                audit_event_d = 1'b0;
            end
            if (audit_c_a_event_d) begin
                audit_c_a_pending_after = dut.neib_a_read_pending_q;
                $display("AUDIT C: A pending_after=%0d fresh_a[1]=%h",
                         audit_c_a_pending_after, amvp_neib_a[1]);
                if (amvp_neib_a[1] != audit_c_a_before) begin
                    $display("FAIL: AUDIT C stale A response overwrote fresh local A data");
                    errors = errors + 1;
                end
                audit_c_a_event_d = 1'b0;
            end
            if (audit_c_b_event_d) begin
                audit_c_b_pending_after = dut.neib_b_read_pending_q;
                $display("AUDIT C: B pending_after=%0d fresh_b[1]=%h",
                         audit_c_b_pending_after, amvp_neib_b[1]);
                if (amvp_neib_b[1] != audit_c_b_before) begin
                    $display("FAIL: AUDIT C stale B response overwrote fresh local B data");
                    errors = errors + 1;
                end
                audit_c_b_event_d = 1'b0;
            end
            if (audit_c_snapshot_d) begin
                audit_c_a_before = amvp_neib_a[1];
                audit_c_b_before = amvp_neib_b[1];
                $display("AUDIT C: fresh local snapshot A1=%h B1=%h",
                         audit_c_a_before, audit_c_b_before);
                audit_c_snapshot_d = 1'b0;
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
            if (condition !== 1'b1) begin
                $display("FAIL: %0s (t=%0t)", message, $time);
                errors = errors + 1;
            end
        end
    endtask

    task check_update_zero;
        input [8*96-1:0] message;
        begin
            check(cur_cu_upd === 1'b0, message);
            check(cur_cu_upd_sz === 2'd0, message);
            check(cur_cu_upd_x === 3'd0, message);
            check(cur_cu_upd_y === 3'd0, message);
            check(cur_cu_upd_mvx === 16'd0, message);
            check(cur_cu_upd_mvy === 16'd0, message);
            check(cur_cu_upd_refidx === 2'd0, message);
        end
    endtask

    task check_update_for_retirement;
        input [31:0] final_mv;
        input [3:0] final_refidx;
        input [8*96-1:0] message;
        reg [1:0] expected_sz;
        reg [2:0] expected_x;
        reg [2:0] expected_y;
        begin
            if (dec_part_mode) begin
                expected_sz = 2'd1;
                expected_x = dec_cux + dec_sub_idx[0];
                expected_y = dec_cuy + dec_sub_idx[1];
            end else begin
                expected_sz = 2'd2;
                expected_x = {dec_cux[2:1], 1'b0};
                expected_y = {dec_cuy[2:1], 1'b0};
            end
            check(cur_cu_upd === 1'b1, message);
            check(cur_cu_upd_sz === expected_sz, message);
            check(cur_cu_upd_x === expected_x, message);
            check(cur_cu_upd_y === expected_y, message);
            check(cur_cu_upd_mvx === final_mv[15:0], message);
            check(cur_cu_upd_mvy === final_mv[31:16], message);
            check(cur_cu_upd_refidx === final_refidx[1:0], message);
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
            check(!mc_commit && !cur_cu_upd,
                  "next transaction cannot start before prior retirement completes");
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

    // Used immediately after a retirement helper returns on the deasserting
    // negedge: presents the next beat for acceptance on the earliest legal
    // rising edge, with no extra idle cycle.
    task start_transaction_earliest;
        input              txn_skip;
        input              txn_part_mode;
        input      [1:0]   txn_sub_idx;
        input      [2:0]   txn_x;
        input      [2:0]   txn_y;
        input      [1:0]   txn_a;
        input      [2:0]   txn_b;
        input      [6:0]   txn_ctux;
        begin
            check(!mc_commit && !cur_cu_upd,
                  "earliest next acceptance follows deasserted prior commit");
            check(irpu2ccu_rdy, "controller ready at earliest next acceptance");
            ccu2irpu_valid      = 1'b1;
            ccu2irpu_mvd        = 32'd0;
            ccu2irpu_ref_idx    = 4'd0;
            ccu2irpu_is_skip    = txn_skip;
            ccu2irpu_part_mode  = txn_part_mode;
            ccu2irpu_sub_idx    = txn_sub_idx;
            dec_txn_cux         = txn_x;
            dec_txn_cuy         = txn_y;
            dec_txn_a_avail     = txn_a;
            dec_txn_b_avail     = txn_b;
            dec_txn_ctux        = txn_ctux;
            @(posedge clk_vc);
            #1;
            s1_accept_cycle = cycle_count;
            check(dec_neib_start,
                  "next P8 sub-block accepted at earliest normal opportunity");
            check(!mc_commit && !cur_cu_upd,
                  "next acceptance is not a repeated prior retirement");
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
        input [31:0] final_mv;
        input [3:0] final_refidx;
        integer commits_before;
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
            dec_final_mv = final_mv;
            dec_final_ref_idx = final_refidx;
            commits_before = mc_commit_count;
            mc_commit = 1'b1;
            #1;
            check_update_for_retirement(final_mv, final_refidx,
                                        "combinational update before retirement edge");
            if (dec_part_mode && (dec_sub_idx === 2'd0) &&
                (dec_cux === 3'd2) && (dec_cuy === 3'd2) &&
                (final_mv === S0_COMMITTED_MV) && (final_refidx === 4'd0) &&
                (s0_commit_cycle < 0)) begin
                $display("T06-B S0 PREEDGE: cycle=%0d mc_commit=%b cur_cu_upd=%b size=%0d x=%0d y=%0d mvx=%h mvy=%h ref=%0d",
                         cycle_count + 1, mc_commit, cur_cu_upd, cur_cu_upd_sz,
                         cur_cu_upd_x, cur_cu_upd_y, cur_cu_upd_mvx,
                         cur_cu_upd_mvy, cur_cu_upd_refidx);
            end
            @(posedge clk_vc);
            #1;
            check(!dec_busy && irpu2ccu_rdy,
                  "MC commit must retire the integrated transaction");
            check(mc_commit_count == commits_before + 1,
                  "one-cycle mc_commit must be sampled on exactly one edge");
            check(update_sample_count == commits_before + 1,
                  "one-cycle mc_commit must produce exactly one sampled update");
            check_update_for_retirement(final_mv, final_refidx,
                                        "update payload held through retirement edge");
            if (dec_part_mode && (dec_sub_idx === 2'd0) &&
                (dec_cux === 3'd2) && (dec_cuy === 3'd2) &&
                (final_mv === S0_COMMITTED_MV) && (final_refidx === 4'd0) &&
                (s0_commit_cycle < 0)) begin
                s0_commit_cycle = cycle_count;
                check(dut.U_GET_NEIB.a_0_reg[2] === {2'b00, S0_COMMITTED_MV},
                      "real rolling A state captures P8 S0 result on commit edge");
                check(dut.U_GET_NEIB.b_0_reg[2] === {2'b00, S0_COMMITTED_MV},
                      "real rolling B state captures P8 S0 result on commit edge");
                $display("T06-B S0 COMMIT EDGE: cycle=%0d mc_commit=%b cur_cu_upd=%b A0[2]=%h B0[2]=%h",
                         s0_commit_cycle, mc_commit, cur_cu_upd,
                         dut.U_GET_NEIB.a_0_reg[2], dut.U_GET_NEIB.b_0_reg[2]);
            end
            @(negedge clk_vc);
            mc_commit = 1'b0;
            #1;
            check_update_zero("update and payload clear immediately after commit falls");
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
        begin : drain_loop
            for (k = 0; k < 80; k = k + 1) begin
                @(negedge clk_vc);
                if (dut.neib_mem_quiescent)
                    disable drain_loop;
            end
        end
        check(dut.neib_mem_quiescent,
              "flush must wait for all physical Neighbor responses to drain");
    endtask

    // Assert/release a flush but return before the physical response slots
    // drain.  The barrier test uses this window to hold a new valid beat.
    task flush_pending_no_wait;
        input use_codec_mode;
        begin : pending_setup
            for (k = 0; k < 30; k = k + 1) begin
                @(negedge clk_vc);
                if (neib_pending && !raw_neib_done_amvp)
                    disable pending_setup;
            end
        end
        check(neib_pending, "barrier setup must reach an in-flight Neighbor transaction");
        @(negedge clk_vc);
        if (use_codec_mode)
            codec_mode = 1'b0;
        else
            reg_slice_go = 1'b1;
        @(posedge clk_vc);
        #1;
        barrier_flush_cycle = cycle_count;
        barrier_a_at_flush = dut.neib_a_read_pending_q;
        barrier_b_at_flush = dut.neib_b_read_pending_q;
        check(!neib_pending && !neib_done_amvp,
              "barrier flush must clear Decoder Neighbor pending");
        check(!dec_busy && !dec_cand_start,
              "barrier flush must clear Decoder controller activity");
        if ((barrier_a_at_flush != 0) || (barrier_b_at_flush != 0))
            check(!irpu2ccu_rdy,
                  "external Decoder ready must be low while stale reads drain");
        $display("BARRIER: flush cycle=%0d A_outstanding=%0d B_outstanding=%0d ready=%0d",
                 barrier_flush_cycle, barrier_a_at_flush, barrier_b_at_flush,
                 irpu2ccu_rdy);
        @(negedge clk_vc);
        if (use_codec_mode)
            codec_mode = 1'b1;
        else
            reg_slice_go = 1'b0;
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
        dec_final_mv = 32'd0;
        dec_final_ref_idx = 4'd0;
        mc_commit_count = 0;
        update_sample_count = 0;
        s0_commit_cycle = -1;
        s1_accept_cycle = -1;
        response_delay_cycles = 0;
        response_word_a = A_WORD;
        response_word_b = B_WORD;
        col2irpu_gnt = 1'b0;
        col2irpu_rd_lat = 1'b0;
        col2irpu_rd = 84'd0;
        ref2irpu_gnt = 1'b0;
        ref2irpu_rd_lat = 1'b0;
        ref2irpu_rd = 33'd0;

        mc_commit = 1'b1;
        #1;
        check_update_zero("reset suppresses rolling update");
        mc_commit = 1'b0;
        repeat (2) @(posedge clk_vc);
        @(negedge clk_vc);
        vc_rst_z = 1'b1;

        // Verify the adapter's guards directly with commit high, without
        // allowing a clock edge to present an illegal controller retirement.
        codec_mode = 1'b0;
        mc_commit = 1'b1;
        #1;
        check_update_zero("codec-mode suppression blocks rolling update");
        mc_commit = 1'b0;
        codec_mode = 1'b1;
        reg_slice_go = 1'b1;
        mc_commit = 1'b1;
        #1;
        check_update_zero("slice flush blocks rolling update");
        mc_commit = 1'b0;
        reg_slice_go = 1'b0;

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
        retire_controller(32'h0102_0304, 4'd0);

        $display("CASE B: P8 S0 external reads");
        a_count_before = a_req_count;
        b_count_before = b_req_count;
        start_transaction(1'b0, 1'b1, 2'd0, 3'd2, 3'd2, 2'b11, 3'b111, 7'd0);
        wait_for_neighbor;
        check(a_req_count > a_count_before && b_req_count > b_count_before,
              "P8 S0 must launch external A/B reads");
        check(amvp_neib_a[0] == A_WORD && amvp_neib_b[0] == B_WORD,
              "P8 S0 must expose returned Neighbor data");
        retire_controller(S0_COMMITTED_MV, 4'd0);

        $display("CASE C: P8 S1 internal A/no-read path");
        a_count_before = a_req_count;
        b_count_before = b_req_count;
        start_transaction_earliest(1'b0, 1'b1, 2'd1, 3'd2, 3'd2,
                                   2'b11, 3'b000, 7'd0);
        check(s1_accept_cycle == s0_commit_cycle + 1,
              "P8 S1 acceptance is the first edge after S0 retirement");
        $display("T06-B S1 EARLIEST ACCEPT: S0_commit_cycle=%0d S1_accept_cycle=%0d",
                 s0_commit_cycle, s1_accept_cycle);
        wait_for_neighbor;
        check(a_req_count == a_count_before && b_req_count == b_count_before,
              "P8 S1 selected case must require no SRAM reads");
        check(amvp_neib_a[1] === {2'b00, S0_COMMITTED_MV},
              "P8 S1 must read the exact MC-committed S0 result from rolling A state");
        check(amvp_neib_b[0] == B_WORD && amvp_neib_b[1] == B_WORD &&
              amvp_neib_b[2] == B_WORD,
              "P8 S1 must retain the prior internal B neighbor view");
        retire_controller(32'h2666_6666, 4'd0);

        $display("CASE D: P_SKIP retains spatial Neighbor acquisition");
        a_count_before = a_req_count;
        b_count_before = b_req_count;
        start_transaction(1'b1, 1'b0, 2'd0, 3'd4, 3'd4, 2'b11, 3'b111, 7'd0);
        wait_for_neighbor;
        check(a_req_count > a_count_before && b_req_count > b_count_before,
              "P_SKIP must not suppress blk16 A/B reads");
        retire_controller(32'h0bad_cafe, 4'd0);

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
        check(monitor_a_req_count == 2 && monitor_b_req_count == 3,
              "fresh P16 transaction must count only its own A/B requests");
        check(qualified_cycle >= last_a_rd_lat_cycle &&
              qualified_cycle >= last_b_rd_lat_cycle,
              "fresh external completion must follow its final A/B rd_lat");
        retire_controller(32'h1111_2222, 4'd0);

        $display("CASE H: non-zero CTU X address context 3");
        start_transaction(1'b0, 1'b0, 2'd0, 3'd2, 3'd2, 2'b11, 3'b111, 7'd3);
        wait_for_neighbor;
        check(first_b_req_cycle >= 0, "second non-zero CTU case must issue a B request");
        check(first_b_addr == expected_first_b_addr(3'd3, 3'd2, 3'd2),
              "CTU X=3 B address must match vc_mvp_rd_mem formula");
        check(first_b_addr != 5'd0, "non-zero CTU address must not use CTU-0 address");
        retire_controller(32'h3333_4444, 4'd0);

        $display("CASE I: cux=0 exact B address field-wise wrap");
        start_transaction(1'b0, 1'b0, 2'd0, 3'd0, 3'd2, 2'b00, 3'b111, 7'd3);
        wait_for_neighbor;
        check(first_b_req_cycle >= 0, "cux=0 case must issue a B request");
        check(first_b_addr == expected_first_b_addr(3'd3, 3'd0, 3'd2),
              "cux=0 B address must match field-wise vc_mvp_rd_mem wrap");
        retire_controller(32'h5555_6666, 4'd0);

        $display("CASE J: fresh P8 S0 external transaction after stale response");
        start_transaction(1'b0, 1'b1, 2'd0, 3'd2, 3'd2, 2'b11, 3'b111, 7'd3);
        wait_for_neighbor;
        check(monitor_a_req_count > 0 && monitor_b_req_count > 0,
              "fresh P8 S0 must issue A/B requests");
        retire_controller(S0_COMMITTED_MV, 4'd0);

        $display("CASE K: fresh P8 S1 no-read transaction after stale response");
        a_count_before = a_req_count;
        b_count_before = b_req_count;
        start_transaction(1'b0, 1'b1, 2'd1, 3'd2, 3'd2, 2'b11, 3'b000, 7'd3);
        wait_for_neighbor;
        check(a_req_count == a_count_before && b_req_count == b_count_before,
              "fresh P8 S1 must issue no A/B SRAM request");
        check(monitor_a_req_count == 0 && monitor_b_req_count == 0,
              "fresh P8 S1 monitor must count zero A/B requests");
        check(amvp_neib_a[1] === {2'b00, S0_COMMITTED_MV},
              "fresh P8 S1 must consume the committed S0 rolling A value");
        check(amvp_neib_b[0] == B_WORD && amvp_neib_b[1] == B_WORD &&
              amvp_neib_b[2] == B_WORD,
              "fresh P8 S1 must not consume stale B data");
        retire_controller(32'h7777_8888, 4'd0);

        $display("CASE L: post-flush Neighbor drain barrier");
        barrier_test_active = 1'b0;
        barrier_flush_cycle = -1;
        barrier_a_at_flush = -1;
        barrier_b_at_flush = -1;
        barrier_a_zero_cycle = -1;
        barrier_b_zero_cycle = -1;
        barrier_ready_reopen_cycle = -1;
        barrier_fresh_accept_cycle = -1;
        barrier_fresh_neib_start_cycle = -1;
        barrier_first_fresh_req_cycle = -1;
        barrier_stale_a_last_cycle = -1;
        barrier_stale_b_last_cycle = -1;
        barrier_hold_accept_count = 0;
        barrier_drain_cycles = 0;
        barrier_drain_violation = 1'b0;
        response_delay_cycles = 5;
        response_word_a = OLD_STALE_A;
        response_word_b = OLD_STALE_B;
        start_transaction(1'b0, 1'b0, 2'd0, 3'd2, 3'd2, 2'b11, 3'b111, 7'd0);
        barrier_test_active = 1'b0;
        flush_pending_no_wait(1'b0);

        // Hold one fresh external-read transaction valid throughout drain.
        response_delay_cycles = 0;
        response_word_a = A_WORD;
        response_word_b = B_WORD;
        @(negedge clk_vc);
        ccu2irpu_valid      = 1'b1;
        ccu2irpu_mvd       = 32'd0;
        ccu2irpu_ref_idx   = 4'd0;
        ccu2irpu_is_skip   = 1'b0;
        ccu2irpu_part_mode = 1'b0;
        ccu2irpu_sub_idx   = 2'd0;
        dec_txn_cux        = 3'd2;
        dec_txn_cuy        = 3'd2;
        dec_txn_a_avail    = 2'b11;
        dec_txn_b_avail    = 3'b111;
        dec_txn_ctux       = 7'd5;
        barrier_test_active = 1'b1;
        begin : barrier_hold_loop
            for (k = 0; k < 80; k = k + 1) begin
                @(negedge clk_vc);
                if (dut.neib_mem_quiescent)
                    disable barrier_hold_loop;
            end
        end
        check(dut.neib_mem_quiescent,
              "held-valid barrier must eventually reach memory quiescence");
        check(!barrier_drain_violation,
              "held-valid barrier must block all fresh activity during drain");
        check(barrier_a_zero_cycle >= 0 && barrier_b_zero_cycle >= 0,
              "both physical Neighbor outstanding counts must reach zero");
        check(barrier_ready_reopen_cycle >= 0,
              "Decoder ready must reopen after final stale response");
        check(irpu2ccu_rdy,
              "ready must reopen once held valid reaches a quiescent boundary");
        @(posedge clk_vc);
        #1;
        check(dec_neib_start, "held valid must be accepted after drain");
        ccu2irpu_valid = 1'b0;
        @(negedge clk_vc);
        check(barrier_hold_accept_count == 1,
              "held valid transaction must be accepted exactly once");
        check(barrier_fresh_accept_cycle > barrier_a_zero_cycle,
              "fresh acceptance must follow A outstanding drain");
        check(barrier_fresh_accept_cycle > barrier_b_zero_cycle,
              "fresh acceptance must follow B outstanding drain");
        if (barrier_stale_a_last_cycle >= 0)
            check(barrier_fresh_accept_cycle > barrier_stale_a_last_cycle,
                  "fresh acceptance must follow final stale A response");
        if (barrier_stale_b_last_cycle >= 0)
            check(barrier_fresh_accept_cycle > barrier_stale_b_last_cycle,
                  "fresh acceptance must follow final stale B response");
        check(barrier_ready_reopen_cycle >= barrier_a_zero_cycle,
              "ready reopen must not precede A outstanding drain");
        check(barrier_ready_reopen_cycle >= barrier_b_zero_cycle,
              "ready reopen must not precede B outstanding drain");
        wait_for_neighbor;
        check(first_a_req_cycle > barrier_a_zero_cycle &&
              first_b_req_cycle > barrier_b_zero_cycle,
              "fresh A/B requests must begin only after stale drain");
        check(monitor_a_req_count == 2 && monitor_b_req_count == 3,
              "fresh held-valid P16 must issue the expected A/B requests");
        check(amvp_neib_a[0] == A_WORD && amvp_neib_b[0] == B_WORD,
              "fresh post-drain external Neighbor data must be correct");
        $display("BARRIER TRACE: flush=%0d A_at_flush=%0d B_at_flush=%0d stale_A_last=%0d stale_B_last=%0d A_zero=%0d B_zero=%0d ready_reopen=%0d fresh_accept=%0d fresh_neib_start=%0d fresh_A_req=%0d fresh_B_req=%0d held_valid_drain_cycles=%0d",
                 barrier_flush_cycle, barrier_a_at_flush, barrier_b_at_flush,
                 barrier_stale_a_last_cycle, barrier_stale_b_last_cycle,
                 barrier_a_zero_cycle, barrier_b_zero_cycle,
                 barrier_ready_reopen_cycle, barrier_fresh_accept_cycle,
                 barrier_fresh_neib_start_cycle, first_a_req_cycle,
                 first_b_req_cycle, barrier_drain_cycles);
        retire_controller(32'h9999_aaaa, 4'd0);
        barrier_test_active = 1'b0;

        $display("CASE M: fresh P8/internal no-read immediately after a completed drain");
        // Construct the distinct local B/A entries through legal committed
        // P8 S0/S1/S2 transactions: S1 writes physical (3,2) to B[3], and
        // S2 writes physical (2,3) to A[3].  No testbench state is injected.
        start_transaction(1'b0, 1'b1, 2'd0, 3'd2, 3'd2,
                          2'b11, 3'b111, 7'd0);
        wait_for_neighbor;
        retire_controller(32'h0102_0304, 4'd0);
        start_transaction(1'b0, 1'b1, 2'd1, 3'd2, 3'd2,
                          2'b11, 3'b000, 7'd0);
        wait_for_neighbor;
        check(monitor_a_req_count == 0 && monitor_b_req_count == 0,
              "local B seed S1 must use no external A/B reads");
        retire_controller(FRESH_LOCAL_B[31:0], {2'b00, FRESH_LOCAL_B[33:32]});
        start_transaction(1'b0, 1'b1, 2'd2, 3'd2, 3'd2,
                          2'b00, 3'b000, 7'd0);
        wait_for_neighbor;
        check(monitor_a_req_count == 0 && monitor_b_req_count == 0,
              "local A seed S2 must use no external A/B reads");
        retire_controller(FRESH_LOCAL_A[31:0], {2'b00, FRESH_LOCAL_A[33:32]});

        response_delay_cycles = 5;
        response_word_a = OLD_STALE_A;
        response_word_b = OLD_STALE_B;
        barrier_test_active = 1'b0;
        barrier_flush_cycle = -1;
        barrier_a_at_flush = -1;
        barrier_b_at_flush = -1;
        barrier_a_zero_cycle = -1;
        barrier_b_zero_cycle = -1;
        barrier_ready_reopen_cycle = -1;
        barrier_fresh_accept_cycle = -1;
        barrier_fresh_neib_start_cycle = -1;
        barrier_stale_a_last_cycle = -1;
        barrier_stale_b_last_cycle = -1;
        start_transaction(1'b0, 1'b0, 2'd0, 3'd2, 3'd2, 2'b01, 3'b001, 7'd0);
        flush_pending_no_wait(1'b0);
        barrier_test_active = 1'b1;
        begin : drain_no_read_loop
            for (k = 0; k < 80; k = k + 1) begin
                @(negedge clk_vc);
                if (dut.neib_mem_quiescent)
                    disable drain_no_read_loop;
            end
        end
        check(dut.neib_mem_quiescent,
              "no-read case must launch only after stale responses drain");
        check(!irpu2ccu_rdy || dut.neib_mem_quiescent,
              "ready gating must remain coherent through no-read drain");
        response_delay_cycles = 0;
        response_word_a = A_WORD;
        response_word_b = B_WORD;
        a_count_before = a_req_count;
        b_count_before = b_req_count;
        start_transaction(1'b0, 1'b1, 2'd0, 3'd3, 3'd3, 2'b00, 3'b000, 7'd0);
        wait_for_neighbor;
        check(a_req_count == a_count_before && b_req_count == b_count_before,
              "post-drain P8/internal must issue zero A/B requests");
        check(amvp_neib_a[1] == FRESH_LOCAL_A &&
              amvp_neib_b[1] == FRESH_LOCAL_B,
              "post-drain P8/internal local Neighbor view must be correct");
        check(qualified_cycle >= launch_cycle,
              "post-drain no-read qualified completion must occur normally");
        $display("NO-READ TRACE: fresh_launch=%0d A_req_count=0 B_req_count=0 raw_high_at_launch=%0d raw_seen_low=%0d qualified_done=%0d local={A1:%h B1:%h}",
                 launch_cycle, monitor_raw_high_at_launch,
                 monitor_raw_seen_low, qualified_cycle,
                 amvp_neib_a[1], amvp_neib_b[1]);
        retire_controller(FRESH_LOCAL_A[31:0], {2'b00, FRESH_LOCAL_A[33:32]});
        barrier_test_active = 1'b0;

        check(col_req_count == 0, "no Col requests are legal in Decoder mode");
        check(ref_req_count == 0, "no RefList requests are legal in Decoder mode");
        check(update_sample_count == mc_commit_count,
              "every MC commit must correspond to exactly one sampled rolling update");
        $display("Request counts: A=%0d B=%0d Col=%0d RefList=%0d",
                 a_req_count, b_req_count, col_req_count, ref_req_count);
        $display("T06-B UPDATE COUNTS: mc_commit=%0d cur_cu_upd_sampled=%0d",
                 mc_commit_count, update_sample_count);
        $display("Stale response counts: A=%0d B=%0d",
                 stale_a_rd_lat_count, stale_b_rd_lat_count);

        if (errors == 0) begin
            $display("T01-B2.3.1 RESULT: PASS");
            $display("T06-B ROLLING UPDATE INTEGRATION RESULT: PASS");
        end else begin
            $display("T01-B2.3.1 RESULT: FAIL (%0d self-check failures)", errors);
            $display("T06-B ROLLING UPDATE INTEGRATION RESULT: FAIL");
            $fatal(1);
        end
        $finish;
    end

endmodule
