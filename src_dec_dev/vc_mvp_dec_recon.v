module vc_mvp_dec_recon (
    input                   clk_vc,
    input                   vc_rst_z,
    input                   codec_mode,
    input                   reg_slice_go,
    input                   dec_recon_start,
    input                   dec_is_skip,
    input                   dec_is_pic_top16,
    input                   dec_is_pic_left16,
    input                   dec_skip_a1_avail,
    input                   dec_skip_b1_avail,
    input      [31:0]       dec_skip_a1_mv,
    input      [31:0]       dec_skip_b1_mv,
    input      [31:0]       dec_spatial_mvp,
    input      [1:0][15:0]  dec_mvd,
    input      [3:0]        dec_ref_idx,

    output reg [31:0]       dec_final_mv,
    output reg [3:0]        dec_final_ref_idx,
    output reg              recon_done
);

    // Packed component order is {Y, X}; extend explicitly before addition.
    wire signed [16:0] mvp_x_17 =
        $signed({dec_spatial_mvp[15], dec_spatial_mvp[15:0]});
    wire signed [16:0] mvp_y_17 =
        $signed({dec_spatial_mvp[31], dec_spatial_mvp[31:16]});
    wire signed [16:0] mvd_x_17 = $signed({dec_mvd[0][15], dec_mvd[0]});
    wire signed [16:0] mvd_y_17 = $signed({dec_mvd[1][15], dec_mvd[1]});

    wire signed [16:0] sum_x_17 = mvp_x_17 + mvd_x_17;
    wire signed [16:0] sum_y_17 = mvp_y_17 + mvd_y_17;

    wire skip_zero_motion =
        dec_is_pic_top16 ||
        dec_is_pic_left16 ||
        (dec_skip_b1_avail && (dec_skip_b1_mv == 32'd0)) ||
        (dec_skip_a1_avail && (dec_skip_a1_mv == 32'd0));

    // At decoder-top integration, derive the picture-boundary flags from
    // accepted, latched transaction coordinates, matching ve_mvp_top.v:
    // dec_is_pic_top16  = ({dec_ctuy_q, dec_cuy[2:1]} == 0);
    // dec_is_pic_left16 = ({dec_ctux_q, dec_cux}      == 0);
    // Capture dec_ctux_q and future dec_ctuy_q on dec_accept; dec_cux and
    // dec_cuy are the controller's registered transaction coordinates.
    // Never derive these flags from live upstream coordinates. Neighbor
    // bindings are A1=dec_a_avail[1]/amvp_neib_a[1][31:0] and
    // B1=dec_b_avail[1]/amvp_neib_b[1][31:0].

    always @(posedge clk_vc or negedge vc_rst_z) begin
        if (!vc_rst_z) begin
            dec_final_mv       <= 32'd0;
            dec_final_ref_idx  <= 4'd0;
            recon_done         <= 1'b0;
        end
        else if (reg_slice_go || !codec_mode) begin
            dec_final_mv       <= 32'd0;
            dec_final_ref_idx  <= 4'd0;
            recon_done         <= 1'b0;
        end
        else begin
            recon_done <= 1'b0;
            if (dec_recon_start) begin
                if (dec_is_skip) begin
                    dec_final_mv <= skip_zero_motion ? 32'd0 : dec_spatial_mvp;
                    dec_final_ref_idx <= 4'd0;
                end
                else begin
                    dec_final_mv      <= {sum_y_17[15:0], sum_x_17[15:0]};
                    dec_final_ref_idx <= dec_ref_idx;
                end
                recon_done        <= 1'b1;
`ifndef SYNTHESIS
                if (!dec_is_skip) begin
                    if (sum_x_17[16] != sum_x_17[15])
                        $error("vc_mvp_dec_recon: X sum overflows signed 16-bit range");
                    if (sum_y_17[16] != sum_y_17[15])
                        $error("vc_mvp_dec_recon: Y sum overflows signed 16-bit range");
                end
`endif
            end
        end
    end

endmodule
