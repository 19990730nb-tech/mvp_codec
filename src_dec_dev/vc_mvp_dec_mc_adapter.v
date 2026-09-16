module vc_mvp_dec_mc_adapter #(
    parameter VC_CTU_X_NB = 7,
    parameter VC_CTU_Y_NB = 7,
    parameter VC_PIC_X_NB = 12,
    parameter VC_PIC_Y_NB = 12,
    parameter MRG2MC_DW = VC_PIC_X_NB + VC_PIC_Y_NB + 39
) (
    input                           clk_vc,
    input                           vc_rst_z,
    input                           codec_mode,
    input                           reg_slice_go,
    input                           dec_send,
    input      [31:0]               dec_final_mv,
    input      [3:0]                dec_final_ref_idx,
    input                           dec_part_mode,
    input                           dec_is_skip,
    input      [1:0]                dec_sub_idx,
    input      [2:0]                dec_cux,
    input      [2:0]                dec_cuy,
    input      [VC_CTU_X_NB-1:0]    dec_ctux,
    input      [VC_CTU_Y_NB-1:0]    dec_ctuy,
    input      [2:0]                mc2mrg_cand_ack,

    output reg [2:0]                dec_mrg2mc_cand_rdy,
    output reg [2:0][MRG2MC_DW-1:0] dec_mrg2mc_cand_data,
    output     [2:0]                dec_mrg2mc_cand_nb,
    output     [2:0]                dec_mrg2mc_cand_done,
    output                           mc_commit
);

    localparam CTU_X_PIC_W = (VC_PIC_X_NB > 6) ? VC_PIC_X_NB - 6 : 1;
    localparam CTU_Y_PIC_W = (VC_PIC_Y_NB > 6) ? VC_PIC_Y_NB - 6 : 1;

    wire active = vc_rst_z && codec_mode && !reg_slice_go && dec_send;
    wire [3:0] p8_cux_ext = {1'b0, dec_cux} + {3'b000, dec_sub_idx[0]};
    wire [3:0] p8_cuy_ext = {1'b0, dec_cuy} + {3'b000, dec_sub_idx[1]};

    reg [2:0] physical_cux;
    reg [2:0] physical_cuy;
    reg [1:0] size_code;
    always @* begin
        if (dec_part_mode) begin
            physical_cux = p8_cux_ext[2:0];
            physical_cuy = p8_cuy_ext[2:0];
            size_code = 2'd1;
        end else begin
            physical_cux = {dec_cux[2:1], 1'b0};
            physical_cuy = {dec_cuy[2:1], 1'b0};
            size_code = 2'd2;
        end
    end

    wire [VC_PIC_X_NB-1:0] pic_x;
    wire [VC_PIC_Y_NB-1:0] pic_y;
    generate
        if ((VC_PIC_X_NB >= 7) && (VC_CTU_X_NB >= VC_PIC_X_NB - 6)) begin : gen_pic_x
            assign pic_x = {dec_ctux[0 +: CTU_X_PIC_W], physical_cux, 3'b000};
        end else begin : gen_bad_pic_x_params
            assign pic_x = {VC_PIC_X_NB{1'b0}};
        end
        if ((VC_PIC_Y_NB >= 7) && (VC_CTU_Y_NB >= VC_PIC_Y_NB - 6)) begin : gen_pic_y
            assign pic_y = {dec_ctuy[0 +: CTU_Y_PIC_W], physical_cuy, 3'b000};
        end else begin : gen_bad_pic_y_params
            assign pic_y = {VC_PIC_Y_NB{1'b0}};
        end
    endgenerate

    wire [MRG2MC_DW-1:0] packet = {
        1'b1,
        pic_y,
        pic_x,
        size_code,
        size_code,
        dec_final_ref_idx[1:0],
        dec_final_mv
    };
    wire [2:0] selected_lane = dec_part_mode ? 3'b001 : 3'b010;
    wire [2:0] handshake = dec_mrg2mc_cand_rdy & mc2mrg_cand_ack;
    reg [2:0] done_q;

    assign dec_mrg2mc_cand_nb = 3'b000;
    assign dec_mrg2mc_cand_done = done_q & {3{vc_rst_z && codec_mode && !reg_slice_go}};
    assign mc_commit = |handshake;

    always @* begin
        dec_mrg2mc_cand_rdy = 3'b000;
        dec_mrg2mc_cand_data = '0;
        if (active) begin
            dec_mrg2mc_cand_rdy = selected_lane;
            if (dec_part_mode)
                dec_mrg2mc_cand_data[0] = packet;
            else
                dec_mrg2mc_cand_data[1] = packet;
        end
    end

    always @(posedge clk_vc or negedge vc_rst_z) begin
        if (!vc_rst_z)
            done_q <= 3'b000;
        else if (reg_slice_go || !codec_mode)
            done_q <= 3'b000;
        else
            done_q <= handshake;
    end

`ifndef SYNTHESIS
    initial begin
        if (VC_PIC_X_NB < 7 || VC_PIC_Y_NB < 7)
            $error("vc_mvp_dec_mc_adapter: picture coordinate widths must be at least 7");
        if (VC_CTU_X_NB < CTU_X_PIC_W || VC_CTU_Y_NB < CTU_Y_PIC_W)
            $error("vc_mvp_dec_mc_adapter: CTU coordinate width is smaller than picture coordinate slice");
        if (MRG2MC_DW != VC_PIC_X_NB + VC_PIC_Y_NB + 39)
            $error("vc_mvp_dec_mc_adapter: MRG2MC_DW must equal PIC_X + PIC_Y + 39");
    end

    always @(posedge clk_vc) begin
        if (active) begin
            if (dec_final_ref_idx[3:2] != 2'b00)
                $error("vc_mvp_dec_mc_adapter: active reference index must fit ref_idx[1:0]");
            if (dec_part_mode) begin
                if (p8_cux_ext[3])
                    $error("vc_mvp_dec_mc_adapter: P8 X sub-block coordinate overflows 3 bits");
                if (p8_cuy_ext[3])
                    $error("vc_mvp_dec_mc_adapter: P8 Y sub-block coordinate overflows 3 bits");
            end else begin
                if (dec_sub_idx != 2'b00)
                    $error("vc_mvp_dec_mc_adapter: P16/P_SKIP requires zero sub-index");
                if (dec_cux[0] || dec_cuy[0])
                    $error("vc_mvp_dec_mc_adapter: P16/P_SKIP base coordinates must be aligned");
            end
            if (dec_is_skip && dec_part_mode)
                $error("vc_mvp_dec_mc_adapter: P_SKIP cannot use P8 partition mode");
        end
    end
`endif

endmodule
