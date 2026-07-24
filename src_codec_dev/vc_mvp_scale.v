// -----------------------------------------------------------------------------
// Temporal motion-vector scaler used for candidates whose reference-picture
// distance differs from the current block.  POC differences are signed 8-bit
// values; the scaled X/Y results are rounded and saturated to signed 16 bits.
// The caller must not start scaling with n_col_poc_diff equal to zero.
// -----------------------------------------------------------------------------
module vc_mvp_scale
#(
    parameter MULCYC = 3'd4
)
(
    // Output
    output reg                     scale_done,
    output reg signed    [15:0]    scale_mvx,
    output reg signed    [15:0]    scale_mvy,
    // Input
    input                          clk_vc,
    input                          vc_rst_z,
    input                          reg_slice_go,
    input                          scale_start,
    input               [15:0]    n_mvx,
    input               [15:0]    n_mvy,
    //input  unsigned    [31:0]    reg_cur_poc,   // current pic poc
    //input  unsigned    [31:0]    cur_ref_poc,   // current ref pic poc
    input               [ 7:0]    n_cur_poc_diff,
    input               [ 7:0]    n_col_poc_diff // collocated / neib poc diff
);

// local parameter

localparam MULCYC_IDLE = 0,
           MULCYC_ACT  = 1;

// Registers Declaration

reg              [ 1:0]      fsm_mulcyc_cs;
reg              [ 2:0]      mul_cyc_cnt;
reg      signed  [15:0]      mvx;
reg      signed  [15:0]      mvy;
reg      signed  [ 7:0]      cur_poc_diff;
reg      signed  [ 7:0]      col_poc_diff;

// Wire Declaration

reg              [ 1:0]      fsm_mulcyc_ns;
wire    signed   [ 7:0]      td;
wire    signed   [ 7:0]      tb;
wire    signed   [ 7:0]      td_abs;
wire    signed   [15:0]      tx; // unsigned 15+1
wire    signed   [22:0]      tb_mul_tx; // sign 16 * sign 8 => (16-1) + (8-1) + 1
wire    signed   [22:0]      tb_mul_tx_add32;
wire    signed   [16:0]      dist_scale_factor_bef_clip;
reg     signed   [12:0]      dist_scale_factor;
wire    signed   [28:0]      scale_mul_mvx; // scale = 13bit, mv = 16bit, (13-1)+(16-1)+1=28bit
wire    signed   [28:0]      scale_mul_mvy; // scale = 13bit, mv = 16bit, (13-1)+(16-1)+1=28bit
wire    unsigned [28:0]      scale_mul_mvx_abs;
wire    unsigned [28:0]      scale_mul_mvy_abs;
wire    unsigned [28:0]      scale_mul_mvx_abs_add127;
wire    unsigned [28:0]      scale_mul_mvy_abs_add127;
wire    unsigned [20:0]      scale_mvx_wo_sign;
wire    unsigned [20:0]      scale_mvy_wo_sign;
wire    signed   [20:0]      scale_mvx_bef_clip;
wire    signed   [20:0]      scale_mvy_bef_clip;
reg              [15:0]      n_scale_mvx;
reg              [15:0]      n_scale_mvy;
wire                         scale_sign_x;
wire                         scale_sign_y;

wire                         mul_cyc_cnt_done;
wire             [15:0]      td_add;

// Combinational Logic

    // HEVC temporal scaling notation:
    //   td = colocated-picture distance, tb = current-reference distance.
    // tx approximates 2^14 / td; the following multiply and >>6 produce the
    // signed Q8 distance scale factor used for both MV components.
    assign mul_cyc_cnt_done = (mul_cyc_cnt == MULCYC );
    assign td = col_poc_diff;
    assign tb = cur_poc_diff;
    assign td_abs = td[7] ? -(td) : td;
    assign td_add = 16'd16384 + td_abs[6:1];
    //============= division =============
    assign tx = $signed(td_add) / $signed(td);
    //assign tx = ( $signed(16'd16384) + $signed(td_abs[6:1]) ) / td;

    //============= multiply =============
    assign tb_mul_tx = tb * tx;

    assign tb_mul_tx_add32 = tb_mul_tx + 32;
    assign dist_scale_factor_bef_clip = tb_mul_tx_add32[22:6];

    // Clip the scale factor before multiplying the 16-bit motion vector.
    // Keeping 13 signed bits represents the normative range -4096..4095.
    always@( * ) begin
        if( dist_scale_factor_bef_clip[16] & ~dist_scale_factor_bef_clip[15:12] )
            dist_scale_factor = 13'b1_0000_0000_0000;
        else if( !dist_scale_factor_bef_clip[16] & |dist_scale_factor_bef_clip[15:12] )
            dist_scale_factor = 13'b0_1111_1111_1111;
        else
            dist_scale_factor = dist_scale_factor_bef_clip[12:0];
    end

    //============== multiply =============
    assign scale_mul_mvx = dist_scale_factor * mvx;
    assign scale_mul_mvy = dist_scale_factor * mvy;
    assign scale_sign_x = dist_scale_factor[12] ^ mvx[15];
    assign scale_sign_y = dist_scale_factor[12] ^ mvy[15];

    // Normative rounding is sign-independent: round the absolute product by
    // adding 127, shift right by 8, and restore the product sign afterwards.
    // This avoids implementation-defined behavior of arithmetic shifts on a
    // negative value.
    // abs
    assign scale_mul_mvx_abs[28:0] = scale_mul_mvx[28] ? -(scale_mul_mvx) : scale_mul_mvx;
    assign scale_mul_mvy_abs[28:0] = scale_mul_mvy[28] ? -(scale_mul_mvy) : scale_mul_mvy;
    // abs+127
    assign scale_mul_mvx_abs_add127[28:0] = scale_mul_mvx_abs[28:0] + 127;
    assign scale_mul_mvy_abs_add127[28:0] = scale_mul_mvy_abs[28:0] + 127;
    // (abs+127) >> 8
    assign scale_mvx_wo_sign[20:0] = scale_mul_mvx_abs_add127[28:8];
    assign scale_mvy_wo_sign[20:0] = scale_mul_mvy_abs_add127[28:8];
    // add sign
    assign scale_mvx_bef_clip[20:0] = scale_sign_x ? (-scale_mvx_wo_sign[20:0]) : scale_mvx_wo_sign[20:0];
    assign scale_mvy_bef_clip[20:0] = scale_sign_y ? (-scale_mvy_wo_sign[20:0]) : scale_mvy_wo_sign[20:0];

    // n_mvx => clip -32768~32767
    always@( * ) begin
        if( scale_mvx_bef_clip[20] & ~&scale_mvx_bef_clip[19:15] )
            n_scale_mvx = 16'b1000_0000_0000_0000;
        else if( !scale_mvx_bef_clip[20] & |scale_mvx_bef_clip[19:15] )
            n_scale_mvx = 16'b0111_1111_1111_1111;
        else
            n_scale_mvx = scale_mvx_bef_clip[15:0];
    end

    // n_mvy => clip -32768~32767
    always@( * ) begin
        if( scale_mvy_bef_clip[20] & ~&scale_mvy_bef_clip[19:15] )
            n_scale_mvy = 16'b1000_0000_0000_0000;
        else if( !scale_mvy_bef_clip[20] & |scale_mvy_bef_clip[19:15] )
            n_scale_mvy = 16'b0111_1111_1111_1111;
        else
            n_scale_mvy = scale_mvy_bef_clip[15:0];
    end

