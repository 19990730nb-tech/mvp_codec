`include "ve_defines.v"
module	ve_amvp_top
#(
    parameter	NUM_REF = 2,
	parameter	MUL_REF = (NUM_REF > 1),
	parameter	MVP_SCALE_EN = 0,
    parameter	MAX_BLK_SZ = 2, // 3:blk32, 2:blk16
	parameter	VC_EN_BI_DIR = 0,  // 0: ref0 only, 1: bi direction
	parameter	VC_SATD_NB = 20,
    parameter	VC_SSE_NB = 40,
	parameter	AMVP2CCU_DW	= (8+78),
	//parameter	AMVP2CCU_DW	= (78+VC_SATD_NB+VC_SSE_NB),
    parameter	CAND_NUM = NUM_REF * 2,
	parameter	FME_BLK8_CMDQ_DEPTH  = 8,
	parameter	FME_BLK16_CMDQ_DEPTH  = 2,
    parameter	FSMW = 5
//	parameter	FME_CMDQ_DEPTH = FME_BLK8_CMDQ_DEPTH + FME_BLK16_CMDQ_DEPTH
)
(
// output
output	[2:0]					cu_blk_en,
output	[2:0][13:0]				cu_cmd_out,
output	[2:0]				    cmdq_empty_n,
output							neib_cu_start,
// FME
output	reg[ 1:0]				amvp2fme_cand_ack,
// CCU
output [ 2:0]					irpu_amvp_rdy,
output [2:0][AMVP2CCU_DW-1:0]	irpu_amvp_rd,
output reg [ 1:0]				irpu_amvp_dlat,
output reg [1:0][33:0]			irpu_amvp_mv_info,
// dbg
output	[6:0]					dbg_fsm_mvp_cs,
output	[FSMW-1:0]				dbg_fsm_cand_cs,
// AVC
output                          avc_mvp_push,
output  [1:0]                   avc_ref_idx,
output                          avc_is_long,
output  [7:0]                   avc_pocdiff,
output  [1:0][15:0]             avc_mvpxy,
output  [1:0][3:0]              avc_mvd_gt4,
// lat
output                          blk_sz_lat,
output  [2:0]                   n_blk_sz,
// input
input							clk_vc,
input							vc_rst_z,
input							reg_i_slice,
input	[31:0]					reg_cur_poc,
input							reg_slice_go,
input							reg_col_l0_flag,
input	[ 3:0]					reg_col_ref_idx,
input							reg_tmp_mvp_flag,
input	[ 3:0]					reg_num_ref_l0_act_m1,
input                           reg_avc_mode,
// CCU
input	[ 2:0]					irpu_amvp_ack,
// FME
input	[ 1:0]					fme2amvp_cand_rdy,
input	[1:0][36-1:0]			fme2amvp_cand_mv, // blk_sz(2), refidx(2), mvxy(32)
// CTU
input							cur_ctu_start,
// CU
input	[ 2:0]					cur_cu_start,
input	[ 2:0]					cur_cu_x,
input	[ 2:0]					cur_cu_y,
input	[ 2:0][1:0]				cur_cu_a_avail,
input	[ 2:0][2:0]				cur_cu_b_avail,
input							cur_cu_is_skip,
input							cur_cu_is_zmv,
input							cur_cu_terminate,
input   [1:0]                   is_pic_right,
input                           is_pic_top16,
input                           is_pic_left16,
// neib
input							neib_done_con,
input	[2:0] [33:0]			neib_b,
input	[1:0] [33:0]			neib_a,
input	[1:0] [41:0]			col_c,
input	[1:0]					col_c_avail,
input	[NUM_REF-1:0][32:0]		reflist_info,
input	[3:0] [31:0]			blk32_neib_b_r,
input	[3:0] [31:0]			blk32_neib_a_r,
input	[1:0] [31:0]			blk16_neib_b_r,
input	[1:0] [31:0]			blk16_neib_a_r,
input		  [31:0]			blk8_neib_b_r,
input		  [31:0]			blk8_neib_a_r
);

// local parameter
localparam	TERM_IDLE = 0,
			TERM_WAIT_EMPTY = 1,
			TERM_FLUSH = 2;
    
localparam  CCU_CMDQ_DEPTH  =   2;

// register declaration
reg		[ 2:0]				fsm_term_cs;
reg		[ 2:0]				term_cnt [0:MAX_BLK_SZ-1];
reg		[ 3:0]				blk32_neib_b_avail;
reg		[ 3:0]				blk32_neib_a_avail;
reg		[ 1:0]				blk16_neib_b_avail;
reg		[ 1:0]				blk16_neib_a_avail;
reg							blk8_neib_b_avail;
reg							blk8_neib_a_avail;
reg                         s_is_pic_top16;
reg                         s_is_pic_left16;

// wire declaration
wire	[16:0]				cu_cmd_out_sel;
reg		[ 2:0]				fsm_term_ns;
wire	[ 3:0]				cur_ref_idx;
wire						cand_cu_start;
wire						cand_blk_done;
wire						cand_blk_idle;
wire	[1:0][42:0]			cand_mv;
wire	[1:0]				cand_rdy;
wire	[MAX_BLK_SZ-1:0][CAND_NUM-1:0]		cand_empty_n;
wire	[MAX_BLK_SZ-1:0][CAND_NUM-1:0][45:0]cand_q;
reg		[MAX_BLK_SZ-1:0][CAND_NUM-1:0][45:0]cand_d;
reg		[MAX_BLK_SZ-1:0][CAND_NUM-1:0]		cand_push;
reg		[MAX_BLK_SZ-1:0]					cand_pop;

//reg		[MAX_BLK_SZ-1:0]	fme2amvp_cand_hsk;
reg		[MAX_BLK_SZ-1:0]	irpu_amvp_hsk;
wire	[AMVP2CCU_DW-1:0]	irpu_amvp_wd;
//cand sel
wire						fme_ref_idx;
wire	[45:0]				sel_cand_0;
wire	[45:0]				sel_cand_1;
wire	[15:0]				mvdabs_cand0[0:1]; // 0:x, 1:y
wire	[15:0]				mvdabs_cand1[0:1]; // 0:x, 1:y
wire	[15:0]				mvd_cand0[0:1]; // 0:x, 1:y
wire	[15:0]				mvd_cand1[0:1]; // 0:x, 1:y
wire	[7:0]				mvd_cost0[0:1]; // 0:x, 1:y
wire	[7:0]				mvd_cost1[0:1]; // 0:x, 1:y
wire	[7:0]				mvdcost_cand0_sum;
wire	[7:0]				mvdcost_cand1_sum;
wire						cand_sel; // 0:cand0, 1:cand1
wire						irpu_amvp_empty_n;
wire						all_queue_empty;
wire						zmv;
wire signed	[15:0]			mvx;
wire signed	[15:0]			mvy;
wire	[MAX_BLK_SZ-1:0]	pop_cmdq;
wire	[MAX_BLK_SZ-1:0][33:0]	mv_q;
wire	[MAX_BLK_SZ-1:0]	mv_empty_n;
wire	[MAX_BLK_SZ-1:0]	mv_full_n;
reg		[MAX_BLK_SZ-1:0]	mv_push;
reg		[MAX_BLK_SZ-1:0]	fme2amvp_cand_hsk;
//
reg		[MAX_BLK_SZ-1:0]	amvp2ccu_push;
reg		[MAX_BLK_SZ-1:0]	gt0;
wire	[MAX_BLK_SZ-1:0]	msb_one;
reg		[MAX_BLK_SZ-1:0]	cand_fifo_rdy;
wire	[MAX_BLK_SZ-1:0]	blk_sz;
wire	[1:0][5:0]			fifo_depth;
wire	[2:0]				avail_b;
wire	[1:0]				avail_a;
reg		[2:0][3:0][31:0]	mvbs_neib_b;
reg		[2:0][3:0][31:0]	mvbs_neib_a;
reg		[1:0][3:0]			mv_bs_b;
reg		[1:0][3:0]			mv_bs_a;
reg		[2:0][3:0]			mvbs_b_avail;
reg		[2:0][3:0]			mvbs_a_avail;
reg     [3:0]               avc_bs_b;
reg     [3:0]               avc_bs_a;
wire    [1:0]               avc_zero_motion;

genvar						i,j;

// combinational logic
always@(*) begin : mvbs_avail
	integer i,j;
	for(i=0 ; i<3 ; i++) begin
		for(j=0 ; j<4 ; j++) begin
            if(i==0 & j==0) begin
				mvbs_b_avail[i][j] = blk8_neib_b_avail;
				mvbs_a_avail[i][j] = blk8_neib_a_avail;
			end
            else if(i==1 & j<2) begin
				mvbs_b_avail[i][j] = blk16_neib_b_avail[j];
				mvbs_a_avail[i][j] = blk16_neib_a_avail[j];
			end
            else if(i==2) begin
				mvbs_b_avail[i][j] = blk32_neib_b_avail[j];
				mvbs_a_avail[i][j] = blk32_neib_a_avail[j];
			end
            else begin
				mvbs_b_avail[i][j] = 0;
				mvbs_a_avail[i][j] = 0;
			end
		end
	end
end

assign	cu_cmd_out_sel = cu_blk_en[2] ? {3'b100, cu_cmd_out[2]} :
						 cu_blk_en[1] ? {3'b010, cu_cmd_out[1]} :
										{3'b001, cu_cmd_out[0]} ;

assign	avail_b		 = cu_cmd_out_sel[ 8:6];
assign	avail_a		 = cu_cmd_out_sel[10:9];
assign fifo_depth[1] = FME_BLK16_CMDQ_DEPTH;
assign fifo_depth[0] = FME_BLK8_CMDQ_DEPTH;

generate
	if( NUM_REF == 1 ) begin : num_ref_equal_1_blk
		always@(*) begin : cand_fifo_rdy_blk
            integer i;
			for(i=0 ; i<MAX_BLK_SZ ; i++) begin
				cand_fifo_rdy[i] = reg_avc_mode ? cand_empty_n[i][0] : &cand_empty_n[i];
			end
        end
	end
	else if(NUM_REF == 2) begin : num_ref_equal_2_blk
        always@(*) begin : cand_fifo_rdy_blk
			integer i;
			for(i=0 ; i<MAX_BLK_SZ ; i++) begin
                cand_fifo_rdy[i] = (reg_num_ref_l0_act_m1==0) ? (reg_avc_mode ? cand_empty_n[i][0] : &cand_empty_n[i][1:0]) : &cand_empty_n[i];
			end
		end
	end
endgenerate

always@(*) begin : amvp_itf_blk
	integer i;
	for(i=0 ; i<MAX_BLK_SZ ; i++) begin
        amvp2fme_cand_ack[i]= mv_full_n[i];
		fme2amvp_cand_hsk[i]= fme2amvp_cand_rdy[i] & amvp2fme_cand_ack[i];
		irpu_amvp_dlat[i] 	= fme2amvp_cand_hsk[i];
        irpu_amvp_mv_info[i]= fme2amvp_cand_mv[i][33:0];
	end
end

assign	zmv = cu_cmd_out_sel[11];

always@(*) begin : cand_out_fifio_ctrl
	integer i,j;
	for(j=0 ; j<MAX_BLK_SZ ; j++) begin
        for(i=0 ; i<CAND_NUM ; i++) begin
			cand_push[j][i] = blk_sz[j] & (cur_ref_idx[0] == i[1]) & cand_rdy[i[0]];
			cand_d[j][i]	= {cu_cmd_out_sel[16:14],cand_mv[i[0]]};
		end
    end
end

always@(*) begin : max_blk_sz_assign_blk
	integer j;
	for(j=0 ; j<MAX_BLK_SZ ; j++) begin
        if(j==0)
		cand_pop[j] = mv_empty_n[j] & cand_fifo_rdy[j];
		else
        cand_pop[j] = mv_empty_n[j] & cand_fifo_rdy[j] & !cand_pop[0];
		mv_push[j]	= fme2amvp_cand_rdy[j] & amvp2fme_cand_ack[j];
	end
end

assign	fme_ref_idx = cand_pop[1] ? mv_q[1][32] : mv_q[0][32];
assign	sel_cand_0 	= cand_pop[1] ? cand_q[1][fme_ref_idx*NUM_REF  ] : cand_q[0][fme_ref_idx*NUM_REF  ];
assign	sel_cand_1 	= cand_pop[1] ? cand_q[1][fme_ref_idx*NUM_REF+1] : cand_q[0][fme_ref_idx*NUM_REF+1];
assign	mvx = zmv ? 0 : ( cand_pop[1] ? mv_q[1][15: 0] : mv_q[0][15: 0] );
assign	mvy = zmv ? 0 : ( cand_pop[1] ? mv_q[1][31:16] : mv_q[0][31:16] );

assign	{mvdabs_cand0[0], mvd_cand0[0]} = mvdabs_mvd(mvx, sel_cand_0[15: 0]); // cand0 x
assign	{mvdabs_cand0[1], mvd_cand0[1]} = mvdabs_mvd(mvy, sel_cand_0[31:16]); // cand0 y
assign	{mvdabs_cand1[0], mvd_cand1[0]} = mvdabs_mvd(mvx, sel_cand_1[15: 0]); // cand1 x
assign	{mvdabs_cand1[1], mvd_cand1[1]} = mvdabs_mvd(mvy, sel_cand_1[31:16]); // cand1 y
assign	mvdcost_cand0_sum = mvd_cost0[0] + mvd_cost0[1];
assign	mvdcost_cand1_sum = mvd_cost1[0] + mvd_cost1[1];
assign	cand_sel = ~reg_avc_mode & (mvdcost_cand0_sum > mvdcost_cand1_sum);
assign	irpu_amvp_wd[31: 0] = {mvy, mvx};
assign	irpu_amvp_wd[47:32] = cand_sel ? mvd_cand1[0] 						: mvd_cand0[0];
assign	irpu_amvp_wd[63:48] = cand_sel ? mvd_cand1[1] 						: mvd_cand0[1];
assign	irpu_amvp_wd[67:64] = 4'(fme_ref_idx);
assign	irpu_amvp_wd[   68] = cand_sel;
assign	irpu_amvp_wd[   69] = cand_sel ? sel_cand_1[42] 					: sel_cand_0[42];
assign	irpu_amvp_wd[77:70] = cand_sel ? sel_cand_1[41:34] 					: sel_cand_0[41:34];
assign	irpu_amvp_wd[85:78] = {mv_bs_b[cand_pop[1]], mv_bs_a[cand_pop[1]]};


always@(*) begin : mvbs_blk32
integer i;
	for(i=0 ; i<4 ; i++) begin
		mvbs_neib_b[2][i] = blk32_neib_b_r[i];
		mvbs_neib_a[2][i] = blk32_neib_a_r[i];
	end
end

always@(*) begin : mvbs_blk16
	integer i;
	for(i=0 ; i<4 ; i++) begin
		if(i<2) begin
            mvbs_neib_b[1][i] = blk16_neib_b_r[i];
			mvbs_neib_a[1][i] = blk16_neib_a_r[i];
		end
		else begin
            mvbs_neib_b[1][i] = 0;
			mvbs_neib_a[1][i] = 0;
		end
	end
end

always@(*) begin : mvbs_blk8
	integer i;
	for(i=0 ; i<4 ; i++) begin
		if(i<1) begin
			mvbs_neib_b[0][i] = blk8_neib_b_r;
            mvbs_neib_a[0][i] = blk8_neib_a_r;
		end
		else begin
			mvbs_neib_b[0][i] = 0;
			mvbs_neib_a[0][i] = 0;
        end
    end
end

always@(*) begin : mv_bs
	integer i,j;
	for(j=0 ; j<2 ; j++) begin
		for(i=0 ; i<4 ; i++) begin
            mv_bs_b[j][i]= get_mv_bs({mvy, mvx}, mvbs_neib_b[j][i], amvp2ccu_push, mvbs_b_avail[j][i], i[1:0]);
			mv_bs_a[j][i]= get_mv_bs({mvy, mvx}, mvbs_neib_a[j][i], amvp2ccu_push, mvbs_a_avail[j][i], i[1:0]);
		end
	end
    // AVC MVP BS
    for(i = 0; i < 4; i++)begin
        avc_bs_b[i] =   get_mv_bs(avc_mvpxy, mvbs_neib_b[1][i], 2'd2, mvbs_b_avail[1][i], i[1:0]);
        avc_bs_a[i] =   get_mv_bs(avc_mvpxy, mvbs_neib_a[1][i], 2'd2, mvbs_a_avail[1][i], i[1:0]);
    end
end

assign	all_queue_empty = ~|{cmdq_empty_n, cand_empty_n, irpu_amvp_rdy};

always@(*) begin : chk_terminate_blk
	integer i;
	for(i=0 ; i<MAX_BLK_SZ ; i=i+1) begin
		gt0[i] = term_cnt[i]>0;
	end
end

assign	msb_one = find_msb_one(gt0);

always@(*) begin : amvp2ccu_fifo_pp
	integer i;
	for(i=0 ; i<MAX_BLK_SZ ; i++) begin
        amvp2ccu_push[i] = (fsm_term_cs[TERM_FLUSH] & msb_one[i]) | ( cand_pop[i] );
		irpu_amvp_hsk[i] = irpu_amvp_rdy[i] & irpu_amvp_ack[i];
	end
end

assign  avc_mvp_push    =   reg_avc_mode & amvp2ccu_push[1];
assign  avc_ref_idx     =   {1'b0, fme_ref_idx};
assign  avc_is_long     =   sel_cand_0[42];
assign  avc_pocdiff     =   sel_cand_0[34+:8];
assign	avc_mvd_gt4     =   {avc_bs_b, avc_bs_a};

assign  avc_zero_motion[0]  =   s_is_pic_top16  | (mvbs_b_avail[1][0] & mvbs_neib_b[1][0] == 0);
assign  avc_zero_motion[1]  =   s_is_pic_left16 | (mvbs_a_avail[1][0] & mvbs_neib_a[1][0] == 0);
assign  avc_mvpxy           =   |avc_zero_motion ? 0 : sel_cand_0[0+:32];

generate
    if(MAX_BLK_SZ==2) begin : assign_max_blk_sz_blk32
		assign irpu_amvp_rdy[2] = 0;
		assign irpu_amvp_rd[2] = 0;
		
	end
endgenerate

assign	blk_sz = cu_cmd_out_sel[14+:MAX_BLK_SZ];

//function/task

function get_mv_bs;
input	[31:0]	cand_mv;
input	[31:0]	neib_mv;
input	[ 1:0]	blk_sz; // one hot b2:32, b1:16, b0:8
input			neib_avail;
input	[ 1:0]	idx;	// 0~3
reg		[15:0]	cand_mv_x;
reg		[15:0]	cand_mv_y;
reg		[15:0]	neib_mv_x;
reg		[15:0]	neib_mv_y;
reg	signed	[16:0]	mv_x_diff;
reg	signed	[16:0]	mv_y_diff;
reg	signed  [16:0]	mvx_abs;
reg	signed  [16:0]	mvy_abs;
reg				en;
begin
	{cand_mv_y, cand_mv_x} = cand_mv;
	{neib_mv_y, neib_mv_x} = neib_mv;
	mv_x_diff = $signed(cand_mv_x) - $signed(neib_mv_x);
	mv_y_diff = $signed(cand_mv_y) - $signed(neib_mv_y);
	mvx_abs = mv_x_diff[16] ? -mv_x_diff : mv_x_diff;
	mvy_abs = mv_y_diff[16] ? -mv_y_diff : mv_y_diff;

    en = //blk_sz[2] ? 1 :
		 blk_sz[1] ? idx<=1 :
				     idx==0;
                     
    get_mv_bs = (en & neib_avail) ? (mvx_abs>=4 | mvy_abs>=4) : 0;
end
endfunction

function [31:0]	mvdabs_mvd ;
input[15:0]	fme_mv;
input[15:0] pred_mv;
reg	 signed [16:0]	mvdiff;
reg	 signed [15:0]	mvd;
reg			sign;
reg  [15:0]	mvdabs;
begin
		mvdiff  = $signed(fme_mv) - $signed(pred_mv);
		mvd	    = mvdiff[15:0];
		sign	= mvdiff[16];
        mvdabs  = sign ? (-mvd) : mvd;
		mvdabs_mvd = {mvdabs,mvd};
end
endfunction

function reg [MAX_BLK_SZ-1:0] find_msb_one;
input	[MAX_BLK_SZ-1:0] data;
reg			is_found;
integer i;
begin
	is_found = 0;
    find_msb_one = 0;	
	for(i=MAX_BLK_SZ-1 ; i>=0 ; i=i-1) begin
		if(~is_found) begin
			is_found = data[i];
            find_msb_one[i] = is_found;
		end	
	end

end
endfunction

// instantiation
vc_mvp_ctrl
#(	
	.MAX_BLK_SZ (MAX_BLK_SZ), // 3:(blk32, blk16, blk8), 2:(blk16, blk8), 1:blk8
   	.NUM_REF    (NUM_REF),
	.AMVP_OR_MRG(1)
)
U_VC_AMVP_CTRL
(
// output
.cur_ref_idx		(cur_ref_idx),
.cu_blk_en			(cu_blk_en),
.cu_cmd_out 		(cu_cmd_out),
.neib_cu_start      (neib_cu_start),
.cand_cu_start      (cand_cu_start),
.empty_n			(cmdq_empty_n),
.pop				(pop_cmdq),
.dbg_fsm_mvp_cs		(dbg_fsm_mvp_cs),
.blk_sz_lat         (blk_sz_lat),
.n_blk_sz           (n_blk_sz),
// input
.clk_vc				(clk_vc),
.vc_rst_z			(vc_rst_z),
.reg_avc_mode       (reg_avc_mode),
.reg_i_slice		(reg_i_slice),
.reg_slice_go		(reg_slice_go),
.reg_num_ref_l0_act_m1(reg_num_ref_l0_act_m1),
.cur_ctu_start      (cur_ctu_start),
.cur_cu_start       (cur_cu_start),
.cur_cu_x           (cur_cu_x),
.cur_cu_y           (cur_cu_y),
.cur_cu_b_avail     (cur_cu_b_avail),
.cur_cu_a_avail     (cur_cu_a_avail),
.cur_cu_is_zmv      (cur_cu_is_zmv),
.cur_cu_is_skip     (cur_cu_is_skip),
.cur_cu_terminate   (cur_cu_terminate),
.is_pic_right       ({1'b0, is_pic_right}),
.neib_done_con      (neib_done_con),
.cand_blk_done      (cand_blk_done),
.cand_blk_idle      (cand_blk_idle)
);

vc_mvp_cand_gen
#(
	.NUM_REF (NUM_REF),
	.AMVP_OR_MRG (1),
	.MVP_SCALE_EN (MVP_SCALE_EN)
)
U_VC_AMVP_CAND_GEN
(
// output
.cand_mv 			(cand_mv),
.cand_rdy	        (cand_rdy),
.cand_blk_done		(cand_blk_done),
.cand_blk_idle		(cand_blk_idle),
.dbg_fsm_cand_cs	(dbg_fsm_cand_cs),
// input
.clk_vc             (clk_vc),
.vc_rst_z           (vc_rst_z),
.cand_cu_start      (cand_cu_start),
.mrg_cand_nr_m1		(3'd1),
.reg_slice_go		(reg_slice_go),
.reg_cur_poc        (reg_cur_poc),
.reg_tmp_mvp_flag	(reg_tmp_mvp_flag),
.reg_num_ref_l0_act_m1(reg_num_ref_l0_act_m1),
.cu_cmd_out			(cu_cmd_out_sel),
.neib_b             (neib_b),
.neib_a             (neib_a),
.col_c              (col_c),
.col_c_avail        (col_c_avail),
.reflist_info       (reflist_info),
.cur_ref_idx        (cur_ref_idx[1:0]),
.col_ref_idx	    (reg_col_ref_idx[1:0]),
.reg_avc_mode       (reg_avc_mode)
);

generate
	for(j=0 ; j<MAX_BLK_SZ ; j++) begin : blk_sz_level
		for(i=0 ; i<CAND_NUM ; i++) begin : cand_num_level
			//blk_sz[45:43], long[42],pocdiff[41:34], ref_idx[33:32], mv[31:0]
			sht_mdl 
            #(
				.DEPTH		(1),
				//.ADDR_LG2_W (1),
			   	.DATA_W 	(46),
				.RST_EN		(1)
			)
            U_CAND_OUT_FIFO(
			// output
			.full_n 	(),
			.n_full_n	(),
			.empty_n	(cand_empty_n[j][i]),
			.n_empty_n	(),
			.q			(cand_q[j][i]),
            // input
			.clk		(clk_vc),
			.rstz		(vc_rst_z),
			.push		(cand_push[j][i]),
			.pop		(cand_pop[j]),
			.d			(cand_d[j][i])
			);	
        end

    end

endgenerate

sht_mdl 
#(
	.DEPTH		( FME_BLK16_CMDQ_DEPTH ),  // blk16 depth 1=>2, blk8 depth 0=>8
   	.DATA_W 	(34),
	.RST_EN		(1)
)
U_FME_16_CAND_FIFO(
// output
.full_n 	(mv_full_n[1]),
.n_full_n	(),
.empty_n	(mv_empty_n[1]),
.n_empty_n	(),
.q			(mv_q[1]),
// input
.clk		(clk_vc),
.rstz		(vc_rst_z),
.push		(mv_push[1]),
.pop		(cand_pop[1]),
.d			(fme2amvp_cand_mv[1][33:0])
);

sht_mdl 
#(
	.DEPTH		( FME_BLK8_CMDQ_DEPTH ),  // blk16 depth 1=>2, blk8 depth 0=>8
   	.DATA_W 	(34),
	.RST_EN		(1)
)
U_FME_8_CAND_FIFO(
    // output
.full_n 	(mv_full_n[0]),
.n_full_n	(),
.empty_n	(mv_empty_n[0]),
.n_empty_n	(),
.q			(mv_q[0]),
// input
.clk		(clk_vc),
.rstz		(vc_rst_z),
.push		(mv_push[0]),
.pop		(cand_pop[0]),
.d			(fme2amvp_cand_mv[0][33:0])
);

// SSE[140,101], SATD[100:81], 
// pocdiff[77:70], longterm[69], mvp_l0_flag[68], ref_idx[67:64], mvd[63:32], mv[31:0]
generate
    for(i=0 ; i<MAX_BLK_SZ ; i++) begin : amvp2ccu_fifo_blk

		sht_mdl 
		#(
            .DEPTH		(CCU_CMDQ_DEPTH), 
		   	.DATA_W 	(AMVP2CCU_DW),
			.RST_EN		(1)
		)
		U_AMVP2CCU_FIFO(
        // output
		.full_n 	(),
		.n_full_n	(),
		.empty_n	(irpu_amvp_rdy[i]),
		.n_empty_n	(),
		.q			(irpu_amvp_rd[i]),
        // input
		.clk		(clk_vc),
		.rstz		(vc_rst_z),
		.push		(amvp2ccu_push[i]),
		.pop		(irpu_amvp_hsk[i]),
		.d			(irpu_amvp_wd)
        );
	end
endgenerate

ve_irpu_expg_bits
#( 	
    .IN_BW (16) // ===> set this only!!!
)
VE_IRPU_EXPG_MVD_CAND0_X
(
// output
.val_out	(mvd_cost0[0]),
// input
.val_in		(mvd_cand0[0])
);

ve_irpu_expg_bits
#( 	
    .IN_BW (16) // ===> set this only!!!
)
VE_IRPU_EXPG_MVD_CAND0_Y
(
// output
.val_out	(mvd_cost0[1]),
// input
.val_in		(mvd_cand0[1])
);

ve_irpu_expg_bits
#( 	
    .IN_BW (16) // ===> set this only!!!
)
VE_IRPU_EXPG_MVD_CAND1_X
(
// output
.val_out	(mvd_cost1[0]),
// input
.val_in		(mvd_cand1[0])
);

ve_irpu_expg_bits
#( 	
    .IN_BW (16) // ===> set this only!!!
)
VE_IRPU_EXPG_MVD_CAND1_Y
(
// output
.val_out	(mvd_cost1[1]),
// input
.val_in		(mvd_cand1[1])
);

// state machine
always@(*) begin : fsm_terminal_ctrl
	fsm_term_ns = 0;
	case(1)
    fsm_term_cs[TERM_IDLE]: begin
			if( |cur_cu_start & cur_cu_terminate )
				fsm_term_ns[TERM_WAIT_EMPTY] = 1;
			else
                fsm_term_ns[TERM_IDLE] = 1;
		end
		fsm_term_cs[TERM_WAIT_EMPTY]: begin
            if( all_queue_empty )
				fsm_term_ns[TERM_FLUSH] = 1;
			else
				fsm_term_ns[TERM_WAIT_EMPTY] = 1;
		end
        fsm_term_cs[TERM_FLUSH]: begin
			if( gt0 == 0 )
				fsm_term_ns[TERM_IDLE] = 1;
			else
				fsm_term_ns[TERM_FLUSH] = 1;
		end
    endcase
end

// sequence logic
always@(posedge clk_vc or negedge vc_rst_z)begin 
    if(~vc_rst_z) begin
		fsm_term_cs <= 1;
        end else if(reg_slice_go)
		fsm_term_cs <= 1;
	else if( fsm_term_cs != fsm_term_ns )begin
		fsm_term_cs <= fsm_term_ns;
    end
end

always@(posedge clk_vc or negedge vc_rst_z)begin : termination_cnt_block
	integer i;
	if(~vc_rst_z) begin
        for(i=0 ; i< MAX_BLK_SZ ; i=i+1)
			term_cnt[i] <= 0;
	end
    else if(reg_slice_go) begin
		for(i=0 ; i< MAX_BLK_SZ ; i=i+1)
			term_cnt[i] <= 0;
    end
    else if(fsm_term_cs[TERM_FLUSH]) begin
		for(i=0 ; i< MAX_BLK_SZ ; i=i+1)
			if(msb_one[i])
				term_cnt[0] <= term_cnt[0] -1;
	end
    else if( cur_cu_terminate )begin
		for(i=0 ; i< MAX_BLK_SZ ; i=i+1)
			if(cur_cu_start[i])
				term_cnt[i] <= term_cnt[i] + 1;
	end
end

always@(posedge clk_vc or negedge vc_rst_z) begin
    if(~vc_rst_z)begin
        blk32_neib_b_avail  <=  0;
        blk32_neib_a_avail  <=  0;
        blk16_neib_b_avail  <=  0;
        blk16_neib_a_avail  <=  0;
        blk8_neib_b_avail   <=  0;
        blk8_neib_a_avail   <=  0;
		s_is_pic_top16 		<=  0;
        s_is_pic_left16 	<=  0;
    end else if(reg_slice_go)begin
        blk32_neib_b_avail  <=  0;
        blk32_neib_a_avail  <=  0;
        blk16_neib_b_avail  <=  0;
        blk16_neib_a_avail  <=  0;
        blk8_neib_b_avail   <=  0;
        blk8_neib_a_avail   <=  0;
		s_is_pic_top16 		<=  0;
		s_is_pic_left16 	<=  0;
    end else begin
	    if(cur_cu_start[2]) begin
	    	blk32_neib_b_avail[0] <= cur_cu_b_avail[0][1];
	    	blk32_neib_b_avail[1] <= cur_cu_b_avail[0][0];
	    	blk32_neib_b_avail[2] <= cur_cu_b_avail[1][0];
            blk32_neib_b_avail[3] <= cur_cu_b_avail[2][1];

	    	blk32_neib_a_avail[0] <= cur_cu_a_avail[0][1];
	    	blk32_neib_a_avail[1] <= cur_cu_a_avail[1][1];
	    	blk32_neib_a_avail[2] <= cur_cu_a_avail[1][0];
	    	blk32_neib_a_avail[3] <= cur_cu_a_avail[2][1];
        end

        if(cur_cu_start[1]) begin
	    	blk16_neib_b_avail[0] <= cur_cu_b_avail[0][1];
	    	blk16_neib_b_avail[1] <= cur_cu_b_avail[0][0];

            blk16_neib_a_avail[0] <= cur_cu_a_avail[0][1];
	    	blk16_neib_a_avail[1] <= cur_cu_a_avail[1][1];

            s_is_pic_top16      <=  is_pic_top16;
            s_is_pic_left16     <=  is_pic_left16;
        end

        if(cur_cu_start[0]) begin
	    	blk8_neib_b_avail <= cur_cu_b_avail[0][1];
	    	blk8_neib_a_avail <= cur_cu_a_avail[0][1];
	    end
    end
end

endmodule
