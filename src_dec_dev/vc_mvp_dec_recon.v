module vc_mvp_dec_recon (
    input                   clk_vc,
    input                   vc_rst_z,
    input                   codec_mode,
    input                   reg_slice_go,
    input                   dec_recon_start,
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
                dec_final_mv      <= {sum_y_17[15:0], sum_x_17[15:0]};
                dec_final_ref_idx <= dec_ref_idx;
                recon_done        <= 1'b1;
`ifndef SYNTHESIS
                if (sum_x_17[16] != sum_x_17[15])
                    $error("vc_mvp_dec_recon: X sum overflows signed 16-bit range");
                if (sum_y_17[16] != sum_y_17[15])
                    $error("vc_mvp_dec_recon: Y sum overflows signed 16-bit range");
`endif
            end
        end
    end

endmodule
