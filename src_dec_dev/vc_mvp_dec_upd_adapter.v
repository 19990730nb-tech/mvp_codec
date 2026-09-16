module vc_mvp_dec_upd_adapter (
    input             clk_vc,
    input             vc_rst_z,
    input             codec_mode,
    input             reg_slice_go,

    input             mc_commit,

    input             dec_part_mode,
    input             dec_is_skip,
    input      [1:0]  dec_sub_idx,
    input      [2:0]  dec_cux,
    input      [2:0]  dec_cuy,

    input      [31:0] dec_final_mv,
    input      [3:0]  dec_final_ref_idx,

    output            cur_cu_upd,
    output reg [1:0]  cur_cu_upd_sz,
    output reg [2:0]  cur_cu_upd_x,
    output reg [2:0]  cur_cu_upd_y,
    output reg [15:0] cur_cu_upd_mvx,
    output reg [15:0] cur_cu_upd_mvy,
    output reg [1:0]  cur_cu_upd_refidx
);

    wire active_update = vc_rst_z && codec_mode && !reg_slice_go && mc_commit;
    wire [3:0] p8_cux_ext = {1'b0, dec_cux} + {3'b000, dec_sub_idx[0]};
    wire [3:0] p8_cuy_ext = {1'b0, dec_cuy} + {3'b000, dec_sub_idx[1]};

    assign cur_cu_upd = active_update;

    always @* begin
        cur_cu_upd_sz     = 2'd0;
        cur_cu_upd_x      = 3'd0;
        cur_cu_upd_y      = 3'd0;
        cur_cu_upd_mvx    = 16'd0;
        cur_cu_upd_mvy    = 16'd0;
        cur_cu_upd_refidx = 2'd0;

        if (active_update) begin
            if (dec_part_mode) begin
                cur_cu_upd_sz = 2'd1;
                cur_cu_upd_x  = p8_cux_ext[2:0];
                cur_cu_upd_y  = p8_cuy_ext[2:0];
            end else begin
                cur_cu_upd_sz = 2'd2;
                cur_cu_upd_x  = {dec_cux[2:1], 1'b0};
                cur_cu_upd_y  = {dec_cuy[2:1], 1'b0};
            end

            cur_cu_upd_mvx    = dec_final_mv[15:0];
            cur_cu_upd_mvy    = dec_final_mv[31:16];
            cur_cu_upd_refidx = dec_final_ref_idx[1:0];
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk_vc) begin
        if (active_update) begin
            if (dec_part_mode) begin
                if (p8_cux_ext[3])
                    $error("vc_mvp_dec_upd_adapter: P8 X coordinate overflows 3 bits");
                if (p8_cuy_ext[3])
                    $error("vc_mvp_dec_upd_adapter: P8 Y coordinate overflows 3 bits");
            end else begin
                if (dec_sub_idx != 2'b00)
                    $error("vc_mvp_dec_upd_adapter: P16/P_SKIP requires zero sub-index");
                if (dec_cux[0] || dec_cuy[0])
                    $error("vc_mvp_dec_upd_adapter: P16/P_SKIP base coordinates must be aligned");
            end
            if (dec_is_skip && dec_part_mode)
                $error("vc_mvp_dec_upd_adapter: P_SKIP cannot use P8 partition mode");
            if (dec_final_ref_idx[3:2] != 2'b00)
                $error("vc_mvp_dec_upd_adapter: active reference index must fit ref_idx[1:0]");
        end
    end
`endif

endmodule
