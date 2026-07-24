`include "ve_defines.v"
module	vc_mvp_cand_gen
#(
    parameter NUM_REF = 2,
	parameter AMVP_OR_MRG = 1,
	parameter MVP_SCALE_EN = 0,
    parameter AW = AMVP_OR_MRG ? 4:2,
	parameter BW = AMVP_OR_MRG ? 6:3,
	parameter FSMW = AMVP_OR_MRG ? 5:3
)
(
//output
// long[42],pocdif[41:34],ref_idx[33:32],mv[31:0]
output	reg [1:0][42:0]	cand_mv, 
output	[1:0]			cand_rdy,
output					cand_blk_done,
output					cand_blk_idle,
output	[FSMW-1:0]		dbg_fsm_cand_cs,

//input
input					clk_vc,
input					vc_rst_z,
input					cand_cu_start,
input	[2:0]			mrg_cand_nr_m1,
input					reg_slice_go,
input					reg_tmp_mvp_flag,
input	[3:0]			reg_num_ref_l0_act_m1,
input	[31:0]			reg_cur_poc,
input                   reg_avc_mode,
input	[16:0]			cu_cmd_out,
//----- neib b -----
// mvxy[0+:32],
// ref_idx[32+:2]
input	[2:0][33:0]		neib_b,
//----- neib a -----
// mvxy[0+:32],
// ref_idx[32+:2]
input	[1:0][33:0] 	neib_a,
//----- neib col c -----
// mvxy[0+:32],
// poc_diff[32+:8],
// long[41]
// intra[40]
input	[-1:0][41:0] 	col_c,
input	[-1:0]	 		col_c_avail,
//----- reflist -----
// poc [-1+:32]
// long[31]
input	[NUM_REF-1:0][32:0] reflist_info,
input	[1:0]			cur_ref_idx,
input	[1:0]			col_ref_idx
);

//local parameter

localparam	CAND_IDLE = 0,
			CAND_WAIT_SCALE_A = 3,
			CAND_WAIT_SCALE_B = 4,
			CAND_WAIT_SCALE_C = 1,
			CAND_DONE = 2;

localparam	UA = 0,
			SA = 1,
			UB = 2,
			SB = 3;
		//	UC = 5,
		//	SC = 6,
		//	ZO = 7;

localparam  A1 = 0,
			B1 = 1,
			B0 = 2,
			A0 = 3,
			B2 = 4,
			UC = 5,
			SC = 6,
			Z0 = 7,
            MED = 8;

//register declaration

reg		[FSMW-1:0]fsm_cand_cs;
reg				cand_num;

reg     [FSMW-1:0]fsm_cand_ns;

//wire decalration

//neighbor available
wire			a0_avail;
wire			a1_avail;
wire			b0_avail;
wire			b1_avail;
wire			b2_avail;
wire			c0_avail;
wire			c1_avail;
//current ref info
wire	[31:0]	cur_ref_poc;
reg		[NUM_REF-1:0] [31:0] ref_poc;
wire	[31:0]	sel_poc;
wire	[31:0]	ref0_poc;
wire	[31:0]	ref1_poc;
wire	[ 7:0]  ref_pocdif;
wire			ref_long;
//neighbor long
wire			a0_long;
wire			a1_long;
wire			b0_long;
wire			b1_long;
wire			b2_long;
// neighbor poc
wire	[31:0]	a0_poc;
wire	[31:0]	a1_poc;
wire	[31:0]	b0_poc;
wire	[31:0]	b1_poc;
wire	[31:0]	b2_poc;
//col info (POC diff, intra, long)
wire	[ 7:0]	c0_pocdif;
wire			c0_intra;
wire			c0_long;
wire	[ 7:0]	c1_pocdif;
wire			c1_intra;
wire			c1_long;
wire	[ 7:0]	col_poc_diff;
//mv => mvx[15:0], mvy[31:16]
wire	[31:0]	a0_mv;
wire	[31:0]	a1_mv;
wire	[31:0]	b0_mv;
wire	[31:0]	b1_mv;
wire	[31:0]	b2_mv;
wire	[31:0]	c0_mv;
wire	[31:0]	c1_mv;
// neighbor reference indices
wire	[ 1:0]	a0_refidx;
wire	[ 1:0]	a1_refidx;
wire	[ 1:0]	b0_refidx;
wire	[ 1:0]	b1_refidx;
wire	[ 1:0]	b2_refidx;

wire	[AW-1:0]cand_a;	
wire	[BW-1:0]cand_b;	
wire	[ 3:0]	cand_c;	

wire			ua;
wire			ub;
wire			uc;
wire			sa;
wire			sb;
wire			sc;
wire			cand_ua_ub_con;
wire			sb_chk_uscale_con;
wire			mva_neq_mvb;
wire			mvb_neq_mvb;
wire			mv_a1_b1_diff;
wire			mv_a1_b2_diff;
wire			mv_a1_a0_diff;
wire			mv_b1_b0_diff;
wire			mv_b1_b2_diff;
reg		[31:0]	sel_cand0_poc;
reg		[31:0]	sel_cand1_poc;

wire	[ 7:0]	sel_poc_diff;
reg 	[31:0]	sel_neib_poc;
wire	[ 7:0]	n_cur_poc_diff;
reg		[ 4:0]	neib_sel_onehot;
reg		[ 6:0]	mv_sel_onehot;
reg		[ 8:0]	cand0_sel_onehot;
reg		[ 7:0]	cand1_sel_onehot;
wire			scale_done;
wire	[15:0]	scale_mvx;
wire	[15:0]	scale_mvy;
reg		[15:0]	mvx_sel;
reg		[15:0]	mvy_sel;
wire	[31:0]	mva_sel;
wire	[31:0]	mvb_sel;
wire	[31:0]	mvb_sel_us;

reg				cand_num_inc;
reg				cand_num_rst;
reg				scale_start;

wire	[2:0]	blk_sz;
wire	[2:0]	cux;
wire	[2:0]	cuy;
// wire [1:0]   col_ref;
//AVC
reg [1:0]       b_c_avail;
reg [1:0][15:0] avc_mvpxy;

//combinational logic

//assign  col_ref = reg_cur_poc[1:0] -1 - (  (cand_c[0] | cand_c[2]) ?  col_c[0][32+:2] : col_c[1][32+:2] );
//assign col_ref =  1- ((cand_c[0] | cand_c[2]) ?  col_c[0][32+:2] : col_c[1][32+:2]);

//dbg
assign	dbg_fsm_cand_cs = fsm_cand_cs;

// candidate block done
assign	cand_blk_done = fsm_cand_cs[CAND_DONE];
assign	cand_blk_idle = fsm_cand_cs[CAND_IDLE];

// neighbor available
assign	blk_sz		=   cu_cmd_out[16:14];
assign	cuy			=   cu_cmd_out[5:3];
assign	cux			=   cu_cmd_out[2:0];
assign	a0_avail 	=	cu_cmd_out[ 9];
assign	a1_avail 	= 	cu_cmd_out[10];
assign	b0_avail 	= 	cu_cmd_out[ 6];
assign	b1_avail 	= 	cu_cmd_out[ 7];
assign	b2_avail 	= 	cu_cmd_out[ 8];

assign	c1_avail  	= col_c_avail[1];//reg_tmp_mvp_flag; 
assign	c0_avail 	= col_c_avail[0];/*blk_sz[2] ? ( cuy!= 3'd4 & reg_tmp_mvp_flag) :  //  cuy==4 => 0
					  blk_sz[1] ? ( cuy!= 3'd6 & reg_tmp_mvp_flag) ://  cuy==6 => 0
								  ( cuy!= 3'd7 & reg_tmp_mvp_flag); //  cuy==7 => 0 
*/
// cur ref info
always@(*) begin : mul_ref_poc_blk
	integer i;
	for(i=0 ; i<NUM_REF ; i=i+1)
		ref_poc[i] = reflist_info[i][31:0];
end
//assign	ref0_poc	=   reflist_info[0][31:0];
//assign	ref1_poc	=   reflist_info[1][31:0];
assign	cur_ref_poc	=	reflist_info[cur_ref_idx][31:0];
assign	ref_long	=	reflist_info[cur_ref_idx][32];
assign	ref_pocdif	= 	n_cur_poc_diff;
// neighbor long
assign	a0_long		= 	reflist_info[neib_a[0][32+:2]][32];
assign	a1_long		= 	reflist_info[neib_a[1][32+:2]][32];
assign	b0_long		= 	reflist_info[neib_b[0][32+:2]][32];
assign	b1_long		= 	reflist_info[neib_b[1][32+:2]][32];
assign	b2_long     =   reflist_info[neib_b[2][32+:2]][32];
// neighbor POC
assign	a0_poc		= 	reflist_info[neib_a[0][32+:2]][31:0];
assign	a1_poc		= 	reflist_info[neib_a[1][32+:2]][31:0];
assign	b0_poc		= 	reflist_info[neib_b[0][32+:2]][31:0];
assign	b1_poc		= 	reflist_info[neib_b[1][32+:2]][31:0];
assign	b2_poc      =   reflist_info[neib_b[2][32+:2]][31:0];
// neib mv
assign	a0_mv		=	neib_a[0][31:0];
assign	a1_mv		=	neib_a[1][31:0];
assign	b0_mv		=	neib_b[0][31:0];
assign	b1_mv		=	neib_b[1][31:0];
assign	b2_mv		=	neib_b[2][31:0];
// ref_idx
assign	a0_refidx	=	neib_a[0][32+:2];
assign	a1_refidx	=	neib_a[1][32+:2];
assign	b0_refidx	=	neib_b[0][32+:2];
assign	b1_refidx	=	neib_b[1][32+:2];
assign	b2_refidx	=	neib_b[2][32+:2];
// col related
assign	c0_pocdif  =	col_c[0][32+:8];
assign	c1_pocdif  =	col_c[1][32+:8];
assign	c0_long    =	col_c[0][41];
assign	c0_intra   =	col_c[0][40];
assign	c1_long    =	col_c[1][41];
assign	c1_intra   =	col_c[1][40];
// col mv
assign	c0_mv		=	col_c[0][31:0];
assign	c1_mv		=	col_c[1][31:0];
// scale related
assign	col_poc_diff = cand_c[2] ? col_c[0][32+:8] : col_c[1][32+:8];
assign	n_cur_poc_diff = poc_diff_clip3(reg_cur_poc, cur_ref_poc);

generate
if(AMVP_OR_MRG) begin : amvp_output_sel
	// unscale
	assign	ua			=  |cand_a[1:0];
	assign	ub			=  |cand_b[2:0];
	assign	uc			=  |cand_c[1:0];
	// scale
	assign	sa			=  |cand_a[3:2];
	assign	sb			=  |cand_b[5:3];
	assign	sc			=  |cand_c[3:2];

	// mva, mvb
	assign	mva_neq_mvb = (|cand_a & |cand_b) ? mva_sel != mvb_sel : 0;
	// mvb, mvb scale
	assign	mvb_neq_mvb = (|cand_b[2:0] & |cand_b[5:3]) ? mvb_sel_us != {scale_mvy, scale_mvx}  : 0;

	// no scale
	assign	cand_ua_ub_con	= ua & ub & mva_neq_mvb; // unscale a+b

	assign	sb_chk_uscale_con = (cand_b[3] & ( ref_long | (cur_ref_poc == b0_poc) ) & (mvb_sel_us == b0_mv) ) |
								(cand_b[4] & ( ref_long | (cur_ref_poc == b1_poc) ) & (mvb_sel_us == b1_mv) ) |
								(cand_b[5] & ( ref_long | (cur_ref_poc == b2_poc) ) & (mvb_sel_us == b2_mv) )  ;

	// scale related
	assign	sel_poc_diff = sc ? col_poc_diff : poc_diff_clip3(reg_cur_poc, sel_neib_poc);

	// for poc dif 
	always@(*) begin
		case(1)
			neib_sel_onehot[0] : sel_neib_poc = a0_poc;
			neib_sel_onehot[1] : sel_neib_poc = a1_poc;
			neib_sel_onehot[2] : sel_neib_poc = b0_poc;
			neib_sel_onehot[3] : sel_neib_poc = b1_poc;
				  default	   : sel_neib_poc = b2_poc; // cand_b[5]
		endcase
	end
	
	// for scale input
	always@(*) begin
		case(1)
			mv_sel_onehot[0] : {mvy_sel,mvx_sel} = a0_mv;
			mv_sel_onehot[1] : {mvy_sel,mvx_sel} = a1_mv;
			mv_sel_onehot[2] : {mvy_sel,mvx_sel} = b0_mv;
			mv_sel_onehot[3] : {mvy_sel,mvx_sel} = b1_mv;
			mv_sel_onehot[4] : {mvy_sel,mvx_sel} = b2_mv;
			mv_sel_onehot[5] : {mvy_sel,mvx_sel} = c0_mv;
			default         : {mvy_sel,mvx_sel} = c1_mv; // cand_c[3]
		endcase
	end

	assign mva_sel = cand_a[0] ? a0_mv :
					cand_a[1] ? a1_mv :
					{scale_mvy, scale_mvx};

	assign mvb_sel = cand_b[0] ? b0_mv :
					cand_b[1] ? b1_mv :
					cand_b[2] ? b2_mv :
					{scale_mvy, scale_mvx};

	assign mvb_sel_us = cand_b[0] ? b0_mv :
						cand_b[1] ? b1_mv :
						b2_mv;

	// long[42], pocdiff[41:34], ref_idx[33:32], mv[31:0]

	// ref_idx[33:32], mv[31:0]
	always@(*) begin
		case(1)
			cand0_sel_onehot[UA] : cand_mv[0][33:0]= cand_a[0] ? neib_a[0] : neib_a[1];
			cand0_sel_onehot[SA] : cand_mv[0][33:0]={1'b0,!cur_ref_idx[0],scale_mvy[15:0], scale_mvx[15:0]};
			cand0_sel_onehot[UB] : cand_mv[0][33:0]= cand_b[0] ? neib_b[0] : ( cand_b[1] ? neib_b[1] : neib_b[2] );
			cand0_sel_onehot[SB] : cand_mv[0][33:0]={1'b0,!cur_ref_idx[0],scale_mvy[15:0], scale_mvx[15:0]};
			cand0_sel_onehot[UC] : cand_mv[0][33:0]=cand_c[0] ? {col_ref_idx,col_c[0][0+:32]} : {col_ref_idx,col_c[1][0+:32]};
			cand0_sel_onehot[SC] : cand_mv[0][33:0]={col_ref_idx,scale_mvy[15:0], scale_mvx[15:0]};
			cand0_sel_onehot[MED] : cand_mv[0][33:0]={2'd0, avc_mvpxy};
			default : cand_mv[0][33:0]={cur_ref_idx,32'd0}; // Z0
		endcase
	end

	always@(*) begin
		case(1)
			cand1_sel_onehot[UB] : cand_mv[1][33:0]= cand_b[0] ? neib_b[0] : ( cand_b[1] ? neib_b[1] : neib_b[2] );
			cand1_sel_onehot[SB] : cand_mv[1][33:0]={1'b0,!cur_ref_idx[0],scale_mvy[15:0], scale_mvx[15:0]};
			cand1_sel_onehot[UC] : cand_mv[1][33:0]= cand_c[0] ? {col_ref_idx,col_c[0][0+:32]} : {col_ref_idx,col_c[1][0+:32]};
			cand1_sel_onehot[SC] : cand_mv[1][33:0]={col_ref_idx,scale_mvy[15:0], scale_mvx[15:0]};
			default : cand_mv[1][33:0]={cur_ref_idx,32'd0}; // Z1
		endcase
	end

	// pocdif[41:34]
	always@(*) begin
		//if( cand0_sel_onehot[UC] | cand0_sel_onehot[SC] )
		//  if(cand_c[0] | cand_c[2])
		//      cand_mv[0][41:34]= c0_pocdif;
		//  else
		//      cand_mv[0][41:34]= c1_pocdif;
		//else
			cand_mv[0][41:34]= ref_pocdif;
	end

	always@(*) begin
		//if( cand1_sel_onehot[UC] | cand1_sel_onehot[SC] ) begin
		//  if(cand_c[0] | cand_c[2])
		//      cand_mv[1][41:34]= c0_pocdif;
		//  else
		//      cand_mv[1][41:34]= c1_pocdif;
		//end
		//else
			cand_mv[1][41:34] = ref_pocdif;
	end

	// long[42]
	always@(*) begin
		case(1)
			cand0_sel_onehot[UA] : cand_mv[0][42]= cand_a[0] ? a0_long : a1_long;
			cand0_sel_onehot[SA] : cand_mv[0][42]= cand_a[2] ? a0_long : a1_long;
			cand0_sel_onehot[UB] : cand_mv[0][42]= cand_b[0] ? b0_long : ( cand_b[1] ? b1_long : b2_long );
			cand0_sel_onehot[SB] : cand_mv[0][42]= cand_b[3] ? b0_long : ( cand_b[4] ? b1_long : b2_long );
			cand0_sel_onehot[UC] : cand_mv[0][42]= cand_c[0] ? c0_long : c1_long;
			cand0_sel_onehot[SC] : cand_mv[0][42]= cand_c[2] ? c0_long : c1_long;
			default : cand_mv[0][42]= ref_long;
			//cand0_sel_onehot[Z0] : {2'd0,32'd0};
		endcase
	end

	always@(*) begin
		case(1)
			cand1_sel_onehot[UB] : cand_mv[1][42]= cand_b[0] ? b0_long : ( cand_b[1] ? b1_long : b2_long );
			cand1_sel_onehot[SB] : cand_mv[1][42]= cand_b[3] ? b0_long : ( cand_b[4] ? b1_long : b2_long );
			cand1_sel_onehot[UC] : cand_mv[1][42]= cand_c[0] ? c0_long : c1_long;
			cand1_sel_onehot[SC] : cand_mv[1][42]= cand_c[2] ? c0_long : c1_long;
			default : cand_mv[1][42]= ref_long;
			//cand0_sel_onehot[Z0] : {2'd0,32'd0};
		endcase
	end

	always@(*) begin: avc_median
		integer i;
		reg [1:0][31:0] b_c_mvxy;
		reg [1:0]       a_gt_b;
		reg [1:0]       b_gt_c;
		reg [1:0]       a_gt_c;
		reg [1:0][2:0]  median_sel;
		reg [31:0]      g_neib_a1;

		b_c_avail   = {b0_avail | b2_avail, b1_avail};
		b_c_mvxy    = {b0_avail ? neib_b[0][0+:32] : {32{b2_avail}} & neib_b[2][0+:32], {32{b1_avail}} & neib_b[1][0+:32]};
		g_neib_a1   = {32{a1_avail}} & neib_a[1][31:0];

		a_gt_b      = 0;
		b_gt_c      = 0;
		a_gt_c      = 0;
		median_sel  = 0;
		avc_mvpxy   = 0;

		for(i = 0; i < 2; i++)begin
			a_gt_b[i]   = $signed(g_neib_a1[i*16+:16]) > $signed(b_c_mvxy[0][i*16+:16]);
			b_gt_c[i]   = $signed(b_c_mvxy[0][i*16+:16]) > $signed(b_c_mvxy[1][i*16+:16]);
			a_gt_c[i]   = $signed(g_neib_a1[i*16+:16]) > $signed(b_c_mvxy[1][i*16+:16]);

			median_sel[i][0] =   a_gt_b[i] & ~b_gt_c[i] & ~a_gt_c[i]    | // A
								~a_gt_b[i]            &   a_gt_c[i];
			median_sel[i][1] =   a_gt_b[i] &  b_gt_c[i]                 | // B
								~a_gt_b[i] & ~b_gt_c[i] & ~a_gt_c[i];
			median_sel[i][2] =   a_gt_b[i] & ~b_gt_c[i] &  a_gt_c[i]    | // C
								~a_gt_b[i] &  b_gt_c[i] & ~a_gt_c[i];
			case({b_c_avail, a1_avail})
				3'b000: avc_mvpxy[i]   =   g_neib_a1[i*16+:16];
				3'b010: avc_mvpxy[i]   =   b_c_mvxy[0][i*16+:16];
				3'b100: avc_mvpxy[i]   =   b_c_mvxy[1][i*16+:16];
				default: begin
					case(1) // synopsys parallel_case
						median_sel[i][0]:  avc_mvpxy[i]   =   g_neib_a1[i*16+:16];
						median_sel[i][1]:  avc_mvpxy[i]   =   b_c_mvxy[0][i*16+:16];
						median_sel[i][2]:  avc_mvpxy[i]   =   b_c_mvxy[1][i*16+:16];
					endcase
				end
			endcase
		end
	end

end        // amvp  end
else begin  : merge_output_sel

    assign ua          = |{cand_a[1:0]};
    assign ub          = |{cand_b[2:0]};
    assign uc          = |{cand_c[1:0]};
    assign sc          = |{cand_c[3:2]};
    // scale related
    assign sel_poc_diff = col_poc_diff;

    always@(*) begin
        {mvy_sel,mvx_sel} = cand_c[2] ? c0_mv : c1_mv;
    end

    // long[42],pocdiff[41:34], ref_idx[33:32], mv[31:0]

    // ref_idx[33:32], mv[31:0]
    always@(*) begin
        case(1)
            cand0_sel_onehot[A1] : cand_mv[0][33:0]= neib_a[1];
            cand0_sel_onehot[B1] : cand_mv[0][33:0]= neib_b[1];
            cand0_sel_onehot[B0] : cand_mv[0][33:0]= neib_b[0];
            cand0_sel_onehot[A0] : cand_mv[0][33:0]= neib_a[0];
            cand0_sel_onehot[B2] : cand_mv[0][33:0]= neib_b[2];
            cand0_sel_onehot[UC] : cand_mv[0][33:0]= cand_c[0] ? {col_ref_idx,col_c[0][0+:32]} : {col_ref_idx,col_c[1][0+:32]};
            cand0_sel_onehot[SC] : cand_mv[0][33:0]={col_ref_idx,scale_mvy[15:0], scale_mvx[15:0]};
            default : cand_mv[0][33:0]={2'd0,32'd0}; // Z0
            //cand0_sel_onehot[Z0] : {2'd0,32'd0};
        endcase
    end

	always@(*) begin
		case(1)
			cand1_sel_onehot[B1] : cand_mv[1][33:0]= neib_b[1];
			cand1_sel_onehot[B0] : cand_mv[1][33:0]= neib_b[0];
			cand1_sel_onehot[A0] : cand_mv[1][33:0]= neib_a[0];
			cand1_sel_onehot[B2] : cand_mv[1][33:0]= neib_b[2];
			cand1_sel_onehot[UC] : cand_mv[1][33:0]= cand_c[0] ? {col_ref_idx,col_c[0][0+:32]} : {col_ref_idx,col_c[1][0+:32]};
			cand1_sel_onehot[SC] : cand_mv[1][33:0]={col_ref_idx,scale_mvy[15:0], scale_mvx[15:0]};
			default : cand_mv[1][33:0]={1'd0,reg_num_ref_l0_act_m1[0]&cand0_sel_onehot[Z0],32'd0}; // Z1
			//default : cand_mv[1][33:0]={2'd0,32'd0}; // Z1
		endcase
		//cand0_sel_onehot[Z0] : {2'd0,32'd0};
	end

	// pocdiff[41:34]
	always@(*) begin
		case(1)
			cand0_sel_onehot[A1] : sel_cand0_poc = a1_poc;
			cand0_sel_onehot[B1] : sel_cand0_poc = b1_poc;
			cand0_sel_onehot[B0] : sel_cand0_poc = b0_poc;
			cand0_sel_onehot[A0] : sel_cand0_poc = a0_poc;
			cand0_sel_onehot[B2] : sel_cand0_poc = b2_poc;
			default : sel_cand0_poc = ref_poc[0]; // Z0
			//cand0_sel_onehot[Z0] : {2'd0,32'd0};
		endcase
	end

	always@(*) begin
		//if( cand0_sel_onehot[UC] |cand0_sel_onehot[SC] )
		//  if( cand_c[0] | cand_c[2] )
		//      cand_mv[0][41:34]= c0_pocdif;
		//  else
		//      cand_mv[0][41:34]= c1_pocdif;
		//else
			cand_mv[0][41:34] = poc_diff_clip3(reg_cur_poc, sel_cand0_poc);
	end

	always@(*) begin
		case(1)
			cand1_sel_onehot[B1] : sel_cand1_poc = b1_poc;
			cand1_sel_onehot[B0] : sel_cand1_poc = b0_poc;
			cand1_sel_onehot[A0] : sel_cand1_poc = a0_poc;
			cand1_sel_onehot[B2] : sel_cand1_poc = b2_poc;
			default : sel_cand1_poc = sel_poc; // Z1
			//cand0_sel_onehot[Z0] : {2'd0,32'd0};
		endcase
	end

	always@(*) begin
		//if( cand1_sel_onehot[UC] |cand1_sel_onehot[SC] )
		//  if( cand_c[0] | cand_c[2] )
		//      cand_mv[1][41:34] = c0_pocdif;
		//  else
		//      cand_mv[1][41:34] = c1_pocdif;
		//else
			cand_mv[1][41:34] = poc_diff_clip3(reg_cur_poc, sel_cand1_poc);
	end

	// long[42]
	always@(*) begin
		case(1)
			cand0_sel_onehot[A1] : cand_mv[0][42]= a1_long;
			cand0_sel_onehot[B1] : cand_mv[0][42]= b1_long;
			cand0_sel_onehot[B0] : cand_mv[0][42]= b0_long;
			cand0_sel_onehot[A0] : cand_mv[0][42]= a0_long;
			cand0_sel_onehot[UC] : cand_mv[0][42]= cand_c[0] ? c0_long : c1_long;
			cand0_sel_onehot[SC] : cand_mv[0][42]= cand_c[2] ? c0_long : c1_long;
			default : cand_mv[0][42]= ref_long;
			//cand0_sel_onehot[Z0] : {2'd0,32'd0};
		endcase
	end

	always@(*) begin
		case(1)
			cand1_sel_onehot[B1] : cand_mv[1][42]= b1_long;
			cand1_sel_onehot[B0] : cand_mv[1][42]= b0_long;
			cand1_sel_onehot[A0] : cand_mv[1][42]= a0_long;
			cand1_sel_onehot[B2] : cand_mv[1][42]= b2_long;
			cand1_sel_onehot[UC] : cand_mv[1][42]= cand_c[0] ? c0_long : c1_long;
			cand1_sel_onehot[SC] : cand_mv[1][42]= cand_c[2] ? c0_long : c1_long;
			default : cand_mv[1][42]= ref_long;
			//cand0_sel_onehot[Z0] : {2'd0,32'd0};
		endcase
	end

end
endgenerate

generate
    if( AMVP_OR_MRG ==0 & NUM_REF==2) begin : mrg_poc_numref_eq2   // merge
        assign sel_poc = cand0_sel_onehot[Z0] ? ref_poc[1] : ref_poc[0];
    end
    else if( AMVP_OR_MRG ==0 & NUM_REF==1 ) begin : mrg_poc_numref_eq1
        assign sel_poc = ref_poc[0];
    end
endgenerate

assign cand_rdy[0] = |cand0_sel_onehot;
assign cand_rdy[1] = |cand1_sel_onehot;

// function/task

function signed [7:0] poc_diff_clip3; // clip -128~127
    input [31:0]    poc_in_0;
    input [31:0]    poc_in_1;
    //------------------------------------
    reg signed[32:0]    poc_diff;
    begin
        poc_diff = $signed(poc_in_0) - $signed(poc_in_1);

        if( poc_diff < -128 ) // < -128, msb=1 and bit[31:7] exist "one 0"
            poc_diff_clip3 = -8'd128; // =-128
        else if( poc_diff > 127 )
            poc_diff_clip3 = 8'd127;
        else
            poc_diff_clip3 = poc_diff[7:0];
    end
endfunction

// instantiation

generate
    if(MVP_SCALE_EN) begin : mvp_scale_en

vc_mvp_scale
#( .MULCYC  (4) )
U_VC_SCALE_CAL(
    // Output
    .scale_done    ( scale_done),
    .scale_mvx     ( scale_mvx),
    .scale_mvy     ( scale_mvy),
    // Input
    .clk_vc        ( clk_vc),
    .vc_rst_z      ( vc_rst_z),
    .reg_slice_go  ( reg_slice_go),
    .scale_start   ( scale_start),
    .n_mvx         ( mvx_sel),
    .n_mvy         ( mvy_sel),
    //.reg_cur_poc    (reg_cur_poc),  // current pic poc
    //.cur_ref_poc    (ref_poc),      // current ref pic poc
    .n_cur_poc_diff ( n_cur_poc_diff),
    .n_col_poc_diff ( sel_poc_diff) // collocated poc diff or neib poc diff
);

end
else begin : mvp_scale_dis

assign scale_done= 0;
assign scale_mvx = 0;
assign scale_mvy = 0;

end

endgenerate

	vc_mvp_cand_prior
	#(
		.AMVP_OR_MRG (AMVP_OR_MRG),
		.MVP_SCALE_EN (MVP_SCALE_EN)
	)
	U_VC_MVP_CAND_PRIOR
	(
    // output
    .cand_a         (cand_a),
    .cand_b         (cand_b),
    .cand_c         (cand_c),
    // input
    .a0_avail       (a0_avail),
    .a1_avail       (a1_avail),
    .b0_avail       (b0_avail),
    .b1_avail       (b1_avail),
    .b2_avail       (b2_avail),
    .c0_avail       (c0_avail),
    .c1_avail       (c1_avail),
    .reg_tmp_mvp_flag (reg_tmp_mvp_flag),
    .reg_avc_mode   (reg_avc_mode),
    .cur_pocdif     (n_cur_poc_diff),
    .ref_poc        (cur_ref_poc),
    .ref_long       (ref_long),
    .a0_long        (a0_long),
    .a1_long        (a1_long),
    .b0_long        (b0_long),
    .b1_long        (b1_long),
    .b2_long        (b2_long),
    .a0_poc         (a0_poc),
    .a1_poc         (a1_poc),
    .b0_poc         (b0_poc),
    .b1_poc         (b1_poc),
    .b2_poc         (b2_poc),
    .c0_pocdif      (c0_pocdif),
    .c0_intra       (c0_intra),
    .c0_long        (c0_long),
    .c1_pocdif      (c1_pocdif),
    .c1_intra       (c1_intra),
	.c1_long	        (c1_long)
	);

// state machine

// a1	
// b1	, (!a1 | a1_b1_diff)
// b0	, (!b1 | b1_b0_diff)
// a0	, (!a1 | a1_a0_diff)
// ---- at least one of above not avail then b2 
// b2	, (!a1 | a1_b2_diff) & (!b1 | b1_b2_diff)

generate

if(AMVP_OR_MRG == 0) begin : merge_cand_prior

    assign mv_a1_b1_diff = neib_a[1] != neib_b[1];
    assign mv_a1_b2_diff = neib_a[1] != neib_b[2];
    assign mv_a1_a0_diff = neib_a[1] != neib_a[0];
    assign mv_b1_b0_diff = neib_b[1] != neib_b[0];
    assign mv_b1_b2_diff = neib_b[1] != neib_b[2];

    wire b1_con = cand_b[1] & (!cand_a[1] | mv_a1_b1_diff);
    wire b0_con = cand_b[0] & (!cand_b[1] | mv_b1_b0_diff);
    wire a0_con = cand_a[0] & (!cand_a[1] | mv_a1_a0_diff);
    wire b2_con = cand_b[2] & (!cand_a[1] | mv_a1_b2_diff) & (!cand_b[1] | mv_b1_b2_diff);

    always@(*) begin : fsm_mrg_cand_gen
        fsm_cand_ns = 0;
        case(1)
            fsm_cand_cs[CAND_IDLE]: begin
                if(cand_cu_start) begin
                    if( cand_a[1] ) begin
                        if(b1_con)          // a1 + b1
                            fsm_cand_ns[CAND_DONE] = 1;
                        else if(b0_con)     // a1 + b0
                            fsm_cand_ns[CAND_DONE] = 1;
                        else if(a0_con)     // a1 + a0
                            fsm_cand_ns[CAND_DONE] = 1;
                        else if(b2_con)     // a1 + b2
                            fsm_cand_ns[CAND_DONE] = 1;
                        else if( uc )       // a1 + uc
                            fsm_cand_ns[CAND_DONE] = 1;
                        else if( sc ) begin // a1 + sc
                            if(mrg_cand_nr_m1==0)
                                fsm_cand_ns[CAND_DONE] = 1; // one cand only
                            else
                                fsm_cand_ns[CAND_WAIT_SCALE_C] = 1;
                        end
                        else                // a1 + z
                            fsm_cand_ns[CAND_DONE] = 1;
                    end
                    else if(cand_b[1]) begin
                        if(b0_con)          // b1 + b0
                            fsm_cand_ns[CAND_DONE] = 1;
                        else if(cand_a[0])  // b1 + a0
                            fsm_cand_ns[CAND_DONE] = 1;
                        else if(b2_con)     // b1 + b2
                            fsm_cand_ns[CAND_DONE] = 1;
                        else if(uc)         // b1 + uc
                            fsm_cand_ns[CAND_DONE] = 1;
                        else if(sc) begin   // b1 + sc
                            if(mrg_cand_nr_m1==0)
                                fsm_cand_ns[CAND_DONE] = 1; // one cand only
                            else
                                fsm_cand_ns[CAND_WAIT_SCALE_C] = 1;
                        end
                        else                // b1 + z
                            fsm_cand_ns[CAND_DONE] = 1;
                    end
                    else if(cand_b[0]) begin
                        if(cand_a[0])       // b0 + a0
                            fsm_cand_ns[CAND_DONE] = 1;
                        else if(cand_b[2])  // b0 + b2
                            fsm_cand_ns[CAND_DONE] = 1;
                        else if(uc)         // b0 + uc
                            fsm_cand_ns[CAND_DONE] = 1;
                        else if(sc) begin   // b0 + sc
                            if(mrg_cand_nr_m1==0)
                                fsm_cand_ns[CAND_DONE] = 1; // one cand only
                            else
                                fsm_cand_ns[CAND_WAIT_SCALE_C] = 1;
                        end
                        else                // b0 + z
                            fsm_cand_ns[CAND_DONE] = 1;
                    end
                    else if(cand_a[0]) begin
                        if(cand_b[2])       // a0 + b2
                            fsm_cand_ns[CAND_DONE] = 1;
                        else if(uc)         // a0 + uc
                            fsm_cand_ns[CAND_DONE] = 1;
                        else if(sc) begin   // a0 + sc
                            if(mrg_cand_nr_m1==0)
                                fsm_cand_ns[CAND_DONE] = 1; // one cand only
                            else
                                fsm_cand_ns[CAND_WAIT_SCALE_C] = 1;
                        end
                        else                // a0 + z
                            fsm_cand_ns[CAND_DONE] = 1;
                    end
                    else if(cand_b[2]) begin
                        if(uc)              // b2 + uc
                            fsm_cand_ns[CAND_DONE] = 1;
                        else if(sc) begin   // b2 + sc
                            if(mrg_cand_nr_m1==0)
                                fsm_cand_ns[CAND_DONE] = 1; // one cand only
                            else
                                fsm_cand_ns[CAND_WAIT_SCALE_C] = 1;
                        end
                        else                // b2 + z
                            fsm_cand_ns[CAND_DONE] = 1;
                    end
                    else if(uc) begin       // uc + z
                        fsm_cand_ns[CAND_DONE] = 1;
                    end
                    else if(sc) begin       // sc + z
                        fsm_cand_ns[CAND_WAIT_SCALE_C] = 1;
                    end
                    else begin              // z + z
                        fsm_cand_ns[CAND_DONE] = 1;
                    end
                end
                else begin
                    fsm_cand_ns[CAND_IDLE] = 1;
                end
            end
            fsm_cand_cs[CAND_WAIT_SCALE_C]: begin
                if( scale_done ) begin
                    fsm_cand_ns[CAND_DONE] = 1;
                    /*
                    if(cand_num==1) // (a or b) + sc
                        fsm_cand_ns[CAND_DONE] = 1;
                    else            // sc + z
                        fsm_cand_ns[CAND_DONE] = 1;
                    */
                end
                else begin
                    fsm_cand_ns[CAND_WAIT_SCALE_C] = 1;
                end
            end           
            fsm_cand_cs[CAND_DONE] : begin
                fsm_cand_ns[CAND_IDLE] = 1;
            end
        endcase
    end

    // cand0_sel_onehot[7:0]
    // cand1_sel_onehot[7:0]
    // 0   1   2   3   4   5   6   7
    // a1  b1  b0  a0  b2  uc  sc  zo

	always@(*) begin
		cand0_sel_onehot = 0;
		cand1_sel_onehot = 0;
		case(1)
			fsm_cand_cs[CAND_IDLE]: begin
				if(cand_cu_start) begin
					if( cand_a[1] ) begin
						cand0_sel_onehot[A1] = 1;
						if(b1_con) // a1 + b1
							cand1_sel_onehot[B1] = 1;
						else if(b0_con) // a1 + b0
							cand1_sel_onehot[B0] = 1;
						else if(a0_con) // a1 + a0
							cand1_sel_onehot[A0] = 1;
						else if(b2_con) // a1 + b2
							cand1_sel_onehot[B2] = 1;
						else if( uc )   // a1 + uc
							cand1_sel_onehot[UC] = 1;
						else if( sc )   // a1 + sc
							cand1_sel_onehot = 0;
						else            // a1 + z
							cand1_sel_onehot[Z0] = 1;
					end
					else if(cand_b[1]) begin
						cand0_sel_onehot[B1] = 1;
						if(b0_con) // b1 + b0
							cand1_sel_onehot[B0] = 1;
						else if(cand_a[0]) // b1 + a0
							cand1_sel_onehot[A0] = 1;
						else if(b2_con) // b1 + b2
							cand1_sel_onehot[B2] = 1;
						else if( uc )   // b1 + uc
							cand1_sel_onehot[UC] = 1;
						else if( sc )   // b1 + sc
							cand1_sel_onehot = 0;
						else            // b1 + z
							cand1_sel_onehot[Z0] = 1;
					end
					else if(cand_b[0]) begin
						cand0_sel_onehot[B0] = 1;
						if(cand_a[0])       // b0 + a0
							cand1_sel_onehot[A0] = 1;
						else if(cand_b[2])  // b0 + b2
							cand1_sel_onehot[B2] = 1;
						else if(uc)         // b0 + uc
							cand1_sel_onehot[UC] = 1;
						else if(sc)         // b0 + sc
							cand1_sel_onehot = 0;
						else                // b0 + z
							cand1_sel_onehot[Z0] = 1;
					end
					else if(cand_a[0]) begin
						cand0_sel_onehot[A0] = 1;
						if(cand_b[2])       // a0 + b2
							cand1_sel_onehot[B2] = 1;
						else if(uc)         // a0 + uc
							cand1_sel_onehot[UC] = 1;
						else if(sc)         // a0 + sc
							cand1_sel_onehot = 0;
						else                // a0 + z
							cand1_sel_onehot[Z0] = 1;
					end
					else if(cand_b[2]) begin
						cand0_sel_onehot[B2] = 1;
						if(uc)              // b2 + uc
							cand1_sel_onehot[UC] = 1;
						else if(sc)         // b2 + sc
							cand1_sel_onehot = 0;
						else                // b2 + z
							cand1_sel_onehot[Z0] = 1;
					end
					else if(uc) begin       // uc + z
						cand0_sel_onehot[UC] = 1;
						cand1_sel_onehot[Z0] = 1;
					end
					else if(sc) begin       // sc + z
						cand0_sel_onehot = 0;
						cand1_sel_onehot = 0;
					end
					else begin              // z + z
						cand0_sel_onehot[Z0] = 1;
						cand1_sel_onehot[Z0] = 1;
					end
				end
			end
			
			fsm_cand_cs[CAND_WAIT_SCALE_C]: begin
				if( scale_done ) begin
					if(cand_num==1) // (a or b) + sc
						cand1_sel_onehot[SC] = 1;
					else            // sc + z
						cand0_sel_onehot[SC] = 1;
						cand1_sel_onehot[Z0] = 1;
					end
				end
		endcase
	end

	// cand_num_inc
	// cand_num_rst
	always@(*) begin
		cand_num_inc = 0;
		cand_num_rst = 0;
		case(1)
			fsm_cand_cs[CAND_IDLE]: begin
				if(cand_cu_start) begin
					if( cand_a[1] ) begin
						if(b1_con) // a1 + b1
							cand_num_inc = 0;
						else if(b0_con) // a1 + b0
							cand_num_inc = 0;
						else if(a0_con) // a1 + a0
							cand_num_inc = 0;
						else if(b2_con) // a1 + b2
							cand_num_inc = 0;
						else if( uc )   // a1 + uc
							cand_num_inc = 0;
						else if( sc ) begin
							if(mrg_cand_nr_m1==0)
								cand_num_inc = 0;
							else
								cand_num_inc = 1;
						end
					end
					else if(cand_b[1]) begin
						if(b0_con) // b1 + b0
							cand_num_inc = 0;
						else if(cand_a[0]) // b1 + a0
							cand_num_inc = 0;
						else if(b2_con) // b1 + b2
							cand_num_inc = 0;
						else if( uc )   // b1 + uc
							cand_num_inc = 0;
						else if( sc ) begin // b1 + sc
							if(mrg_cand_nr_m1==0)
								cand_num_inc = 0;
							else
								cand_num_inc = 1;
						end
					end
					else if(cand_b[0]) begin
						if(cand_a[0])       // b0 + a0
							cand_num_inc = 0;
						else if(cand_b[2])  // b0 + b2
							cand_num_inc = 0;
						else if(uc)         // b0 + uc
							cand_num_inc = 0;
						else if(sc) begin
							if(mrg_cand_nr_m1==0)
								cand_num_inc = 0;
							else
								cand_num_inc = 1;
						end
					end
					else if(cand_a[0]) begin
						if(cand_b[2])       // a0 + b2
							cand_num_inc = 0;
						else if(uc)         // a0 + uc
							cand_num_inc = 0;
						else if(sc) begin
							if(mrg_cand_nr_m1==0)
								cand_num_inc = 0;
							else
								cand_num_inc = 1;
						end
					end
					else if(cand_b[2]) begin
						if(uc)              // b2 + uc
							cand_num_inc = 0;
						else if(sc) begin
							if(mrg_cand_nr_m1==0)
								cand_num_inc = 0;
							else
								cand_num_inc = 1;
						end
					end
				end
			end			
			fsm_cand_cs[CAND_WAIT_SCALE_C]: begin
				if( scale_done ) begin
					cand_num_rst = 1;
					/*
					if(cand_num==1) // (a or b) + sc
						fsm_cand_ns[CAND_DONE] = 1;
					else            // sc + z
						fsm_cand_ns[CAND_DONE] = 1;
					*/
				end
			end
		endcase
	end

	// scale_start
	always@(*) begin
		scale_start = 0;
		case(1)
			fsm_cand_cs[CAND_IDLE]: begin
				if(cand_cu_start) begin
					if( cand_a[1] ) begin
						if(b1_con) // a1 + b1
							scale_start = 0;
						else if(b0_con) // a1 + b0
							scale_start = 0;
						else if(a0_con) // a1 + a0
							scale_start = 0;
						else if(b2_con) // a1 + b2
							scale_start = 0;
						else if( sc ) begin
							if(mrg_cand_nr_m1==0)
								scale_start = 0;
							else
								scale_start = 1;
						end
					end
					else if(cand_b[1]) begin
						if(b0_con) // b1 + b0
							scale_start = 0;
						else if(cand_a[0]) // b1 + a0
							scale_start = 0;
						else if(b2_con) // b1 + b2
							scale_start = 0;
						else if( sc ) begin // b1 + sc
							if(mrg_cand_nr_m1==0)
								scale_start = 0;
							else
								scale_start = 1;
						end
					end
					else if(cand_b[0]) begin
						if(cand_a[0])       // b0 + a0
							scale_start = 0;
						else if(cand_b[2])  // b0 + b2
							scale_start = 0;
						else if(sc) begin
							if(mrg_cand_nr_m1==0)
								scale_start = 0;
							else
								scale_start = 1;
						end
					end
					else if(cand_a[0]) begin
						if(cand_b[2])       // a0 + b2
							scale_start = 0;
						else if(sc) begin
							if(mrg_cand_nr_m1==0)
								scale_start = 0;
							else
								scale_start = 1;
						end
					end
					else if(cand_b[2]) begin
						if(sc)
							scale_start = 1;
					end
					else if(sc) begin
						if(mrg_cand_nr_m1==0)
							scale_start = 0;
						else
							scale_start = 1;
					end
				end
			end
		endcase
	end
end // MRG end	

else begin : amvp_cand_prior

    always@(*) begin : fsm_amvp_cand_gen
        fsm_cand_ns = 0;
        case(1)
            fsm_cand_cs[CAND_IDLE]: begin
                if(cand_cu_start) begin
                    if( cand_ua_ub_con | reg_avc_mode) begin // ua + ub
                        fsm_cand_ns[CAND_DONE] = 1;
                    end
                    else if( ua ) begin
                        if( uc ) // ua + uc
                            fsm_cand_ns[CAND_DONE] = 1;
                        else if( sc )
                            fsm_cand_ns[CAND_WAIT_SCALE_C] = 1;
                        else // ua + z
                            fsm_cand_ns[CAND_DONE] = 1;
                    end
                    else if( sa ) begin
                        fsm_cand_ns[CAND_WAIT_SCALE_A] = 1;
                    end
                    else if( ub ) begin
                        if(sb) begin
                            if(sb_chk_uscale_con) begin
                                if(uc) // ub + uc
                                    fsm_cand_ns[CAND_DONE] = 1;
                                else if(sc)
                                    fsm_cand_ns[CAND_WAIT_SCALE_C] = 1;
                                else // z
                                    fsm_cand_ns[CAND_DONE] = 1;
                            end
                            else begin
                                fsm_cand_ns[CAND_WAIT_SCALE_B] = 1;
                            end
                        end
                        else if( uc ) // ub + uc
                            fsm_cand_ns[CAND_DONE] = 1;
                        else if( sc )
                            fsm_cand_ns[CAND_WAIT_SCALE_C] = 1;
                        else // ub + z
                            fsm_cand_ns[CAND_DONE] = 1;
                    end
                    else if( sb ) begin // cand_a == 0
                        fsm_cand_ns[CAND_WAIT_SCALE_B] = 1;
                    end// 
					else if( uc ) begin// uc + z
                        fsm_cand_ns[CAND_DONE] = 1;
                    end
                    else if( sc ) begin
                        fsm_cand_ns[CAND_WAIT_SCALE_C] = 1;
                    end
                    else begin // z + z
                        fsm_cand_ns[CAND_DONE] = 1;
                    end
                end
                else
                    fsm_cand_ns[CAND_IDLE] = 1;
            end

            fsm_cand_cs[CAND_WAIT_SCALE_A]: begin
                if( scale_done ) begin
                    if( ub & mva_neq_mvb ) // sa + ub
                        fsm_cand_ns[CAND_DONE] = 1;
                    else if( uc ) // sa + uc
                        fsm_cand_ns[CAND_DONE] = 1;
                    else if( sc )
                        fsm_cand_ns[CAND_WAIT_SCALE_C] = 1;
                    else // sa + z
                        fsm_cand_ns[CAND_DONE] = 1;
                end
                else
                    fsm_cand_ns[CAND_WAIT_SCALE_A] = 1;
            end

            fsm_cand_cs[CAND_WAIT_SCALE_B]: begin
                if( scale_done ) begin
                    if(cand_num==1 & (!cand_b[2:0]) & mvb_neq_mvb) // ub + sb
                        fsm_cand_ns[CAND_DONE] = 1;
                    else if( cand_num == 1 & |cand_b[2:0] ) begin // ub + ?
                        if(uc)
                            fsm_cand_ns[CAND_DONE] = 1; // ub + uc
                        else if(sc)
                            fsm_cand_ns[CAND_WAIT_SCALE_C] = 1; // ub + sc
                        else
                            fsm_cand_ns[CAND_DONE] = 1; // ub + z
                    end
                    else if( uc ) // sb + uc
                        fsm_cand_ns[CAND_DONE] = 1;
                    else if( sc )
                        fsm_cand_ns[CAND_WAIT_SCALE_C] = 1;
                    else // sb + z
                        fsm_cand_ns[CAND_DONE] = 1;
                end
                else
                    fsm_cand_ns[CAND_WAIT_SCALE_B] = 1;
            end

            fsm_cand_cs[CAND_WAIT_SCALE_C]: begin
                if( scale_done )
                    fsm_cand_ns[CAND_DONE] = 1;
                    /*
                    if(cand_num==1) // (a or b) + sc
                        fsm_cand_ns[CAND_DONE] = 1;
                    else  // sc + z
                        fsm_cand_ns[CAND_DONE] = 1; */
                else
                    fsm_cand_ns[CAND_WAIT_SCALE_C] = 1;
            end

            fsm_cand_cs[CAND_DONE]: begin
                fsm_cand_ns[CAND_IDLE] = 1;
            end
        endcase
    end

    // cand0_sel_onehot[7:0]
    // cand1_sel_onehot[7:0]
    // 0   1   2   3   4   5   6   7
	// ua  sa  ub  sb  uc  sc  z0  z1
	always@(*) begin
		cand0_sel_onehot = 0;
		cand1_sel_onehot = 0;
		case(1)
			fsm_cand_cs[CAND_IDLE]: begin
				if(cand_cu_start) begin
					if( cand_ua_ub_con | reg_avc_mode) begin // ua + ub
						if(reg_avc_mode ? {a1_avail, b_c_avail} == {1'b1, 2'd0} : 1'b1)
							cand0_sel_onehot[UA] = 1;
						else if({a1_avail, b_c_avail} == 0)
							cand0_sel_onehot[Z0] = 1;
						else
							cand0_sel_onehot[MED] = 1;
						cand1_sel_onehot[UB] = 1;
					end
					else if( ua ) begin
						cand0_sel_onehot[UA] = 1;
						if( uc ) // ua + uc
							cand1_sel_onehot[UC] = 1;
						else if( sc )
							cand1_sel_onehot = 0;
						else
							cand1_sel_onehot[Z0] = 1;
					end
					else if( sa ) begin
						cand0_sel_onehot = 0;
						cand1_sel_onehot = 0;
					end
					else if( ub ) begin
						cand0_sel_onehot[UB] = 1;
						if( sb ) begin
							if(sb_chk_uscale_con) begin
								if(uc)
									cand1_sel_onehot[UC] = 1;
								else if(sc)
									cand1_sel_onehot = 0;
								else
									cand1_sel_onehot[Z0] = 1;
							end
							else begin
								cand1_sel_onehot = 0;
							end
						end
						else if( uc ) // ub + uc
							cand1_sel_onehot[UC] = 1;
						else if( sc )
							cand1_sel_onehot = 0;
						else
							cand1_sel_onehot[Z0] = 1;
					end
					else if( sb ) begin
						cand0_sel_onehot = 0;
						cand1_sel_onehot = 0;
					end
					else if( uc ) begin // uc + z
						cand0_sel_onehot[UC] = 1;
						cand1_sel_onehot[Z0] = 1;
					end
					else if( sc ) begin
						cand0_sel_onehot = 0;
						cand1_sel_onehot = 0;
					end
					else begin // z + z
						cand0_sel_onehot[Z0] = 1;
						cand1_sel_onehot[Z0] = 1;
					end
				end
			end

			fsm_cand_cs[CAND_WAIT_SCALE_A]: begin
				if( scale_done ) begin
					cand0_sel_onehot[SA] = 1;
					if( ub & mva_neq_mvb ) // sa + ub
						cand1_sel_onehot[UB] = 1;
					else if( uc ) // sa + uc
						cand1_sel_onehot[UC] = 1;
					else if( sc )
						cand1_sel_onehot = 0;
					else // sa + z
						cand1_sel_onehot[Z0] = 1;
				end
			end

			fsm_cand_cs[CAND_WAIT_SCALE_B]: begin // continue
				if( scale_done ) begin
					if(cand_num==1 & !cand_b[2:0] & mvb_neq_mvb) // ub + sb
						cand1_sel_onehot[SB] = 1;
					else if( cand_num==1 & |cand_b[2:0] ) begin // ub + ?
						cand0_sel_onehot = 0;
						if(uc)
							cand1_sel_onehot[UC] = 1; // ub
						else if(sc)
							cand0_sel_onehot = 0;
						else
							cand1_sel_onehot[Z0] = 1;
					end
					else if( uc ) begin // sb + uc
						cand0_sel_onehot[SB] = 1;
						cand1_sel_onehot[UC] = 1;
					end
					else if( sc ) begin
						cand0_sel_onehot[SB] = 1;
					end
					else begin // sb + z
						cand0_sel_onehot[SB] = 1;
						cand1_sel_onehot[Z0] = 1;
					end
				end
			end

			fsm_cand_cs[CAND_WAIT_SCALE_C]: begin
				if( scale_done ) begin
					if(cand_num==1) // (a or b) + sc
						cand1_sel_onehot[SC] = 1;
					else begin  // sc + z
						cand0_sel_onehot[SC] = 1;
						cand1_sel_onehot[Z0] = 1;
					end
				end
			end
		endcase
		if(reg_avc_mode)    cand1_sel_onehot    =   0;
	end

	// neib_sel_onehot
	// 0   1   2   3   4
	// a0  a1  b0  b1  b1
	// sel for poc (scale also)
	always@(*) begin
		neib_sel_onehot = 0;
		case(1)
			fsm_cand_cs[CAND_IDLE]: begin
				if(cand_cu_start) begin
					if( sa )
						neib_sel_onehot[1:0] = cand_a[3:2];
					else if( sb ) begin
						neib_sel_onehot[4:2] = cand_b[5:3];
					end
				end
			end
			fsm_cand_cs[CAND_WAIT_SCALE_A]: begin
				neib_sel_onehot[1:0] = cand_a[3:2];
				if( scale_done )
					if( sb )
						neib_sel_onehot[4:2] = cand_b[5:3];
			end
			fsm_cand_cs[CAND_WAIT_SCALE_B]: begin
				neib_sel_onehot[4:2] = cand_b[5:3];
			end
		endcase
	end

	// mv_sel_onehot
	// 0   1   2   3   4   5   6
	// a0  a1  b0  b1  b2  c0  c1
	// sel for scaling
	always@(*) begin
		mv_sel_onehot = 0;
		case(1)
			fsm_cand_cs[CAND_IDLE]: begin
				if(cand_cu_start) begin
					if( ua ) begin
						if( sc )
							mv_sel_onehot[6:5] = cand_c[3:2];
					end
					else if( sa )
						mv_sel_onehot[1:0] = cand_a[3:2];
					else if( ub ) begin
						if(sb) begin
							if(sb_chk_uscale_con) begin
								if(sc) begin
									mv_sel_onehot[6:5] = cand_c[3:2];
								end
							end
							else begin
								mv_sel_onehot[4:2] = cand_b[5:3];
							end
						end
						else if( sc )
							mv_sel_onehot[6:5] = cand_c[3:2];
					end
					else if( sb )
						mv_sel_onehot[4:2] = cand_b[5:3];
					else if( sc )
						mv_sel_onehot[6:5] = cand_c[3:2];
				end
			end

			fsm_cand_cs[CAND_WAIT_SCALE_A]: begin
				if( scale_done )
					if( sc )
						mv_sel_onehot[6:5] = cand_c[3:2];
			end

			fsm_cand_cs[CAND_WAIT_SCALE_B]: begin
				if( scale_done )
					if( sc )
						mv_sel_onehot[6:5] = cand_c[3:2];
			end
		endcase
	end

	// cand_num_inc
	// cand_num_rst
	always@(*) begin
		cand_num_inc = 0;
		cand_num_rst = 0;
		case(1)
			fsm_cand_cs[CAND_IDLE]: begin
				if(cand_cu_start) begin
					if( cand_ua_ub_con ) begin
						cand_num_inc = 0;
					end
					else if( ua ) begin
						if( sc )
							cand_num_inc = 1;
					end
					else if( sa ) begin
						cand_num_inc = 0;
					end
					else if( ub ) begin
						if( sb )begin
							if(sb_chk_uscale_con) begin
								if(uc)
									cand_num_inc = 0;
								else if(sc)
									cand_num_inc = 1;
								else
									cand_num_inc = 0;
							end
							else begin
								cand_num_inc = 1;
							end
						end
						else if( uc ) // ub + uc
							cand_num_inc = 0;
						else if( sc ) // ub + sc
							cand_num_inc = 1;
					end
				end
			end

			fsm_cand_cs[CAND_WAIT_SCALE_A]: begin
				if( scale_done )
					if(ub & mva_neq_mvb)
						cand_num_inc = 0;
					else if( sb )
						cand_num_inc = 1;
					else if( sc )
						cand_num_inc = 1;
			end

			fsm_cand_cs[CAND_WAIT_SCALE_B]: begin
				if( scale_done )
					if(cand_num==1 & (!cand_b[2:0]) & mvb_neq_mvb) // ub + sb
						cand_num_rst = 1;
					else if( cand_num==1 & !cand_b[2:0] )  // ub + ?
						if(uc)
							cand_num_rst = 1; // ub + uc
						else if(sc)
							cand_num_inc = 0; // ub + sc
						else
							cand_num_rst = 1; // ub + z
					else if(uc)
						cand_num_inc = 0;
					else if(sc)
						cand_num_inc = 1;
			end

			fsm_cand_cs[CAND_WAIT_SCALE_C]: begin
				if( scale_done )
					if(cand_num==1) // (a or b) + sc
						cand_num_rst = 1;
			end
		endcase
	end	

	// scale_start
	always@(*) begin
		scale_start = 0;
		case(1)
			fsm_cand_cs[CAND_IDLE]: begin
				if(cand_cu_start) begin
					if(cand_ua_ub_con)
						scale_start = 0;
					else if( ua ) begin
						if( uc )
							scale_start = 0;
						else if( sc )
							scale_start = 1;
					end
					else if( sa )
						scale_start = 1;
					else if( ub ) begin
						if( sb )
							scale_start = 1;
						else if( uc )
							scale_start = 0;
						else if( sc )
							scale_start = 1;
					end
					else if( sb )
						scale_start = 1;
					else if( uc )
						scale_start = 0;
					else if( sc )
						scale_start = 1;
				end
			end

			fsm_cand_cs[CAND_WAIT_SCALE_A]: begin
				if( scale_done ) begin
					if( ub & mva_neq_mvb ) // sa + ub
						scale_start = 0;
					else if( uc ) // sa + uc
						scale_start = 0;
					else if( sc )
						scale_start = 1;
				end
			end

			fsm_cand_cs[CAND_WAIT_SCALE_B]: begin
				if( scale_done )
					if(cand_num==1 & (!cand_b[2:0]) & mvb_neq_mvb) // ub + sb
						scale_start = 0;
					else if( cand_num==1 & (!cand_b[2:0]) ) begin // ub + ?
						if( uc )
							scale_start = 0;
						else if(sc)
							scale_start = 1;
					end
					else if(uc)
						scale_start = 0;
					else if( sc )
						scale_start = 1;
				end
			
		endcase
	end

end // AMVP end
endgenerate

// sequence logic

always@(posedge clk_vc or negedge vc_rst_z)begin
    if(~vc_rst_z) begin
        cand_num <= 0;
    end
    else if( cand_num_rst | reg_slice_go )begin
        cand_num <= 0;
    end
    else if( ~reg_avc_mode & cand_num_inc )begin
        cand_num <= 1;
    end
end

always@(posedge clk_vc or negedge vc_rst_z)begin
    if(~vc_rst_z) begin
        fsm_cand_cs <= 1;
    end
    else if( reg_slice_go ) begin
        fsm_cand_cs <= 1;
    end
    else if( fsm_cand_cs != fsm_cand_ns )begin
        fsm_cand_cs <= fsm_cand_ns;
    end
end


endmodule
