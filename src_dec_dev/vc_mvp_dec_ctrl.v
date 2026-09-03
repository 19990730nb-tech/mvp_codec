// AVC decoder motion-transaction admission/scheduling controller.
//
// This is intentionally a standalone T00 block.  It owns one accepted
// transaction at a time and leaves neighbor generation, candidate arithmetic,
// reconstruction, and result packing to later integration work.

module vc_mvp_dec_ctrl (
    input                   clk_vc,
    input                   vc_rst_z,
    input                   codec_mode,

    input                   ccu2irpu_valid,
    output                  irpu2ccu_rdy,
    input      [1:0][15:0]  ccu2irpu_mvd,
    input      [3:0]        ccu2irpu_ref_idx,
    input                   ccu2irpu_is_skip,
    input                   ccu2irpu_part_mode,
    input      [1:0]        ccu2irpu_sub_idx,

    input      [2:0]        dec_txn_cux,
    input      [2:0]        dec_txn_cuy,

    input                   neib_done_amvp,
    input                   cand_capture_done,
    input                   recon_done,
    input                   result_accept,

    input                   cur_cu_upd,
    input      [1:0]        cur_cu_upd_sz,
    input      [2:0]        cur_cu_upd_x,
    input      [2:0]        cur_cu_upd_y,

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

    output     [1:0]        dec_expected_sub_idx,
    output                  dec_busy,
    output     [5:0]        dbg_dec_fsm_cs
);

    localparam [5:0] DEC_IDLE     = 6'b000001;
    localparam [5:0] DEC_NEIB     = 6'b000010;
    localparam [5:0] DEC_MVP      = 6'b000100;
    localparam [5:0] DEC_RECON    = 6'b001000;
    localparam [5:0] DEC_SEND     = 6'b010000;
    localparam [5:0] DEC_WAIT_UPD = 6'b100000;

    reg [5:0]       dec_fsm_cs;
    reg [5:0]       dec_fsm_ns;

    reg [1:0][15:0] dec_mvd_q;
    reg [3:0]        dec_ref_idx_q;
    reg              dec_is_skip_q;
    reg              dec_part_mode_q;
    reg [1:0]        dec_sub_idx_q;
    reg [2:0]        dec_cux_q;
    reg [2:0]        dec_cuy_q;
    reg [1:0]        dec_expected_sub_idx_q;

    reg              dec_neib_start_q;
    reg              dec_cand_start_q;
    reg              dec_recon_start_q;

    wire             dec_accept;
    wire [1:0]       expected_sub_idx_next;
    wire [1:0]       expected_commit_sz;
    wire             dec_commit;

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

    assign dec_expected_sub_idx = dec_expected_sub_idx_q;
    assign dec_busy              = (dec_fsm_cs != DEC_IDLE);
    assign dbg_dec_fsm_cs       = dec_fsm_cs;

    // The update size is determined from the latched syntax, never raw CCU
    // inputs.  P8x8 is blk8; P16x16 and skip use blk16 commits.
    assign expected_commit_sz = dec_part_mode_q ? 2'd1 : 2'd2;

    assign dec_commit = cur_cu_upd &&
                        (cur_cu_upd_sz == expected_commit_sz) &&
                        (cur_cu_upd_x  == dec_cux_q) &&
                        (cur_cu_upd_y  == dec_cuy_q);

    // The ordering tracker advances only after the matching update commit.
    // It is deliberately not part of ready generation.
    assign expected_sub_idx_next =
        (dec_sub_idx_q == 2'd3) ? 2'd0 : (dec_sub_idx_q + 2'd1);

    always @(*) begin
        dec_fsm_ns = dec_fsm_cs;

        case (dec_fsm_cs)
            DEC_IDLE: begin
                if (dec_accept)
                    dec_fsm_ns = DEC_NEIB;
            end

            DEC_NEIB: begin
                if (neib_done_amvp)
                    dec_fsm_ns = DEC_MVP;
            end

            DEC_MVP: begin
                if (cand_capture_done)
                    dec_fsm_ns = DEC_RECON;
            end

            DEC_RECON: begin
                if (recon_done)
                    dec_fsm_ns = DEC_SEND;
            end

            DEC_SEND: begin
                if (result_accept)
                    dec_fsm_ns = DEC_WAIT_UPD;
            end

            DEC_WAIT_UPD: begin
                if (dec_commit)
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
            dec_expected_sub_idx_q <= 2'd0;
            dec_neib_start_q       <= 1'b0;
            dec_cand_start_q       <= 1'b0;
            dec_recon_start_q      <= 1'b0;
        end
        else begin
            dec_fsm_cs        <= dec_fsm_ns;

            // Registered pulse outputs are cleared by default.  Each is set
            // only at the event that enters its associated processing state.
            dec_neib_start_q  <= 1'b0;
            dec_cand_start_q  <= 1'b0;
            dec_recon_start_q <= 1'b0;

            if (dec_accept) begin
                dec_mvd_q       <= ccu2irpu_mvd;
                dec_ref_idx_q   <= ccu2irpu_ref_idx;
                dec_is_skip_q   <= ccu2irpu_is_skip;
                dec_part_mode_q <= ccu2irpu_part_mode;
                dec_sub_idx_q   <= ccu2irpu_sub_idx;
                dec_cux_q       <= dec_txn_cux;
                dec_cuy_q       <= dec_txn_cuy;

                // This pulse is visible in the cycle after the handshake,
                // when all transaction fields are registered.
                dec_neib_start_q <= 1'b1;
            end
            else begin
                if ((dec_fsm_cs == DEC_NEIB) && neib_done_amvp)
                    dec_cand_start_q <= 1'b1;

                if ((dec_fsm_cs == DEC_MVP) && cand_capture_done)
                    dec_recon_start_q <= 1'b1;

                if ((dec_fsm_cs == DEC_WAIT_UPD) && dec_commit) begin
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

            if (dec_accept && ccu2irpu_part_mode &&
                (ccu2irpu_sub_idx != dec_expected_sub_idx_q))
                $error("vc_mvp_dec_ctrl: P8 sub_idx is out of order");

            if (dec_accept && !ccu2irpu_part_mode &&
                (ccu2irpu_sub_idx != 2'd0))
                $error("vc_mvp_dec_ctrl: P16 transaction must use sub_idx 0");

            if (dec_accept && ccu2irpu_is_skip &&
                (ccu2irpu_part_mode || (ccu2irpu_sub_idx != 2'd0)))
                $error("vc_mvp_dec_ctrl: P_SKIP must be P16/sub_idx 0");

            if (dec_commit && (dec_fsm_cs != DEC_WAIT_UPD))
                $error("vc_mvp_dec_ctrl: dec_commit acted on outside DEC_WAIT_UPD");

            dec_neib_start_d  <= dec_neib_start;
            dec_cand_start_d  <= dec_cand_start;
            dec_recon_start_d <= dec_recon_start;
        end
    end
`endif

endmodule
