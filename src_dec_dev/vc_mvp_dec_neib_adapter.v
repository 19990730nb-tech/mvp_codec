// AVC DEC: adapt one registered Decoder transaction to the legacy AMVP
// Neighbor command/lane interface.  It packs coordinates, availability, and
// mode metadata; it does not calculate MVP/MED/final MV or own transaction
// sequencing, rolling-neighbor state, RefList traversal, or MC.

module vc_mvp_dec_neib_adapter (
    input                   clk_vc,
    input                   codec_mode,
    input                   dec_neib_start,

    input                   dec_part_mode,
    input                   dec_is_skip,
    input      [1:0]        dec_sub_idx,
    input      [2:0]        dec_cux,
    input      [2:0]        dec_cuy,
    input      [1:0]        dec_a_avail,
    input      [2:0]        dec_b_avail,

    output                  amvp_cu_start,
    output     [2:0][13:0]  amvp_cmd_out,
    output     [1:0][2:0]   cmdq_empty_n,
    output     [2:0]        amvp_blk_sz,
    output     [2:0]        n_blk_sz_amvp,
    output                  blk_sz_lat_amvp
);

    reg [2:0]       cmd_cux;
    reg [2:0]       cmd_cuy;
    reg [13:0]      cmd;
    reg [2:0]       blk_onehot;
    reg [2:0][13:0] amvp_cmd_out_q;
    reg [1:0][2:0]  cmdq_empty_n_q;

    wire [3:0]      p8_cux_ext;
    wire [3:0]      p8_cuy_ext;
    wire            invalid_p8_coord;

    assign p8_cux_ext = {1'b0, dec_cux} + {3'b000, dec_sub_idx[0]};
    assign p8_cuy_ext = {1'b0, dec_cuy} + {3'b000, dec_sub_idx[1]};

    // P8 coordinates are base 8x8 slots plus the sub-block bits; P16 and
    // P_SKIP retain the accepted base coordinate.
    assign invalid_p8_coord = codec_mode && dec_neib_start && dec_part_mode &&
                              (p8_cux_ext[3] || p8_cuy_ext[3]);

    always @(*) begin
        cmd_cux = dec_cux;
        cmd_cuy = dec_cuy;
        blk_onehot = 3'b010;

        if (dec_part_mode) begin
            cmd_cux = p8_cux_ext[2:0];
            cmd_cuy = p8_cuy_ext[2:0];
            blk_onehot = 3'b001;
        end

        // Decoder owns the resolved A/B availability; this block only packs it.
        cmd = {1'b0, dec_is_skip, 1'b0, dec_a_avail, dec_b_avail,
               cmd_cuy, cmd_cux};

        amvp_cmd_out_q = 42'd0;
        cmdq_empty_n_q = 6'd0;

        if (codec_mode) begin
            amvp_cmd_out_q[0] = cmd;
            if (!dec_part_mode)
                // vc_mvp_get_neib reads coordinates from lane 0 while its
                // AVC blk16 availability path separately reads lane 1.
                amvp_cmd_out_q[1] = cmd;

            // Only the selected block-size lane is active; lane 0 duplication
            // for P16/P_SKIP is a context mirror, not a second transaction.
            cmdq_empty_n_q[1] = blk_onehot;
        end
    end

    assign amvp_cu_start   = codec_mode && dec_neib_start;
    // The legacy Neighbor block captures selected A/B views on this size pulse.
    assign blk_sz_lat_amvp = codec_mode && dec_neib_start;
    assign amvp_cmd_out    = amvp_cmd_out_q;
    assign cmdq_empty_n    = cmdq_empty_n_q;
    assign amvp_blk_sz     = codec_mode ? blk_onehot : 3'b000;
    assign n_blk_sz_amvp   = codec_mode ? blk_onehot : 3'b000;

`ifndef SYNTHESIS
    // A 3-bit legacy coordinate must not silently wrap when selecting S1/S2/S3.
    integer p8_coord_error_count;

    initial p8_coord_error_count = 0;

    always @(posedge clk_vc) begin
        if (invalid_p8_coord) begin
            p8_coord_error_count = p8_coord_error_count + 1;
            $error("vc_mvp_dec_neib_adapter: P8 coordinate overflows 3-bit slot space");
        end
    end
`endif

    // T01-B2 integration policy: use AVC mode with temporal MVP disabled and
    // drive vc_mvp_get_neib.cur_ctu_start low so U_GET_REFLIST stays idle.
    // Phase-1 has one legal L0 reference (ref_idx 0), so no RefList traversal
    // is part of the Decoder Neighbor path.

endmodule
