// AVC DEC: one-entry motion-transaction controller for the AVC decoder.
// It accepts parsed CCU syntax, holds the transaction context, sequences
// Neighbor/MVP/reconstruction handoffs, and retires on MC commit.
// It does not generate neighbors, calculate MVP/final MV values, hold the
// result for MC, or generate the Neighbor current-CU update.

module vc_mvp_dec_ctrl (
    input                   clk_vc,
    input                   vc_rst_z,
    input                   codec_mode,
    input                   reg_slice_go,

    input                   ccu2irpu_valid,
    output                  irpu2ccu_rdy,
    input      [1:0][15:0]  ccu2irpu_mvd,
    input      [3:0]        ccu2irpu_ref_idx,
    input                   ccu2irpu_is_skip,
    input                   ccu2irpu_part_mode,
    input      [1:0]        ccu2irpu_sub_idx,

    input      [2:0]        dec_txn_cux,
    input      [2:0]        dec_txn_cuy,
    input      [1:0]        dec_txn_a_avail,
    input      [2:0]        dec_txn_b_avail,

    input                   neib_done_amvp,
    input                   cand_capture_done,
    input                   recon_done,
    input                   mc_commit,

    output                  dec_neib_start,
    output                  dec_cand_start,
    output                  dec_recon_start,

    output     [1:0][15:0]  dec_mvd,
    output     [3:0]        dec_ref_idx,
    output                  dec_is_skip,
    output                  dec_part_mode,
    output     [1:0]        dec_sub_idx,
    output     [2:0]        dec_cux,
    output     [2:0]        dec_cuy,
    output     [1:0]        dec_a_avail,
    output     [2:0]        dec_b_avail,

    output     [1:0]        dec_expected_sub_idx,
    output                  dec_busy,
    output     [5:0]        dbg_dec_fsm_cs
);

    // AVC DEC: one-hot pipeline ownership; DEC_SEND holds the final-MV
    // transaction until the downstream MC/result-hold path commits it.
    localparam [5:0] DEC_IDLE     = 6'b000001;
    localparam [5:0] DEC_NEIB     = 6'b000010;
    localparam [5:0] DEC_MVP      = 6'b000100;
    localparam [5:0] DEC_RECON    = 6'b001000;
    localparam [5:0] DEC_SEND     = 6'b010000;

    // Registered transaction context: downstream stages use these fields,
    // never the raw CCU payload after the acceptance cycle.
    reg [5:0]       dec_fsm_cs;
    reg [5:0]       dec_fsm_ns;

    reg [1:0][15:0] dec_mvd_q;
    reg [3:0]        dec_ref_idx_q;
    reg              dec_is_skip_q;
    reg              dec_part_mode_q;
    reg [1:0]        dec_sub_idx_q;
    reg [2:0]        dec_cux_q;
    reg [2:0]        dec_cuy_q;
    reg [1:0]        dec_a_avail_q;
    reg [2:0]        dec_b_avail_q;
    reg [1:0]        dec_expected_sub_idx_q;

    // One-cycle handoff pulses: Neighbor -> candidate/MVP -> reconstruction.
    reg              dec_neib_start_q;
    reg              dec_cand_start_q;
    reg              dec_recon_start_q;

    wire             dec_accept;
    wire [1:0]       expected_sub_idx_next;

    // Admission is resource-only.  Ordering violations are simulation errors;
    // they must not suppress ready and create a protocol deadlock.
    assign irpu2ccu_rdy       = codec_mode && (dec_fsm_cs == DEC_IDLE);
    assign dec_accept         = ccu2irpu_valid && irpu2ccu_rdy;

    assign dec_neib_start     = dec_neib_start_q;
    assign dec_cand_start     = dec_cand_start_q;
    assign dec_recon_start    = dec_recon_start_q;

    assign dec_mvd            = dec_mvd_q;
    assign dec_ref_idx        = dec_ref_idx_q;
    assign dec_is_skip        = dec_is_skip_q;
    assign dec_part_mode      = dec_part_mode_q;
    assign dec_sub_idx        = dec_sub_idx_q;
    assign dec_cux            = dec_cux_q;
    assign dec_cuy            = dec_cuy_q;
    assign dec_a_avail        = dec_a_avail_q;
    assign dec_b_avail        = dec_b_avail_q;

    assign dec_expected_sub_idx = dec_expected_sub_idx_q;
    assign dec_busy              = (dec_fsm_cs != DEC_IDLE);
    assign dbg_dec_fsm_cs       = dec_fsm_cs;

    // P8 order is committed from the registered sub-index.  This tracker is
    // deliberately not part of ready generation (see admission above).
    assign expected_sub_idx_next =
        (dec_sub_idx_q == 2'd3) ? 2'd0 : (dec_sub_idx_q + 2'd1);

    // FSM handoffs: each completion advances one stage; final-MV delivery is
    // complete only when MC accepts the externally held result.
    always @(*) begin
        dec_fsm_ns = dec_fsm_cs;

        case (dec_fsm_cs)
            DEC_IDLE: begin
                // CCU syntax is latched before the Neighbor request pulse.
                if (dec_accept)
                    dec_fsm_ns = DEC_NEIB;
            end

            DEC_NEIB: begin
                // Neighbor has returned the spatial A/B/C view for MVP.
                if (neib_done_amvp)
                    dec_fsm_ns = DEC_MVP;
            end

            DEC_MVP: begin
                // Candidate/MVP stage has captured its predictor inputs.
                if (cand_capture_done)
                    dec_fsm_ns = DEC_RECON;
            end

            DEC_RECON: begin
                // Reconstruction has produced the final MV for the MC hold.
                if (recon_done)
                    dec_fsm_ns = DEC_SEND;
            end

            DEC_SEND: begin
                // mc_commit is the architectural transaction retirement point.
                if (mc_commit)
                    dec_fsm_ns = DEC_IDLE;
            end

            default: dec_fsm_ns = DEC_IDLE;
        endcase
    end

    always @(posedge clk_vc or negedge vc_rst_z) begin
        if (~vc_rst_z) begin
            dec_fsm_cs             <= DEC_IDLE;
            dec_mvd_q              <= 32'd0;
            dec_ref_idx_q          <= 4'd0;
            dec_is_skip_q          <= 1'b0;
            dec_part_mode_q        <= 1'b0;
            dec_sub_idx_q          <= 2'd0;
            dec_cux_q              <= 3'd0;
            dec_cuy_q              <= 3'd0;
            dec_a_avail_q          <= 2'd0;
            dec_b_avail_q          <= 3'd0;
            dec_expected_sub_idx_q <= 2'd0;
            dec_neib_start_q       <= 1'b0;
            dec_cand_start_q       <= 1'b0;
            dec_recon_start_q      <= 1'b0;
        end
        // Synchronous slice/mode flush drops pending work and all context.
        else if (reg_slice_go || !codec_mode) begin
            dec_fsm_cs             <= DEC_IDLE;
            dec_mvd_q              <= 32'd0;
            dec_ref_idx_q          <= 4'd0;
            dec_is_skip_q          <= 1'b0;
            dec_part_mode_q        <= 1'b0;
            dec_sub_idx_q          <= 2'd0;
            dec_cux_q              <= 3'd0;
            dec_cuy_q              <= 3'd0;
            dec_a_avail_q          <= 2'd0;
            dec_b_avail_q          <= 3'd0;
            dec_expected_sub_idx_q <= 2'd0;
            dec_neib_start_q       <= 1'b0;
            dec_cand_start_q       <= 1'b0;
            dec_recon_start_q      <= 1'b0;
        end
        else begin
            dec_fsm_cs        <= dec_fsm_ns;

            // Clear handoff pulses by default; each is asserted only for the
            // completion event that launches the next downstream stage.
            dec_neib_start_q  <= 1'b0;
            dec_cand_start_q  <= 1'b0;
            dec_recon_start_q <= 1'b0;

            // Capture the complete CCU transaction at the one accepted beat.
            if (dec_accept) begin
                dec_mvd_q       <= ccu2irpu_mvd;
                dec_ref_idx_q   <= ccu2irpu_ref_idx;
                dec_is_skip_q   <= ccu2irpu_is_skip;
                dec_part_mode_q <= ccu2irpu_part_mode;
                dec_sub_idx_q   <= ccu2irpu_sub_idx;
                dec_cux_q       <= dec_txn_cux;
                dec_cuy_q       <= dec_txn_cuy;
                // Availability is transaction context; hold it through all
                // downstream stages instead of rereading the raw CCU inputs.
                dec_a_avail_q   <= dec_txn_a_avail;
                dec_b_avail_q   <= dec_txn_b_avail;

                // Neighbor sees the registered context in this following cycle.
                dec_neib_start_q <= 1'b1;
            end
            else begin
                // These pulses mark the Neighbor -> MVP and MVP -> final-MV
                // reconstruction handoff points; arithmetic is external.
                if ((dec_fsm_cs == DEC_NEIB) && neib_done_amvp)
                    dec_cand_start_q <= 1'b1;

                if ((dec_fsm_cs == DEC_MVP) && cand_capture_done)
                    dec_recon_start_q <= 1'b1;

                // AVC DEC: advance P8 only after MC commit so the prior final
                // MV is visible to the next sub-block's rolling-neighbor lookup.
                // P16 and P_SKIP are complete macroblock transactions.
                if ((dec_fsm_cs == DEC_SEND) && mc_commit) begin
                    if (dec_part_mode_q)
                        dec_expected_sub_idx_q <= expected_sub_idx_next;
                    else
                        dec_expected_sub_idx_q <= 2'd0;
                end
            end
        end
    end

`ifndef SYNTHESIS
    // Portable simulation-only protocol checks.  Immediate checks are used
    // here so the block remains usable by Verilog simulators without SVA.
    reg dec_neib_start_d;
    reg dec_cand_start_d;
    reg dec_recon_start_d;

    always @(posedge clk_vc or negedge vc_rst_z) begin
        if (~vc_rst_z) begin
            dec_neib_start_d  <= 1'b0;
            dec_cand_start_d  <= 1'b0;
            dec_recon_start_d <= 1'b0;
        end
        else begin
            if (dec_neib_start && dec_neib_start_d)
                $error("vc_mvp_dec_ctrl: dec_neib_start is not a pulse");
            if (dec_cand_start && dec_cand_start_d)
                $error("vc_mvp_dec_ctrl: dec_cand_start is not a pulse");
            if (dec_recon_start && dec_recon_start_d)
                $error("vc_mvp_dec_ctrl: dec_recon_start is not a pulse");

            if (dec_accept && (dec_fsm_cs != DEC_IDLE))
                $error("vc_mvp_dec_ctrl: accepted transaction while busy");

            // Phase-1 has one legal L0 reference; width remains 4 bits for
            // structural compatibility and future extension.
            if (dec_accept && ccu2irpu_ref_idx != 4'd0)
                $error("vc_mvp_dec_ctrl: phase-1 Decoder requires ref_idx 0");

            if (dec_accept && ccu2irpu_part_mode &&
                (ccu2irpu_sub_idx != dec_expected_sub_idx_q))
                $error("vc_mvp_dec_ctrl: P8 sub_idx is out of order");

            if (dec_accept && !ccu2irpu_part_mode &&
                (ccu2irpu_sub_idx != 2'd0))
                $error("vc_mvp_dec_ctrl: P16 transaction must use sub_idx 0");

            if (dec_accept && ccu2irpu_is_skip &&
                (ccu2irpu_part_mode || (ccu2irpu_sub_idx != 2'd0)))
                $error("vc_mvp_dec_ctrl: P_SKIP must be P16/sub_idx 0");

            if (mc_commit && (dec_fsm_cs != DEC_SEND))
                $error("vc_mvp_dec_ctrl: mc_commit acted on outside DEC_SEND");

            dec_neib_start_d  <= dec_neib_start;
            dec_cand_start_d  <= dec_cand_start;
            dec_recon_start_d <= dec_recon_start;
        end
    end
`endif

endmodule