// function/task 



// instantiation



// state machine 

    // Arithmetic is combinational; this FSM supplies the configured interface
    // latency.  Inputs are captured on scale_start and outputs become valid
    // exactly when the MULCYC counter expires.
    always@(*) begin : fsm_mulcyc
        fsm_mulcyc_ns = 0;
        case(1) //synopsys parallel_case
            fsm_mulcyc_cs[MULCYC_IDLE]: begin
                if(scale_start)
                    fsm_mulcyc_ns[MULCYC_ACT] = 1'b1;
                else
                    fsm_mulcyc_ns[MULCYC_IDLE]= 1'b1;
            end
            fsm_mulcyc_cs[MULCYC_ACT]: begin
                if(mul_cyc_cnt_done)
                    fsm_mulcyc_ns[MULCYC_IDLE] = 1'b1;
                else
                    fsm_mulcyc_ns[MULCYC_ACT] = 1'b1;
            end
        endcase
    end

    // sequence logic

    always@( posedge clk_vc or negedge vc_rst_z ) begin
        if(~vc_rst_z)begin
            fsm_mulcyc_cs <= 1;
        end
        else if( reg_slice_go ) begin
            fsm_mulcyc_cs <= 1;
        end
        else if( fsm_mulcyc_cs != fsm_mulcyc_ns )begin
            fsm_mulcyc_cs <= fsm_mulcyc_ns;
        end
    end

    always@( posedge clk_vc or negedge vc_rst_z ) begin
        if(~vc_rst_z)begin
            mul_cyc_cnt <= 0;
        end
        else if( reg_slice_go ) begin
            mul_cyc_cnt <= 0;
        end
        else begin
            if( mul_cyc_cnt_done )
                mul_cyc_cnt <= 0;
            else if( fsm_mulcyc_cs[MULCYC_ACT] | scale_start )
                mul_cyc_cnt <= mul_cyc_cnt + 1'b1;
        end
    end

    always@( posedge clk_vc or negedge vc_rst_z ) begin
        if(~vc_rst_z)begin
            scale_done <= 0;
        end
        else if( scale_done | reg_slice_go ) begin
            scale_done <= 0;
        end
        else if( mul_cyc_cnt_done )begin
            scale_done <= 1;
        end
    end

    always@( posedge clk_vc ) begin
        if( mul_cyc_cnt_done ) begin
            scale_mvx <= n_scale_mvx;
            scale_mvy <= n_scale_mvy;
        end
    end

    always@( posedge clk_vc ) begin
        if( scale_start ) begin
            mvx             <= n_mvx;
            mvy             <= n_mvy;
            col_poc_diff    <= n_col_poc_diff;
            cur_poc_diff    <= n_cur_poc_diff;
        end
    end

endmodule

//  td = Clip3( −128, 127, DiffPicOrderCnt( currPic, refPicListA[ refIdxA ] ) )  (8-152)
//  tb = Clip3( −128, 127, DiffPicOrderCnt( currPic, RefPicListX[ refIdxLX ] ) ) (8-153)
//  tx=(16384+(Abs(td) >> 1))/td		(8-149)
//  distScaleFactor = Clip3( −4096, 4095, ( tb * tx + 32 ) >> 6 )	(8-150)
//  mvLXA = Clip3( −32768, 32767, Sign( distScaleFactor * mvLXA ) * ( ( Abs( distScaleFactor * mvLXA ) + 127 ) >> 8 ) )	(8-151)
