// AVC Decoder Phase-1 spatial MVP capture wrapper.
//
// The selected 17-bit command is assembled by the Decoder integration from
// the frozen T01 adapter's selected block-size lane and 14-bit command.  This
// wrapper changes only A0 availability for the legacy candidate generator;
// all other availability bits and the A/B Neighbor MVs are preserved.
module vc_mvp_dec_cand (
    input                   clk_vc,
    input                   vc_rst_z,
    input                   reg_slice_go,
    input                   dec_cand_start,
    input      [16:0]       selected_cu_cmd,
    input      [2:0][33:0]  amvp_neib_b,
    input      [1:0][33:0]  amvp_neib_a,

    output reg [31:0]       dec_spatial_mvp,
    output reg              cand_capture_done,
    output                  cand_busy
);

    wire [16:0] candidate_cu_cmd;
    wire [2:0][33:0] candidate_neib_b;
    wire [1:0][33:0] candidate_neib_a;
    wire [0:0][32:0] decoder_reflist_info;
    wire [1:0][42:0] candidate_mv;
    wire [1:0] candidate_rdy;
    wire candidate_blk_done;
    wire candidate_blk_idle;
    wire candidate_start;

    // Preserve selected A1/B0/B1/B2 and all command metadata; suppress only
    // A0 because AVC candidate0's generic UA mux otherwise prefers A0.
    assign candidate_cu_cmd = {
        selected_cu_cmd[16:10], 1'b0, selected_cu_cmd[8:0]
    };

    // Phase-1 supports only ref_idx 0.  Keep each Neighbor MV bit-for-bit and
    // sanitize every legacy ref-index field before it can index reflist_info.
    genvar n;
    generate
        for (n = 0; n < 3; n = n + 1) begin : gen_sanitize_b_ref
            assign candidate_neib_b[n] = {2'b00, amvp_neib_b[n][31:0]};
        end
        for (n = 0; n < 2; n = n + 1) begin : gen_sanitize_a_ref
            assign candidate_neib_a[n] = {2'b00, amvp_neib_a[n][31:0]};
        end
    endgenerate

    assign decoder_reflist_info[0] = {1'b0, 32'd0};
    assign candidate_start = dec_cand_start && candidate_blk_idle &&
                             !reg_slice_go;
    assign cand_busy = !candidate_blk_idle;

    vc_mvp_cand_gen #(
        .NUM_REF      (1),
        .AMVP_OR_MRG  (1),
        .MVP_SCALE_EN (0)
    ) U_DEC_CAND_GEN (
        .cand_mv                  (candidate_mv),
        .cand_rdy                 (candidate_rdy),
        .cand_blk_done            (candidate_blk_done),
        .cand_blk_idle            (candidate_blk_idle),
        .dbg_fsm_cand_cs          (),
        .clk_vc                   (clk_vc),
        .vc_rst_z                 (vc_rst_z),
        .cand_cu_start            (candidate_start),
        .mrg_cand_nr_m1           (3'd0),
        .reg_slice_go             (reg_slice_go),
        .reg_tmp_mvp_flag         (1'b0),
        .reg_num_ref_l0_act_m1    (4'd0),
        .reg_cur_poc              (32'd0),
        .reg_avc_mode             (1'b1),
        .cu_cmd_out               (candidate_cu_cmd),
        .neib_b                   (candidate_neib_b),
        .neib_a                   (candidate_neib_a),
        .col_c                    ({2{42'd0}}),
        .col_c_avail              (2'b00),
        .reflist_info             (decoder_reflist_info),
        .cur_ref_idx              (2'b00),
        .col_ref_idx              (2'b00)
    );

    // Candidate data is combinational in IDLE/start.  Capture on that launch
    // edge; candidate_blk_done occurs in the following cycle and is not a data
    // valid indication.
    always @(posedge clk_vc or negedge vc_rst_z) begin
        if (!vc_rst_z) begin
            dec_spatial_mvp   <= 32'd0;
            cand_capture_done <= 1'b0;
        end
        else if (reg_slice_go) begin
            dec_spatial_mvp   <= 32'd0;
            cand_capture_done <= 1'b0;
        end
        else begin
            cand_capture_done <= 1'b0;
            if (dec_cand_start) begin
                if (!candidate_blk_idle) begin
`ifndef SYNTHESIS
                    $error("vc_mvp_dec_cand: start while candidate generator is busy");
`endif
                end
                else if (!candidate_rdy[0]) begin
`ifndef SYNTHESIS
                    $error("vc_mvp_dec_cand: candidate0 not ready on accepted start");
`endif
                end
                else if (candidate_rdy[1]) begin
`ifndef SYNTHESIS
                    $error("vc_mvp_dec_cand: candidate1 must remain disabled in AVC mode");
`endif
                end
                else begin
                    dec_spatial_mvp   <= candidate_mv[0][31:0];
                    cand_capture_done <= 1'b1;
                end
            end
        end
    end

endmodule
