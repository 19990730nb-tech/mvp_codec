`include "ve_defines.v"
module ve_mvp_top
#(
    parameter   VC_PIC_X_NB = 12,
	parameter   VC_PIC_Y_NB = 12,
	parameter	VC_CTU_X_NB	= 7,
	parameter	VC_CTU_Y_NB	= 7,
    parameter	VC_CU_X_NB	= 9,
	parameter	VC_CU_Y_NB	= 9,
	parameter	VC_EN_BI_DIR = 0,
	parameter	NUM_REF = 2,
    parameter	MVP_SCALE_EN = 1,
	parameter	MUL_REF = (NUM_REF > 1),
	parameter	MAX_BLK_SZ = 2, // 3:blk32, 2:blk16
	parameter	VC_SATD_NB = 16, 
	parameter	VC_SSE_NB = 26, 
    parameter	VC_MRG_NB = VC_SATD_NB + VC_SSE_NB,
	parameter	MRG2MC_DW = VC_PIC_X_NB + VC_PIC_Y_NB + 39, // ypos(VC_PIC_X_NB), xpos(VC_PIC_Y_NB), vsx(2)+hsz(2)+ cand_idxp(1) +refidx(2)+mvy(16)+mvx(16) = 39
	parameter	MRG2CCU_DW 	= (8+8+46+VC_SATD_NB +1   // luma + chroma (+1),
								     +VC_SSE_NB  +1 ),// luma + chroma (+1), 
	parameter	AMVP2CCU_DW = (8+78),
    parameter	FME_BLK8_CMDQ_DEPTH =   8,
	parameter	FME_BLK16_CMDQ_DEPTH=   3
)
(
// output

// read neib
output						irpu2neib_b_req,
output[ 4:0]				irpu2neib_b_addr,
output						irpu2neib_a_req,
output[ 1:0]				irpu2neib_a_addr,
output						irpu2col_req,
output[ 4:0]				irpu2col_addr,
output						irpu2ref_req,
output[3+VC_EN_BI_DIR:0]	irpu2ref_addr,
// FME
output[1:0]					amvp2fme_cand_ack,
// MC
output[2:0]					mrg2mc_cand_rdy,
output[2:0][MRG2MC_DW-1:0]	mrg2mc_cand_data,
output[2:0]                 mrg2mc_cand_nb,
output[2:0]					mrg2mc_cost_ack,
// CCU
output[ 2:0]				irpu_amvp_rdy,
output[2:0][AMVP2CCU_DW-1:0]irpu_amvp_rd,
output[ 2:0]				irpu_mrg_rdy,
output[2:0][MRG2CCU_DW-1:0]	irpu_mrg_rd,
output[ 1:0]				irpu_amvp_dlat,
output[1:0][33:0]			irpu_amvp_mv_info,
output[2:0]					mrg2mc_cand_done,
// dbg
output reg	[31:0]			reg_mvp_dbg_out,

// input
input						clk_vc,
input						vc_rst_z,
input						reg_i_slice,
input	[31:0]				reg_cur_poc,
input	[ 2:0]				reg_ctu_sz,  //  0:4, 1:8 ... 5:128
input						reg_slice_go,
input						reg_col_l0_flag,
input	[ 3:0]				reg_col_ref_idx,
input	[VC_CTU_X_NB-1:0]	reg_pic_width_ctu_m1,
input	[VC_CU_X_NB-1:0]	reg_pic_width_cu_m1,
input	[VC_CU_Y_NB-1:0]	reg_pic_height_cu_m1,
input	[ 3:0]			    reg_num_ref_l0_act_m1,
input	[ 3:0]				reg_num_ref_l1_act_m1,
input						reg_tmp_mvp_flag,
input	[5:0]				reg_mv_gain,
input                       reg_enc_cons_mrg,
input   [3:0]               reg_enc_mrg_mvx_thr,
input   [3:0]               reg_enc_mrg_mvy_thr,
input                       reg_avc_mode,
// CCU
input	[ 2:0]				irpu_amvp_ack,
input	[ 2:0]				irpu_mrg_ack,
// mode decision
input  						cur_cu_upd,
input	[1:0]				cur_cu_upd_sz,
input	[2:0]				cur_cu_upd_x,
input	[2:0]				cur_cu_upd_y,
input	[15:0]				cur_cu_upd_mvx,
input	[15:0]				cur_cu_upd_mvy,
input	[1:0]				cur_cu_upd_refidx,
// FME
input	[ 1:0]				fme2amvp_cand_rdy,
input	[1:0][35:0] 		fme2amvp_cand_mv, // blk_sz (2) +  refidx (2) + mvxy (32)
// MC
input	[2:0]				mc2mrg_cand_ack,
input	[2:0]				mc2mrg_cost_rdy,
input	[2:0][VC_MRG_NB+2-1:0] mc2mrg_cost_data,
// CTU
input						cur_ctu_start,
input	[VC_CTU_X_NB-1:0]	cur_ctu_x,
input	[VC_CTU_Y_NB-1:0]	cur_ctu_y,
// CU
input	[ 2:0]				cur_cu_start,
input	[ 2:0]				cur_cu_x,
input	[ 2:0]				cur_cu_y,
input	[ 2:0][1:0]			cur_cu_a_avail,
input	[ 2:0][2:0]			cur_cu_b_avail,
input						cur_cu_is_skip,
input						cur_cu_is_zmv,
input						cur_cu_terminate,
// neib read
input						neib_a2irpu_gnt,
input						neib_a2irpu_rd_lat,
input	[34*2-1:0]			neib_a2irpu_rd,
input						neib_b2irpu_gnt,
input						neib_b2irpu_rd_lat,
input	[34*2-1:0]			neib_b2irpu_rd,
input						col2irpu_gnt,
input						col2irpu_rd_lat,
input	[42*2-1:0]			col2irpu_rd,
input						ref2irpu_gnt,
input						ref2irpu_rd_lat,
input	[32:0]				ref2irpu_rd,
// dbg
input						reg_vc_dbg_out_go,
input	[2:0]				reg_vc_irpu_dbg_sel
);
// local parameter

// register declaration

// wire declaration
wire						neib_done_amvp;
wire						neib_done_mrg;
wire	[NUM_REF-1:0][32:0]	reflist_info;
wire						cand_blk_done;
wire						cmdq_cu_start;
wire						amvp_neib_cu_start;
wire						mrg_neib_cu_start;
wire	[ 2:0]				blk_sz;
wire	[ 2:0]				neib_b_avail;
wire	[ 1:0]				neib_a_avail;
wire	[2:0][13:0]			amvp_cmd_out;
wire	[2:0][13:0]			mrg_cmd_out;
wire						cand0_push;
wire						cand1_push;
wire	[33:0]				cand0_mv;
wire	[33:0]				cand1_mv;
wire	[2:0] [33:0]		amvp_neib_b;
wire	[1:0] [33:0]		amvp_neib_a;
wire	[1:0] [41:0]		amvp_col_c;
wire	[1:0]				amvp_col_c_avail;
wire	[2:0] [33:0]		mrg_neib_b;
wire	[1:0] [33:0]		mrg_neib_a;
wire	[1:0] [41:0]		mrg_col_c;
wire	[1:0]				mrg_col_c_avail;
reg		[VC_PIC_X_NB-1:0]   pic_x;
reg		[VC_PIC_Y_NB-1:0]   pic_y;
wire	[1:0][2:0]			cmdq_empty_n;       //0: merge, 1: AMVP
wire	[2:0]				amvp_blk_sz;
wire	[2:0]				mrg_blk_sz;
wire	[3:0][31:0]			blk32_neib_b_r;
wire	[3:0][31:0]			blk32_neib_a_r;
wire	[1:0][31:0]			blk16_neib_b_r;
wire	[1:0][31:0]			blk16_neib_a_r;
wire	[31:0]				blk8_neib_b_r;
wire	[31:0]				blk8_neib_a_r;
wire                        blk_sz_lat_mrg;
wire                        blk_sz_lat_amvp;
wire    [2:0]               n_blk_sz_mrg;
wire    [2:0]               n_blk_sz_amvp;

// dbg mrg
wire	[6:0]				dbg_fsm_mrg_mvp_cs;
wire	[2:0]				dbg_fsm_mrg_cand_cs;
wire	[3:0]				dbg_fsm_mrg_mv_gain_cs;
wire	[5:0][3:0]			dbg_fsm_mrg_flow_cs;
wire	[2:0]				dbg_cand_diff;
wire    [5:0]               dbg_cu_xy;
// dbg amvp
wire	[6:0]				dbg_fsm_amvp_mvp_cs;
wire	[4:0]				dbg_fsm_amvp_cand_cs;

wire [5:0][31:0]			dbg_mvp_out;

// AVC
wire                        g_reg_i_slice;
wire                        avc_mvp_push;
wire    [1:0]               avc_ref_idx;
wire                        avc_is_long;
wire    [7:0]               avc_pocdiff;
wire    [1:0][15:0]         avc_mvpxy;
wire    [1:0][3:0]          avc_mvd_gt4;
wire    [1:0]               is_pic_right;
wire                        is_pic_top16;
wire                        is_pic_left16;

//combinational logic

assign	dbg_mvp_out[0] = {
							1'd0,
							dbg_fsm_mrg_mvp_cs,		// 7
							dbg_fsm_mrg_flow_cs[5], // 4
							dbg_fsm_mrg_flow_cs[4], // 4
                            dbg_fsm_mrg_flow_cs[3], // 4
							dbg_fsm_mrg_flow_cs[2], // 4
							dbg_fsm_mrg_flow_cs[1], // 4
							dbg_fsm_mrg_flow_cs[0]	// 4
						};

assign	dbg_mvp_out[1] = {
							1'd0,
                            irpu_amvp_ack[1:0],     // 2
                            irpu_amvp_rdy[1:0],     // 2
                            amvp2fme_cand_ack,      // 2
                            fme2amvp_cand_rdy,      // 2
                            dbg_cand_diff, 		    // 4
							dbg_fsm_amvp_cand_cs,   // 5
							dbg_fsm_amvp_mvp_cs,    // 7
							dbg_fsm_mrg_mv_gain_cs, // 4
							dbg_fsm_mrg_cand_cs	    // 3
						};

assign  dbg_mvp_out[2]  =   {{32-VC_PIC_X_NB-VC_PIC_Y_NB-5{1'b0}},
                            mrg2mc_cand_data[0][MRG2MC_DW-1-:(VC_PIC_X_NB+VC_PIC_Y_NB+1)],
                            mrg2mc_cost_ack[0],        // bit3
                            mc2mrg_cost_rdy[0],        // bit2
                            mc2mrg_cand_ack[0],        // bit1
                            mrg2mc_cand_rdy[0]};       // bit0

assign  dbg_mvp_out[3]  =   {{32-VC_PIC_X_NB-VC_PIC_Y_NB-5{1'b0}},
                            mrg2mc_cand_data[1][MRG2MC_DW-1-:(VC_PIC_X_NB+VC_PIC_Y_NB+1)],
                            mrg2mc_cost_ack[1],        // bit3
                            mc2mrg_cost_rdy[1],        // bit2
                            mc2mrg_cand_ack[1],        // bit1
                            mrg2mc_cand_rdy[1]};       // bit0

assign  dbg_mvp_out[4]  =   {{32-VC_PIC_X_NB-VC_PIC_Y_NB-5{1'b0}},
                            mrg2mc_cand_data[2][MRG2MC_DW-1-:(VC_PIC_X_NB+VC_PIC_Y_NB+1)],
                            mrg2mc_cost_ack[2],        // bit3
                            mc2mrg_cost_rdy[2],        // bit2
                            mc2mrg_cand_ack[2],        // bit1
                            mrg2mc_cand_rdy[2]};       // bit0

assign  dbg_mvp_out[5]  =   {2'd0,                          //2bits, 31-30
                            cur_ctu_y[0+:6],                //6bits, 29-24
                            cur_cu_y,                       //3bits, 23-21
                            cur_ctu_x[0+:6],                //6bits, 20-15
                            cur_cu_x,                       //3bits, 14-12
                            irpu_mrg_ack,                   //3bots, 11-9
                            irpu_mrg_rdy,                   //3bits, 8-6
                            dbg_cu_xy};                     //6bits, 5-0                        

always@(*) begin : pic_x_y_assign_blk
    pic_x   =   {cur_ctu_x[0+:VC_PIC_X_NB-6], cur_cu_x, 3'd0};
    pic_y   =   {cur_ctu_y[0+:VC_PIC_Y_NB-6], cur_cu_y, 3'd0};
end

assign  g_reg_i_slice   =   reg_avc_mode | reg_i_slice;
assign  is_pic_right    =   {2{{cur_ctu_x[0+:VC_PIC_X_NB-6], cur_cu_x[2:1]} == reg_pic_width_cu_m1[VC_CU_X_NB-1:1]}} &
                            {1'b1, cur_cu_x[0] == reg_pic_width_cu_m1[0]}   |   {1'b0, {cur_cu_y[0], cur_cu_x[0]} == 3};

assign  is_pic_top16    =   {cur_ctu_y, cur_cu_y[2:1]} == 0;
assign  is_pic_left16   =   {cur_ctu_x, cur_cu_x}      == 0;

// function/task

// instantiation

ve_mrg_top
#(
	.MVP_SCALE_EN	(MVP_SCALE_EN),
	.AMVP_OR_MRG  	(0),
	.NUM_REF		(NUM_REF),
	.MUL_REF	 	(NUM_REF > 1),
    .MAX_BLK_SZ 	(3), // 3:blk32, 2:blk16
	.VC_SATD_NB	 	(VC_SATD_NB),
	.VC_SSE_NB	 	(VC_SSE_NB),
	.VC_MRG_NB		(VC_MRG_NB),
	.VC_PIC_X_NB	(VC_PIC_X_NB),
    .VC_PIC_Y_NB	(VC_PIC_Y_NB),
	.VC_CTU_X_NB	(VC_CTU_X_NB),
	.VC_CTU_Y_NB	(VC_CTU_Y_NB),
    .MRG2CCU_DW     (MRG2CCU_DW),
	.VC_EN_BI_DIR	(0),   // 0: ref0 only, 1: bi direction
	.FSMW			(3)
)
U_VE_MRG_TOP
(
// output
.cu_blk_en				(mrg_blk_sz),
.cu_cmd_out 			(mrg_cmd_out),
.neib_cu_start      	(mrg_neib_cu_start),
.cmdq_empty_n			(cmdq_empty_n[0]),
.mrg2mc_cand_rdy    	(mrg2mc_cand_rdy),
.mrg2mc_cand_nb         (mrg2mc_cand_nb),
.mrg2mc_cand_data   	(mrg2mc_cand_data),
.mrg2mc_cost_ack    	(mrg2mc_cost_ack),
.irpu_mrg_rdy       	(irpu_mrg_rdy),
.irpu_mrg_rd 			(irpu_mrg_rd),
.mrg2mc_cand_done		(mrg2mc_cand_done),
.blk_sz_lat             (blk_sz_lat_mrg),
.n_blk_sz               (n_blk_sz_mrg),
.dbg_fsm_mvp_cs			(dbg_fsm_mrg_mvp_cs),
.dbg_fsm_cand_cs		(dbg_fsm_mrg_cand_cs),
.dbg_fsm_mv_gain_cs		(dbg_fsm_mrg_mv_gain_cs),
.dbg_fsm_mrg_flow_cs	(dbg_fsm_mrg_flow_cs),
.dbg_cand_diff			(dbg_cand_diff),
.dbg_cu_xy              (dbg_cu_xy),

// input
.clk_vc 				(clk_vc),
.vc_rst_z           	(vc_rst_z),
.reg_i_slice			(g_reg_i_slice),
.reg_ctu_sz				(reg_ctu_sz),
.reg_cur_poc        	(reg_cur_poc),
.reg_slice_go       	(reg_slice_go),
.reg_col_l0_flag    	(reg_col_l0_flag),
.reg_col_ref_idx    	(reg_col_ref_idx),
.reg_tmp_mvp_flag		(reg_tmp_mvp_flag),
.reg_num_ref_l0_act_m1	(reg_num_ref_l0_act_m1),
.reg_mv_gain			(reg_mv_gain),
.reg_enc_cons_mrg       (reg_enc_cons_mrg),
.reg_enc_mrg_mvx_thr    (reg_enc_mrg_mvx_thr),
.reg_enc_mrg_mvy_thr    (reg_enc_mrg_mvy_thr),
.reg_avc_mode           (reg_avc_mode),
.irpu_mrg_ack       	(irpu_mrg_ack),
.mc2mrg_cand_ack    	(mc2mrg_cand_ack),
.mc2mrg_cost_rdy    	(mc2mrg_cost_rdy),
.mc2mrg_cost_data   	(mc2mrg_cost_data),
.cur_ctu_start      	(cur_ctu_start),
.cur_ctu_x				(cur_ctu_x),
.cur_ctu_y				(cur_ctu_y),
.cur_cu_start       	(cur_cu_start),
.cur_cu_x           	(cur_cu_x),
.cur_cu_y           	(cur_cu_y),
.cur_cu_a_avail     	(cur_cu_a_avail),
.cur_cu_b_avail     	(cur_cu_b_avail),
.cur_cu_is_skip     	(cur_cu_is_skip),
.cur_cu_is_zmv      	(cur_cu_is_zmv),
.cur_cu_terminate   	(cur_cu_terminate),
.pic_x					(pic_x),
.pic_y					(pic_y),
.neib_done_con      	(neib_done_mrg),
.neib_b             	(mrg_neib_b),
.neib_a             	(mrg_neib_a),
.col_c              	(mrg_col_c),
.col_c_avail        	(mrg_col_c_avail),
.reflist_info       	(reflist_info),
.blk32_neib_b_r			(blk32_neib_b_r),
.blk16_neib_b_r			(blk16_neib_b_r),
.blk8_neib_b_r			(blk8_neib_b_r),
.blk32_neib_a_r			(blk32_neib_a_r),
.blk16_neib_a_r			(blk16_neib_a_r),
.blk8_neib_a_r			(blk8_neib_a_r),
// AVC
.avc_mvp_push           (avc_mvp_push),
.avc_ref_idx            (avc_ref_idx),
.avc_is_long            (avc_is_long),
.avc_pocdiff            (avc_pocdiff),
.avc_mvpxy              (avc_mvpxy),
.avc_mvd_gt4            (avc_mvd_gt4)
);

ve_amvp_top
#(
	.MVP_SCALE_EN			(MVP_SCALE_EN),
	.NUM_REF				(NUM_REF),
	.MUL_REF				(NUM_REF > 1),
	.VC_SATD_NB	 			(VC_SATD_NB),
    .VC_SSE_NB	 			(VC_SSE_NB),
	.MAX_BLK_SZ				(MAX_BLK_SZ), // 3:blk32, 2:blk16
	.AMVP2CCU_DW			(AMVP2CCU_DW),
	.FME_BLK8_CMDQ_DEPTH 	(FME_BLK8_CMDQ_DEPTH),
	.FME_BLK16_CMDQ_DEPTH 	(FME_BLK16_CMDQ_DEPTH),
	.FSMW					(5)
)
U_VE_AMVP_TOP
(
// output
.cu_blk_en				(amvp_blk_sz),
.cu_cmd_out 			(amvp_cmd_out),
.cmdq_empty_n           (cmdq_empty_n[1]),
.neib_cu_start      	(amvp_neib_cu_start),
.amvp2fme_cand_ack		(amvp2fme_cand_ack),
.irpu_amvp_rdy			(irpu_amvp_rdy),
.irpu_amvp_rd			(irpu_amvp_rd),
.irpu_amvp_dlat			(irpu_amvp_dlat),
.irpu_amvp_mv_info		(irpu_amvp_mv_info),
.blk_sz_lat             (blk_sz_lat_amvp),
.n_blk_sz               (n_blk_sz_amvp),
.dbg_fsm_mvp_cs			(dbg_fsm_amvp_mvp_cs),
.dbg_fsm_cand_cs		(dbg_fsm_amvp_cand_cs),
// AVC
.avc_mvp_push           (avc_mvp_push),
.avc_ref_idx            (avc_ref_idx),
.avc_is_long            (avc_is_long),
.avc_pocdiff            (avc_pocdiff),
.avc_mvpxy              (avc_mvpxy),
.avc_mvd_gt4            (avc_mvd_gt4),
// input
.irpu_amvp_ack			(irpu_amvp_ack),
.clk_vc             	(clk_vc),
.vc_rst_z           	(vc_rst_z),
.reg_i_slice			(reg_i_slice),
.reg_slice_go			(reg_slice_go),
.reg_cur_poc        	(reg_cur_poc),
.reg_col_l0_flag    	(reg_col_l0_flag),
.reg_col_ref_idx    	(reg_col_ref_idx),
.reg_tmp_mvp_flag		(reg_tmp_mvp_flag),
.reg_num_ref_l0_act_m1	(reg_num_ref_l0_act_m1),
.reg_avc_mode           (reg_avc_mode),
.fme2amvp_cand_rdy		(fme2amvp_cand_rdy),
.fme2amvp_cand_mv		(fme2amvp_cand_mv),
.cur_ctu_start      	(cur_ctu_start),
.cur_cu_start       	(cur_cu_start),
.cur_cu_x           	(cur_cu_x),
.cur_cu_y           	(cur_cu_y),
.cur_cu_a_avail     	(cur_cu_a_avail),
.cur_cu_b_avail     	(cur_cu_b_avail),
.cur_cu_is_skip     	(cur_cu_is_skip),
.cur_cu_is_zmv      	(cur_cu_is_zmv),
.cur_cu_terminate   	(cur_cu_terminate),
.is_pic_right           (is_pic_right),
.is_pic_top16           (is_pic_top16),
.is_pic_left16          (is_pic_left16),
.neib_done_con      	(neib_done_amvp), 
.neib_b             	(amvp_neib_b), 
.neib_a             	(amvp_neib_a), 
.col_c              	(amvp_col_c), 
.col_c_avail        	(amvp_col_c_avail), 
.reflist_info       	(reflist_info),
.blk32_neib_b_r			(blk32_neib_b_r),
.blk16_neib_b_r			(blk16_neib_b_r),
.blk8_neib_b_r			(blk8_neib_b_r),
.blk32_neib_a_r			(blk32_neib_a_r),
.blk16_neib_a_r			(blk16_neib_a_r),
.blk8_neib_a_r			(blk8_neib_a_r)
);


vc_mvp_get_neib
#(
    .VC_CTU_X_NB	(VC_CTU_X_NB),
	.VC_CTU_Y_NB	(VC_CTU_Y_NB),
	.NUM_REF		(NUM_REF),
	.MAX_BLK_SZ		(MAX_BLK_SZ),
	.VC_EN_BI_DIR	(VC_EN_BI_DIR)
)
U_VC_MVP_GET_NEIB
(
// otuput
.neib_done_amvp			(neib_done_amvp),
.neib_done_mrg			(neib_done_mrg),
.irpu2neib_b_req    	(irpu2neib_b_req),
.irpu2neib_b_addr   	(irpu2neib_b_addr),
.amvp_neib_b        	(amvp_neib_b),
.mrg_neib_b         	(mrg_neib_b),
.blk32_neib_b_r			(blk32_neib_b_r),
.blk16_neib_b_r			(blk16_neib_b_r),
.blk8_neib_b_r			(blk8_neib_b_r),
.irpu2neib_a_req    	(irpu2neib_a_req),
.irpu2neib_a_addr   	(irpu2neib_a_addr),
.amvp_neib_a        	(amvp_neib_a),
.mrg_neib_a         	(mrg_neib_a),
.blk32_neib_a_r			(blk32_neib_a_r),
.blk16_neib_a_r			(blk16_neib_a_r),
.blk8_neib_a_r			(blk8_neib_a_r),
.irpu2col_req       	(irpu2col_req),
.irpu2col_addr      	(irpu2col_addr),
.amvp_col_c         	(amvp_col_c),
.mrg_col_c          	(mrg_col_c),
.amvp_col_c_avail   	(amvp_col_c_avail),
.mrg_col_c_avail    	(mrg_col_c_avail),
.irpu2ref_req       	(irpu2ref_req),
.irpu2ref_addr      	(irpu2ref_addr),
.reflist_info 			(reflist_info),		
// input
.clk_vc             	(clk_vc),
.vc_rst_z           	(vc_rst_z),
.amvp_blk_sz			(amvp_blk_sz),
.mrg_blk_sz				(mrg_blk_sz),
.cmdq_empty_n			(cmdq_empty_n),
.reg_avc_mode           (reg_avc_mode),
.reg_slice_go			(reg_slice_go),
.reg_i_slice			(reg_i_slice),
.reg_pic_width_ctu_m1	(reg_pic_width_ctu_m1),
.reg_pic_width_cu_m1	(reg_pic_width_cu_m1),
.reg_pic_height_cu_m1	(reg_pic_height_cu_m1),
.reg_num_ref_l0_act_m1	(reg_num_ref_l0_act_m1),
.reg_tmp_mvp_flag		(reg_tmp_mvp_flag),
.cur_ctu_start      	(cur_ctu_start),
.ctux			    	(cur_ctu_x),
.ctuy					(cur_ctu_y),
.pic_x					(pic_x),
.pic_y					(pic_y),
.cur_cu_upd				(cur_cu_upd),
.cur_cu_upd_sz			(cur_cu_upd_sz),
.cur_cu_upd_x			(cur_cu_upd_x),
.cur_cu_upd_y			(cur_cu_upd_y),
.cur_cu_upd_mvx			(cur_cu_upd_mvx),
.cur_cu_upd_mvy			(cur_cu_upd_mvy),
.cur_cu_upd_refidx		(cur_cu_upd_refidx),
.amvp_cu_start 			(amvp_neib_cu_start),
.mrg_cu_start  			(mrg_neib_cu_start),
.amvp_cmd_out			(amvp_cmd_out),
.mrg_cmd_out			(mrg_cmd_out),
.neib_b2irpu_gnt    	(neib_b2irpu_gnt),
.neib_b2irpu_rd_lat 	(neib_b2irpu_rd_lat),
.neib_b2irpu_rd     	(neib_b2irpu_rd),
.neib_a2irpu_gnt    	(neib_a2irpu_gnt),
.neib_a2irpu_rd_lat 	(neib_a2irpu_rd_lat),
.neib_a2irpu_rd     	(neib_a2irpu_rd),
.col2irpu_gnt       	(col2irpu_gnt),
.col2irpu_rd_lat    	(col2irpu_rd_lat),
.col2irpu_rd        	(col2irpu_rd),
.ref2irpu_gnt       	(ref2irpu_gnt),
.ref2irpu_rd_lat    	(ref2irpu_rd_lat),
.ref2irpu_rd			(ref2irpu_rd),
.blk_sz_lat_amvp        (blk_sz_lat_amvp),
.blk_sz_lat_mrg         (blk_sz_lat_mrg),
.n_blk_sz_amvp          (n_blk_sz_amvp),
.n_blk_sz_mrg           (n_blk_sz_mrg)
);

// state machine

// sequence logic

always@(posedge clk_vc or negedge vc_rst_z) begin : dbg_sel
	if(~vc_rst_z) begin
		reg_mvp_dbg_out <= 0;
	end
    else if(reg_slice_go)
    reg_mvp_dbg_out <= 0;
	else if(reg_vc_dbg_out_go) begin
		reg_mvp_dbg_out <= dbg_mvp_out[reg_vc_irpu_dbg_sel];
	end
end

endmodule
