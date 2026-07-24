`include "ve_defines.v"
module	ve_mrg_top
#(
	parameter	AMVP_OR_MRG = 0, // 1:AMVP, 0:MERGE
	parameter	MVP_SCALE_EN = 0,
	parameter	NUM_REF = 2,
    parameter	MUL_REF = (NUM_REF > 1),
	parameter	MAX_BLK_SZ = 3, // 3:blk32, 2:blk16
	parameter	VC_CTU_X_NB = 7,
	parameter	VC_CTU_Y_NB = 7,
	parameter	VC_PIC_X_NB = 12,
    parameter	VC_PIC_Y_NB = 12,
	parameter	VC_EN_BI_DIR = 0,  // 0: ref0 only, 1: bi direction
	parameter	VC_SATD_NB = 18, 
	parameter	VC_SSE_NB = 26,  
	parameter	VC_MRG_NB = VC_SATD_NB + VC_SSE_NB,
    parameter	MRG2MC_DW = VC_PIC_X_NB + VC_PIC_Y_NB + 39, // ypos(VC_CTU_Y_NB+6), xpos(VC_CTU_X_NB+6), vsx(2)+hsz(2)+refidx(2)+mvy(16)+mvx(16) = 38
	parameter	MRG2CCU_DW 	= (8+8+VC_SSE_NB+VC_SATD_NB+2+46 ),
	parameter	FSMW = 3
)

(
// output

output	[2:0]					cu_blk_en,
output	[2:0][13:0]				cu_cmd_out,
output							neib_cu_start,
output	[2:0]					cmdq_empty_n,
output                          blk_sz_lat,
output  [2:0]                   n_blk_sz,
// MC
output reg	[2:0]				mrg2mc_cand_rdy,
output reg	[2:0][MRG2MC_DW-1:0]mrg2mc_cand_data, //     ypos => VC_CTU_Y_NB+6 ,xpos => VC_CTU_X_NB+6 , vsz => 2 , hsz => 2 ,ref_idx => 2 ,mvy => 16, mvx => 16
output  reg [2:0]               mrg2mc_cand_nb,
output [2:0]                    mrg2mc_cost_ack,
// CCU
output	 [ 2:0]					irpu_mrg_rdy,
output   [2:0][MRG2CCU_DW-1:0]	irpu_mrg_rd,
output  [2:0]					mrg2mc_cand_done,
// dbg
output	[6:0]					dbg_fsm_mvp_cs,
output	[FSMW-1:0]				dbg_fsm_cand_cs,
output	[3:0]					dbg_fsm_mv_gain_cs,
output	[5:0][3:0]				dbg_fsm_mrg_flow_cs,
output	[2:0]					dbg_cand_diff,
output  [5:0]                   dbg_cu_xy,

// input

input							clk_vc,
input							vc_rst_z,
input							reg_i_slice,
input	[31:0]					reg_cur_poc,
input	[ 2:0]					reg_ctu_sz,
input							reg_slice_go,
input							reg_tmp_mvp_flag,
input	[ 3:0]					reg_num_ref_l0_act_m1,
input							reg_col_l0_flag,
input	[ 3:0]					reg_col_ref_idx,
input	[ 5:0]					reg_mv_gain,
input                       	reg_enc_cons_mrg,
input   [3:0]                   reg_enc_mrg_mvx_thr,
input   [3:0]                   reg_enc_mrg_mvy_thr,
input                           reg_avc_mode,
// CCU
input   [ 2:0]                  irpu_mrg_ack,
// MC
input   [ 2:0]                  mc2mrg_cand_ack,
input   [2:0]                   mc2mrg_cost_rdy,
input   [2:0] [VC_SATD_NB+VC_SSE_NB+2-1:0] mc2mrg_cost_data,// {sse,satd}
// CTU
input                           cur_ctu_start,
input   [VC_CTU_X_NB-1:0]       cur_ctu_x,
input   [VC_CTU_Y_NB-1:0]       cur_ctu_y,
// CU
input   [ 2:0]                  cur_cu_start,
input   [ 2:0]                  cur_cu_x,
input   [ 2:0]                  cur_cu_y,
input   [ 2:0][1:0]             cur_cu_a_avail,
input   [ 2:0][2:0]             cur_cu_b_avail,
input                           cur_cu_is_skip,
input                           cur_cu_is_zmv,
input                           cur_cu_terminate,
input   [VC_PIC_X_NB-1:0]       pic_x,
input   [VC_PIC_Y_NB-1:0]       pic_y,
// neib 
input                           neib_done_con,
input   [2:0] [33:0]            neib_b,
input   [1:0] [33:0]            neib_a,
input   [1:0] [41:0]            col_c,
input   [1:0]                   col_c_avail,
input   [NUM_REF-1:0][32:0]     reflist_info,
input   [3:0]   [31:0]          blk32_neib_b_r,
input   [3:0]   [31:0]          blk32_neib_a_r,
input   [1:0]   [31:0]          blk16_neib_b_r,
input   [1:0]   [31:0]          blk16_neib_a_r,
input           [31:0]          blk8_neib_b_r,
input           [31:0]          blk8_neib_a_r,
// AVC
input                           avc_mvp_push,
input   [1:0]                   avc_ref_idx,
input                           avc_is_long,
input   [7:0]                   avc_pocdiff,
input   [1:0][15:0]             avc_mvpxy,
input   [1:0][3:0]              avc_mvd_gt4

);

// local parameter
localparam	TERM_IDLE = 0,
			TERM_WAIT_EMPTY = 1,
			TERM_FLUSH = 2;

localparam	MVG_IDLE = 0,
			MVG_BLK8 = 1,
			MVG_BLK16= 2,
			MVG_BLK32= 3;

localparam	MC_IDLE = 0,
			MC_WAIT_HSK_0 = 1,
			MC_WAIT_HSK_1 = 2,
			MC_DONE = 3;

localparam	MRG_IDLE = 0,
			MRG_CAND_RDY = 1,
			MRG_MC_CAND_RDY = 2,
			MRG_DONE = 3;

// register declaration
reg   [2:0][3:0]            fsm_mc_done_cs;
reg   [2:0]                 fsm_term_cs;
reg   [3:0]                 fsm_mv_gain_cs;
reg   [2:0]                 cu_empty_n_reg;
reg   [2:0][2:0]            term_cnt;
reg   [2:0]                 toggle_cost;
reg   [2:0][VC_MRG_NB+2-1:0] cost_q_reg;
reg   [45:0]                cand_r;
//reg   [2:1][5:0]            cuxy;
reg   [1:0]                 cu_x16;
reg   [1:0]                 cu_y16;
reg                         cu_x32;
reg                         cu_y32;
reg   [3:0]                 blk32_neib_b_avail;
reg   [3:0]                 blk32_neib_a_avail;
reg   [1:0]                 blk16_neib_b_avail;
reg   [1:0]                 blk16_neib_a_avail;
reg                         blk8_neib_b_avail;
reg                         blk8_neib_a_avail;

reg   [2:0][1:0]            mrg_cand_rdy;
reg   [2:0]                 cand_diff;
reg   [5:0][3:0]            fsm_mrg_flow_cs;

reg   [2:0][1:0][31:0]      md_mv;

// motion detection
reg   [31:0]                cand_mv_0_reg;
reg   [2:0]                 md_cal_en;
reg   [2:0]                 mvg_cnt; // 0~4
reg   [11:0]                mul_add_accu;
reg   [9:0]                 md_abs_sum_clip;
reg   [2:0][7:0]            md_mvl;

// wire declaration
//wire cand_diff
reg   [1:0][31:0]           md_mv_sel;
reg   [2:0][1:0][VC_MRG_NB+2-1:0] cost_q;
reg   [5:0][3:0]            fsm_mrg_flow_ns;
reg   [2:0][3:0]            fsm_mc_done_ns;
reg   [ 3:0]                fsm_mv_gain_ns;
reg   [ 2:0]                fsm_term_ns;
wire  [ 3:0]                cur_ref_idx;
wire                        cand_cu_start;
wire                        cand_blk_done;
wire                        cand_blk_idle;
wire  [1:0][42:0]           cand_mv;
wire  [1:0]                 cand_rdy;
wire  [5:0]                 cand_empty_n;
wire  [5:0][45:0]           cand_q;
reg   [5:0][45:0]           cand_d;
reg   [5:0]                 cand_push;
reg   [5:0]                 cand_pop;

reg   [5:0][46:0]           cand2_d;
reg   [5:0]                 cand2_push;
reg   [5:0]                 cand2_pop;

reg   [2:0]                 mrg2mc_cand_hsk;
reg   [2:0]                 mc2mrg_cost_hsk;
reg   [2:0]                 irpu_mrg_hsk;
reg   [2:0][MRG2CCU_DW-1:0]  irpu_mrg_wd;

reg   [2:0][3:0]            mv_bs_b_0;
reg   [2:0][3:0]            mv_bs_a_0;
reg   [2:0][3:0]            mv_bs_b_1;
reg   [2:0][3:0]            mv_bs_a_1;
// cand sel
reg     [2:0]                 cand_sel; // 0:cand0, 1:cand1
reg     [2:0][45:0]           sel_cand_0;
reg     [2:0][45:0]           sel_cand_1;
reg     [2:0][VC_MRG_NB+2-1:0] sel_cost_0;
reg     [2:0][VC_MRG_NB+2-1:0] sel_cost_1;

wire                          all_queue_empty;
reg     [2:0]                 mrg2ccu_push;
reg     [MAX_BLK_SZ-1:0]      gt0;
wire    [MAX_BLK_SZ-1:0]      msb_one;
wire    [ 1:0]                sz;
wire    [2:0][11:0]           pic_x_sel;
wire    [2:0][11:0]           pic_y_sel;
wire    [16:0]                cu_cmd_out_sel;
wire                          cand_push_0;
wire                          cand_push_1;
wire    [31:0]                cand_mv0_blk_sz_sel;
wire    [31:0]                cand_mv1_blk_sz_sel;
wire    [31:0]                cand_mv0_sel;
wire    [31:0]                cand_mv1_sel;
wire    [ 9:0]                n_md_abs_sum_clip;
wire    [11:0]                mul_add_0;
wire    [11:0]                mul_add_1;
wire    [11:0]                mul_mask1;
wire                          md_cal_en_or;
wire    [11:0]                n_mul_add_accu;
wire    [7:0]                 mul_add_clip;
wire    [9:0]                 n_md_abs_sum_clip_sel;
wire    [2:0]                 mrg_cand_nr_m1 = 1;
wire    [1:0]                 is_pic_right;

reg     [2:0][3:0][31:0]      mvbs_neib_b;
reg     [2:0][3:0][31:0]      mvbs_neib_a;
reg     [2:0][3:0]            mvbs_b_avail;
reg     [2:0][3:0]            mvbs_a_avail;

reg		[2:0]					cand_pop_con;
reg     [2:0]                   cand1_ena;

genvar							i,j;

// combinational logic
assign	mrg2mc_cand_done[0] = fsm_mc_done_cs[0][MC_DONE];
assign	mrg2mc_cand_done[1] = fsm_mc_done_cs[1][MC_DONE];
assign	mrg2mc_cand_done[2] = fsm_mc_done_cs[2][MC_DONE];

// dbg start

assign	dbg_fsm_mv_gain_cs = fsm_mv_gain_cs;
assign	dbg_fsm_mrg_flow_cs[0] = fsm_mrg_flow_cs[0];
assign	dbg_fsm_mrg_flow_cs[1] = fsm_mrg_flow_cs[1];
assign	dbg_fsm_mrg_flow_cs[2] = fsm_mrg_flow_cs[2];
assign	dbg_fsm_mrg_flow_cs[3] = fsm_mrg_flow_cs[3];
assign	dbg_fsm_mrg_flow_cs[4] = fsm_mrg_flow_cs[4];
assign	dbg_fsm_mrg_flow_cs[5] = fsm_mrg_flow_cs[5];
assign	dbg_cand_diff	= cand_diff;
assign  dbg_cu_xy       =   {cu_y32, cu_x32,
                             cu_y16, cu_x16};
// dbg end

always@(*) begin : fsm_mrg_flow_ns_blk
    integer i;
    for(i=0 ; i<3 ; i++) begin
        fsm_mrg_flow_ns[i*2+0] = get_fsm_mrg_flow_ns(
                                                    cand_rdy[0],
                                                    cu_cmd_out_sel[14+i],
                                                    1'b1, // don't care
                                                    1'b1, // don't care
                                                    mrg2mc_cand_hsk[i],
                                                    mc2mrg_cost_hsk[i],
                                                    1'b0,
                                                    cand_diff[i],
                                                    fsm_mrg_flow_cs[2*i+1][3],
                                                    fsm_mrg_flow_cs[2*i+0]);

        fsm_mrg_flow_ns[i*2+1] = get_fsm_mrg_flow_ns(
                                                    cand_rdy[1],
                                                    cu_cmd_out_sel[14+i],
                                                    fsm_mrg_flow_cs[2*i+0][1], //
                                                    fsm_mrg_flow_cs[2*i+0][2], //
                                                    mrg2mc_cand_hsk[i],
                                                    mc2mrg_cost_hsk[i],
                                                    1'b1,
                                                    cand_diff[i],
                                                    fsm_mrg_flow_cs[2*i+0][3],
                                                    fsm_mrg_flow_cs[2*i+1]);
    end
end

always@(*) begin : mvbs_avail
    integer i,j;
    for(i=0 ; i<3 ; i++) begin
        for(j=0 ; j<4 ; j++) begin
            if(i==0 && j==0) begin
                mvbs_b_avail[i][j] = blk8_neib_b_avail;
                mvbs_a_avail[i][j] = blk8_neib_a_avail;
            end
            else if(i==1 && j<2) begin
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

// motion detection start
assign cand_push_0 = cand_push[0] | cand_push[2] | cand_push[4]; // blk8 | blk16 | blk32
assign cand_push_1 = cand_push[1] | cand_push[3] | cand_push[5];
assign cand_mv0_blk_sz_sel = cand_push[0] ? cand_d[0][31:0] :
                              cand_push[2] ? cand_d[2][31:0] :
                                             cand_d[4][31:0];
assign cand_mv1_blk_sz_sel = cand_push[1] ? (cand1_ena[0] ? cand_d[1][31:0] : (cand_push[0] ? cand_d[0][31:0] : cand_r[31:0])) :
                              cand_push[3] ? (cand1_ena[1] ? cand_d[3][31:0] : (cand_push[2] ? cand_d[2][31:0] : cand_r[31:0])) :
                                              (cand1_ena[2] ? cand_d[5][31:0] : (cand_push[4] ? cand_d[4][31:0] : cand_r[31:0]));

assign cand_mv0_sel = cand_mv0_blk_sz_sel;//(cand_push_0 & (reg_avc_mode | cand_push_1)) ? cand_mv0_blk_sz_sel : cand_mv_0_reg;
assign cand_mv1_sel = cand_mv1_blk_sz_sel;

//---- timing ----

always@(*) begin : md_mv_sel_blk
    integer i;
    for(i=0; i<2 ; i++)
        md_mv_sel[i] = fsm_mv_gain_cs[MVG_BLK8] ? md_mv[0][i] :
                       fsm_mv_gain_cs[MVG_BLK16]? md_mv[1][i] :
                                                  md_mv[2][i];
end

assign n_md_abs_sum_clip = get_md_abs_sum_clip( md_mv_sel[0], md_mv_sel[1]);
assign mul_add_1 = mul_mask1 & {1'b0, md_abs_sum_clip,1'b0};
assign mul_add_0 = (mvg_cnt==1) ? {12{reg_mv_gain[0]}} & {2'd0,md_abs_sum_clip} :
                                   {  mul_add_accu[11:1]};
assign mul_mask1 = (mvg_cnt==1) ? {12{reg_mv_gain[1]}} :
                   (mvg_cnt==2) ? {12{reg_mv_gain[2]}} :
                   (mvg_cnt==3) ? {12{reg_mv_gain[3]}} :
                   (mvg_cnt==4) ? {12{reg_mv_gain[4]}} :
                   (mvg_cnt==5) ? {12{reg_mv_gain[5]}} : 0;
assign md_cal_en_or =  fsm_mv_gain_cs[MVG_BLK8] & md_cal_en[0] |
                       fsm_mv_gain_cs[MVG_BLK16] & md_cal_en[1] |
                       fsm_mv_gain_cs[MVG_BLK32] & md_cal_en[2];

assign n_mul_add_accu = mul_add_0 + mul_add_1;
assign mul_add_clip = (n_mul_add_accu > 8'd255) ? 8'd255 : n_mul_add_accu[7:0];
// motion detection end

assign cu_cmd_out_sel = cu_blk_en[2] ? {3'b100, cu_cmd_out[2]} :
                        cu_blk_en[1] ? {3'b010, cu_cmd_out[1]} :
                                       {3'b001, cu_cmd_out[0]};

assign pic_x_sel[0] = pic_x;
assign pic_y_sel[0] = pic_y;
//assign pic_x_sel[1] = {cur_ctu_x[0+:VC_PIC_X_NB-6], cuxy[1][2:0],3'd0};
//assign pic_y_sel[1] = {cur_ctu_y[0+:VC_PIC_Y_NB-6], cuxy[1][5:3],3'd0};
//assign pic_x_sel[2] = {cur_ctu_x[0+:VC_PIC_X_NB-6], cuxy[2][2:0],3'd0};
//assign pic_y_sel[2] = {cur_ctu_y[0+:VC_PIC_Y_NB-6], cuxy[2][5:3],3'd0};
assign pic_x_sel[1] = {cur_ctu_x[0+:VC_PIC_X_NB-6], cu_x16, 1'b0 ,3'd0};
assign pic_y_sel[1] = {cur_ctu_y[0+:VC_PIC_Y_NB-6], cu_y16, 1'b0 ,3'd0};
assign pic_x_sel[2] = {cur_ctu_x[0+:VC_PIC_X_NB-6], cu_x32, 2'd0 ,3'd0};
assign pic_y_sel[2] = {cur_ctu_y[0+:VC_PIC_Y_NB-6], cu_y32, 2'd0 ,3'd0};

always@(*) begin : mrg2mc_cand_rdy_blk
    integer i;
    for(i=0; i<3 ; i++)
        mrg2mc_cand_rdy[i] = |mrg_cand_rdy[i];
end

assign mrg2mc_cost_ack = 3'b111;

// check two cands diff or same
//assign fsm_mrg_cand_ns[0] = fsm_mrg_cand(cand_rdy[0], fsm_mrg_cand_cs[1][1], reg_slice_go, fsm_mrg_cand_cs[0] );
//assign fsm_mrg_cand_ns[1] = fsm_mrg_cand(cand_rdy[1], fsm_mrg_cand_cs[0][1], reg_slice_go, fsm_mrg_cand_cs[1] );

/*
assign cand_diff = (mrg_cand_nr_m1 == 0)                           ? 0 :
                   (&cand_rdy)                                     wire [5:0] cand_empty_n;            [0+:34] :
                   cu_blk_en[2] &                                   wire [5:0] cand_empty_n;            [0+:34] :
                   cu_blk_en[1] &                                                                         [0+:34] :
                   cu_blk_en[0] & cand_empty_n[0] & cand_rdy[1] ? cand_r[0][0+:34] != cand_mv[1][0+:34] : 0;
*/

always@(*) begin: pop_blk
    integer i;
    for(i=0; i<3 ; i++) begin
        if(reg_avc_mode)
            cand_pop_con[i] = mc2mrg_cost_hsk[i];
        else
            cand_pop_con[i] = !cand_diff[i] & fsm_mrg_flow_cs[i*2+0][2] & mc2mrg_cost_hsk[i] |
                               cand_diff[i] & fsm_mrg_flow_cs[i*2+0][3] & fsm_mrg_flow_cs[i*2+1][2] & mc2mrg_cost_hsk[i];
    end
end

always@(*) begin : fifo_ctrl_blk_sz
    integer i;
    for(i=0 ; i<3 ; i++) begin
        // cand lvl ctrl
        cand_push[i*2+0]   = i == 1 & reg_avc_mode ? avc_mvp_push : cand_rdy[0] & cu_cmd_out_sel[14+i];   // cand0
        cand_push[i*2+1]   = i == 1 & reg_avc_mode ? avc_mvp_push : cand_rdy[1] & cu_cmd_out_sel[14+i];   // cand1
        cand_d[i*2+0]      = reg_avc_mode ? {3'd0, avc_is_long, avc_pocdiff, avc_ref_idx, avc_mvpxy} : {cu_cmd_out_sel[16:14],cand_mv[0]};
        cand_d[i*2+1]      = {cu_cmd_out_sel[16:14], cand_mv[1][42:8], reg_avc_mode ? avc_mvd_gt4 : cand_mv[1][0+:8]};
        cand_pop[i*2+0]    = cand_pop_con[i];//(fsm_mrg_flow_cs[i*2+0][3] & (fsm_mrg_flow_cs[i*2+1][3] | !cand_diff[i] ));
        cand_pop[i*2+1]    = cand_pop_con[i];//(fsm_mrg_flow_cs[i*2+0][3] & (fsm_mrg_flow_cs[i*2+1][3] | !cand_diff[i] ));
        // cand hsk
        mrg2mc_cand_hsk[i] = mrg2mc_cand_rdy[i] & mc2mrg_cand_ack[i];
        mrg2mc_cand_data[i] = {|mrg_cand_rdy[i][0], pic_y_sel[i], pic_x_sel[i], 2'(i+1), 2'(i+1),(mrg_cand_rdy[i][0] ? cand_q[2*i+0][33:0] : cand_q[2*i+1][33:0]) };
        // cost hsk
        mc2mrg_cost_hsk[i] = mc2mrg_cost_rdy[i] & mrg2mc_cost_ack[i];
    end
end

always@(*) begin : cost_q_sel
    integer i;
    for(i=0 ; i<3 ; i++) begin
        cost_q[i][0] = cand_diff[i] ? cost_q_reg[i] : mc2mrg_cost_data[i];
        cost_q[i][1] = mc2mrg_cost_data[i];
        cand_sel[i]  = (cost_q[i][1][0+: (VC_SATD_NB+1)] < cost_q[i][0][0+: (VC_SATD_NB+1)]) & cand_diff[i];
        sel_cand_0[i]= cand_q[2*i+0][45:0];
        sel_cand_1[i]= cand_q[2*i+1][45:0];
        sel_cost_0[i]= cost_q[i][0];
        sel_cost_1[i]= cost_q[i][1];
    end
end

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
    for(i=0 ; i<3 ; i++) begin
        for(j=0 ; j<4 ; j++) begin
            mv_bs_b_0[i][j]= get_mv_bs(sel_cand_0[i][31:0], mvbs_neib_b[i][j], mrg2ccu_push, mvbs_b_avail[i][j], j[1:0]);
            mv_bs_a_0[i][j]= get_mv_bs(sel_cand_0[i][31:0], mvbs_neib_a[i][j], mrg2ccu_push, mvbs_a_avail[i][j], j[1:0]);
            mv_bs_b_1[i][j]= get_mv_bs(sel_cand_1[i][31:0], mvbs_neib_b[i][j], mrg2ccu_push, mvbs_b_avail[i][j], j[1:0]);
            mv_bs_a_1[i][j]= get_mv_bs(sel_cand_1[i][31:0], mvbs_neib_a[i][j], mrg2ccu_push, mvbs_a_avail[i][j], j[1:0]);
        end
    end
end

always@(*) begin : irpu_mrg_wd_blk
    integer i;
    for(i=0 ; i<3 ; i++) begin
        irpu_mrg_wd[i]={
            {reg_avc_mode ? cand_q[3][0+:8] : {cand_sel[i] ? {mv_bs_b_1[i],mv_bs_a_1[i]} : {mv_bs_b_0[i],mv_bs_a_0[i]}}, // md, motion level 8
             md_mvl[i]},
            {cand_sel[i] ? sel_cost_1[i][(VC_SATD_NB+1)+:(VC_SSE_NB+1)] : sel_cost_0[i][(VC_SATD_NB+1)+:(VC_SSE_NB+1)]}, // sse   26+1
            {cand_sel[i] ? sel_cost_1[i][0+: (VC_SATD_NB+1)]      : sel_cost_0[i][0+: (VC_SATD_NB+1)]      }, // satd  16+1
            {cand_sel[i] ? sel_cand_1[i][41:34]                   : sel_cand_0[i][41:34]                   }, // poc diff 8
            {cand_sel[i] ? sel_cand_1[i][42]                      : sel_cand_0[i][42]                      }, // long   1
            {cand_sel[i]},                                                                                   // mrg idx 1
            {cand_sel[i] ? {2'd0,sel_cand_1[i][33:32]}            : {2'd0,sel_cand_0[i][33:32]}            }, // ref idx 4
            {cand_sel[i] ?  sel_cand_1[i][31:0]                   :  sel_cand_0[i][31:0]                   }  // cand mv 32
        };
    end
end

assign all_queue_empty = ~|{cmdq_empty_n, cand_empty_n, irpu_mrg_rdy};

always@(*) begin : chk_terminate_blk
	integer i;
	for(i=0 ; i<MAX_BLK_SZ ; i=i+1) begin
		gt0[i] = term_cnt[i]>0;
	end
end

assign	msb_one = find_msb_one(gt0);

always@(*) begin : mrg2ccu_fifo_pp
	integer i;
    for(i=0 ; i<MAX_BLK_SZ ; i++) begin
		mrg2ccu_push[i] = (fsm_term_cs[TERM_FLUSH] & msb_one[i]) | cand_pop[2*i+0];
		irpu_mrg_hsk[i] = irpu_mrg_rdy[i] & irpu_mrg_ack[i];
	end
end

// function/task

function get_mv_bs;
    input [31:0] cand_mv;
    input [31:0] neib_mv;
    input  [2:0] blk_sz; // one hot b2:32, b1:16, b0:8
    input        neib_avail;
    input  [1:0] idx;    // 0~3
    reg  [15:0]  cand_mv_x;
    reg  [15:0]  cand_mv_y;
    reg  [15:0]  neib_mv_x;
    reg  [15:0]  neib_mv_y;
    reg signed [16:0] mv_x_diff;
    reg signed [16:0] mv_y_diff;
    reg signed [16:0] mvx_abs;
    reg signed [16:0] mvy_abs;
    reg en;
begin
    {cand_mv_y, cand_mv_x} = cand_mv;
    {neib_mv_y, neib_mv_x} = neib_mv;
    mv_x_diff = $signed(cand_mv_x) - $signed(neib_mv_x);
    mv_y_diff = $signed(cand_mv_y) - $signed(neib_mv_y);
    mvx_abs = mv_x_diff[16] ? -mv_x_diff : mv_x_diff;
    mvy_abs = mv_y_diff[16] ? -mv_y_diff : mv_y_diff;

    en = blk_sz[2] ? 1 :
         blk_sz[1] ? idx<=1 :
                     idx==0;

    get_mv_bs = (en & neib_avail) ? (mvx_abs>=4 | mvy_abs>=4) : 0;
end
endfunction

function [9:0] get_md_abs_sum_clip;
    input [31:0] cand_0;
    input [31:0] cand_1;
    reg signed [16:0] mvx_sum;
    reg signed [16:0] mvy_sum;
    reg [16:0] mvx_abs;
    reg [16:0] mvy_abs;
    reg [13:0] mvx_shf;
    reg [13:0] mvy_shf;
    reg [13:0] mv_abs_sum;
    reg [ 9:0] mv_abs_sum_clip;
begin
    mvx_sum = $signed(cand_0[15: 0]) + $signed(cand_1[15: 0]);
    mvy_sum = $signed(cand_0[31:16]) + $signed(cand_1[31:16]);
    mvx_abs = mvx_sum[16] ? -(mvx_sum) : mvx_sum;
    mvy_abs = mvy_sum[16] ? -(mvy_sum) : mvy_sum;
    mvx_shf = mvx_abs[16:3];
    mvy_shf = mvy_abs[16:3];
    mv_abs_sum = mvx_shf[12:0] + mvy_shf[12:0];
    mv_abs_sum_clip = (mv_abs_sum > 14'd1023) ? 1023 : mv_abs_sum[9:0];
    get_md_abs_sum_clip = mv_abs_sum_clip;
end
endfunction

function reg [MAX_BLK_SZ-1:0] find_msb_one;
    input [MAX_BLK_SZ-1:0] data;
    reg is_found;
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

function [1:0] fsm_mrg_cand;
    input rdy;
    input the_other_rdy;
    input slice_start;
    input [1:0] fsm_mrg_cand_cs;
    localparam  IDLE =0,
                RDY  =1;
begin
    fsm_mrg_cand = 0;
    case(1) //synopsys parallel_case
        fsm_mrg_cand_cs[IDLE] : begin // IDLE
            if(rdy)
                fsm_mrg_cand[RDY] = 1;
            else
                fsm_mrg_cand[IDLE] = 1;
        end
        fsm_mrg_cand_cs[RDY] : begin
            if(the_other_rdy)
                fsm_mrg_cand[IDLE] = 1;
            else
                fsm_mrg_cand[RDY] = 1;
        end
    endcase
    if( slice_start )
        fsm_mrg_cand[0] = 1;
end
endfunction

function [3:0] get_fsm_mrg_flow_ns;
input		cand_rdy;
input		blk_en;
input		mrg_cand_rdy_0;
input		mrg_mc_cand_rdy_0;
input		mrg2mc_cand_hsk;
input		mc2mrg_cost_hsk;
input		idx;
input		cand_diff;
input		other_done;
input [3:0]	fsm_mrg_flow_cs;
/*
localparam	MRG_IDLE = 0,
			MRG_CAND_RDY = 1,
			MRG_MC_CAND_RDY = 2,
			MRG_DONE = 3;
*/
reg   [3:0]    fsm_mrg_flow_ns;
begin
    fsm_mrg_flow_ns = 0;
    case(1) // synopsys parallel_case
        fsm_mrg_flow_cs[MRG_IDLE]: begin
            if(cand_rdy & blk_en)
                fsm_mrg_flow_ns[MRG_CAND_RDY] = 1;
            else
                fsm_mrg_flow_ns[MRG_IDLE] = 1;
        end
        fsm_mrg_flow_cs[MRG_CAND_RDY]: begin
            if(!idx) begin
                if(mrg2mc_cand_hsk)
                    fsm_mrg_flow_ns[MRG_MC_CAND_RDY] = 1;
                else
                    fsm_mrg_flow_ns[MRG_CAND_RDY] = 1;
            end
            else begin
                if(!cand_diff)
                    fsm_mrg_flow_ns[MRG_IDLE] = 1;
                else if(mrg_cand_rdy_0)
                    fsm_mrg_flow_ns[MRG_CAND_RDY] = 1;
                else if(mrg2mc_cand_hsk)
                    fsm_mrg_flow_ns[MRG_MC_CAND_RDY] = 1;
                else
                    fsm_mrg_flow_ns[MRG_CAND_RDY] = 1;
            end
        end
        fsm_mrg_flow_cs[MRG_MC_CAND_RDY]: begin
            if(!idx) begin
                if(mc2mrg_cost_hsk)
                    fsm_mrg_flow_ns[MRG_DONE] = 1;
                else
                    fsm_mrg_flow_ns[MRG_MC_CAND_RDY] = 1;
            end
            else begin
                if(mrg_mc_cand_rdy_0)
                    fsm_mrg_flow_ns[MRG_MC_CAND_RDY] = 1;
                else if(mc2mrg_cost_hsk)
                    fsm_mrg_flow_ns[MRG_DONE] = 1;
                else
                    fsm_mrg_flow_ns[MRG_MC_CAND_RDY] = 1;
            end
        end
        fsm_mrg_flow_cs[MRG_DONE]: begin
            if(!idx) begin
                if(!cand_diff) begin
                    fsm_mrg_flow_ns[MRG_IDLE] = 1;
                end
                else begin
                    if( other_done )
                        fsm_mrg_flow_ns[MRG_IDLE] = 1;
                    else
                        fsm_mrg_flow_ns[MRG_DONE] = 1;
                end
            end
            else begin
                fsm_mrg_flow_ns[MRG_IDLE] = 1;
            end
        end
    endcase
end
get_fsm_mrg_flow_ns = fsm_mrg_flow_ns;
endfunction

// instantiation

vc_mvp_ctrl
#(	
	.MAX_BLK_SZ (MAX_BLK_SZ), // 3:(blk32, blk16, blk8), 2:(blk16, blk8), 1:blk8
   	.NUM_REF    (NUM_REF),
	.AMVP_OR_MRG(AMVP_OR_MRG)
)
U_VC_MRG_CTRL
(
// output
.cur_ref_idx            ( cur_ref_idx),
.cu_blk_en              ( cu_blk_en),
.cu_cmd_out             ( cu_cmd_out),
.neib_cu_start          ( neib_cu_start),
.cand_cu_start          ( cand_cu_start),
.empty_n                ( cmdq_empty_n),
.pop                    ( ),
.dbg_fsm_mvp_cs         ( dbg_fsm_mvp_cs),
.blk_sz_lat             ( blk_sz_lat),
.n_blk_sz               ( n_blk_sz),
// input
.clk_vc                 ( clk_vc),
.vc_rst_z               ( vc_rst_z),
.reg_i_slice            ( reg_i_slice),
.reg_slice_go           ( reg_slice_go),
.reg_avc_mode           ( reg_avc_mode),
.reg_num_ref_l0_act_m1  ( 4'd0),
.cur_ctu_start          ( cur_ctu_start),
.cur_cu_start           ( cur_cu_start),
.cur_cu_x               ( cur_cu_x),
.cur_cu_y               ( cur_cu_y),
.cur_cu_b_avail         ( cur_cu_b_avail),
.cur_cu_a_avail         ( cur_cu_a_avail),
.cur_cu_is_zmv          ( cur_cu_is_zmv),
.cur_cu_is_skip         ( cur_cu_is_skip),
.cur_cu_terminate       ( cur_cu_terminate),
.is_pic_right           ( 3'd0),
.neib_done_con          ( neib_done_con),
.cand_blk_done          ( cand_blk_done),
.cand_blk_idle          ( cand_blk_idle)
);

vc_mvp_cand_gen
#(
    .NUM_REF (NUM_REF),
    .AMVP_OR_MRG (0),
    .MVP_SCALE_EN (MVP_SCALE_EN),
    .FSMW    (FSMW)
)
U_VC_MRG_CAND_GEN
(
// output
    .cand_mv            ( cand_mv),
    .cand_rdy           ( cand_rdy),
    .cand_blk_done      ( cand_blk_done),
    .cand_blk_idle      ( cand_blk_idle),
    .dbg_fsm_cand_cs    ( dbg_fsm_cand_cs),
// input
    .clk_vc             ( clk_vc),
    .vc_rst_z           ( vc_rst_z),
    .cand_cu_start      ( cand_cu_start),
    .mrg_cand_nr_m1     ( mrg_cand_nr_m1),
    .reg_slice_go       ( reg_slice_go),
    .reg_tmp_mvp_flag   ( reg_tmp_mvp_flag),
    .reg_cur_poc        ( reg_cur_poc),
    .reg_num_ref_l0_act_m1( reg_num_ref_l0_act_m1),
    .cu_cmd_out         ( cu_cmd_out_sel),
    .neib_b             ( neib_b),
    .neib_a             ( neib_a),
    .col_c              ( col_c),
    .col_c_avail        ( col_c_avail),
    .reflist_info       ( reflist_info),
    .cur_ref_idx        ( cur_ref_idx[1:0]),
    .col_ref_idx        ( reg_col_ref_idx[1:0]),
    .reg_avc_mode       ( reg_avc_mode)
);

// 0: blk8 cand0
// 1: blk8 cand1
// 2: blk16 cand0
// 3: blk16 cand1
// 4: blk32 cand0
// 5: blk32 cand1

generate
    for(i=0 ; i<6; i=i+1) begin : cand_fifo

    //blk_sz[45:43], long[42],pocdiff[41:34], ref_idx[33:32], mv[31:0]
    sht_mdl
    #(
        .DEPTH    (1),
        .DATA_W   (46),  // cand + cand_valid
        .RST_EN   (1)
    )
    U_CAND_OUT_FIFO(
    // output
        .full_n   (),
        .n_full_n (),
        .empty_n  (cand_empty_n[i]),
        .n_empty_n(),
        .q        (cand_q[i]),
    // input
        .clk      (clk_vc),
        .rstz     (vc_rst_z),
        .push     (cand_push[i]),
        .pop      (cand_pop[i]),
        .d        (cand_d[i])
    );
    end
endgenerate

generate
    for(i=0 ; i<3 ; i++) begin : mrg2ccu_fifo_blk
        sht_mdl
        #(
            .DEPTH          (1),
            //.ADDR_LG2_W   (1),
            .DATA_W         (MRG2CCU_DW),
            .RST_EN         (1)
        )
        U_MRG2CCU_FIFO(
        // output
            .full_n         (),
            .n_full_n       (),
            .empty_n        (irpu_mrg_rdy[i]),
            .n_empty_n      (),
            .q              (irpu_mrg_rd[i]),
        // input
            .clk            (clk_vc),
            .rstz           (vc_rst_z),
            .push           (mrg2ccu_push[i]),
            .pop            (irpu_mrg_hsk[i]),
            .d              (irpu_mrg_wd[i])
        );
    end
endgenerate

// state machine

always@(*) begin : fsm_mv_gain
    fsm_mv_gain_ns = 0;
    case(1) // synopsys parallel_case
        fsm_mv_gain_cs[MVG_IDLE]: begin
            if(reg_avc_mode ? cand_push[2] : cand_push[1])begin
                if(reg_avc_mode)
                    fsm_mv_gain_ns[MVG_BLK16] = 1;
                else
                    fsm_mv_gain_ns[MVG_BLK8] = 1;
            end
            else
                fsm_mv_gain_ns[MVG_IDLE] = 1;
        end
        fsm_mv_gain_cs[MVG_BLK8]: begin
            if(mvg_cnt == 5) begin
                if( cu_empty_n_reg[1])
                    fsm_mv_gain_ns[MVG_BLK16] = 1;
                else
                    fsm_mv_gain_ns[MVG_IDLE] = 1;
            end
            else
                fsm_mv_gain_ns[MVG_BLK8] = 1;
        end
        fsm_mv_gain_cs[MVG_BLK16]: begin
            if(mvg_cnt == 5) begin
                if(reg_avc_mode)
                    fsm_mv_gain_ns[MVG_IDLE] = 1;
                else if(cu_empty_n_reg[2])
                    fsm_mv_gain_ns[MVG_BLK32] = 1;
                else
                    fsm_mv_gain_ns[MVG_IDLE] = 1;
            end
            else
                fsm_mv_gain_ns[MVG_BLK16] = 1;
        end
        fsm_mv_gain_cs[MVG_BLK32]: begin
            if(mvg_cnt == 5) begin
                fsm_mv_gain_ns[MVG_IDLE] = 1;
            end
            else
                fsm_mv_gain_ns[MVG_BLK32] = 1;
        end
    endcase
end

always@(*) begin : fsm_terminal_ctrl
    fsm_term_ns = 0;
    case(1) // synopsys parallel_case
        fsm_term_cs[TERM_IDLE]: begin
            if( !cur_cu_start & cur_cu_terminate )
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

always@(*) begin : fsm_mc_cand_done
    integer i;
    for(i=0 ; i< 3 ; i++) begin
        fsm_mc_done_ns[i] = 0;
        case(1) // synopsys parallel_case
            fsm_mc_done_cs[i][MC_IDLE]: begin
                if( reg_avc_mode ? mrg2mc_cand_rdy[i] : (cand_rdy[1] & cu_cmd_out_sel[14+i]) ) begin
                    if(cand1_ena[i]) begin
                        if(fsm_mrg_flow_cs[2*i+0][MRG_MC_CAND_RDY])
                            fsm_mc_done_ns[i][MC_WAIT_HSK_1] = 1;
                        else begin
                            if(mrg2mc_cand_hsk[i])
                                fsm_mc_done_ns[i][MC_WAIT_HSK_1] = 1;
                            else
                                fsm_mc_done_ns[i][MC_WAIT_HSK_0] = 1;
                        end
                    end
                    else begin
                        if(fsm_mrg_flow_cs[2*i+0][MRG_MC_CAND_RDY])
                            fsm_mc_done_ns[i][MC_DONE] = 1;
                        else begin
                            if(mrg2mc_cand_hsk[i])
                                fsm_mc_done_ns[i][MC_DONE] = 1;
                            else
                                fsm_mc_done_ns[i][MC_WAIT_HSK_0] = 1;
                        end
                    end
                end
                else
                    fsm_mc_done_ns[i][MC_IDLE] = 1;
            end
            fsm_mc_done_cs[i][MC_WAIT_HSK_0]: begin
                if(mrg2mc_cand_hsk[i]) begin
                    if(cand_diff[i])
                        fsm_mc_done_ns[i][MC_WAIT_HSK_1] = 1;
                    else
                        fsm_mc_done_ns[i][MC_DONE] = 1;
                end
                else
                    fsm_mc_done_ns[i][MC_WAIT_HSK_0] = 1;
            end
            fsm_mc_done_cs[i][MC_WAIT_HSK_1]: begin
                if(mrg2mc_cand_hsk[i])
                    fsm_mc_done_ns[i][MC_DONE] = 1;
                else
                    fsm_mc_done_ns[i][MC_WAIT_HSK_1] = 1;
            end
            fsm_mc_done_cs[i][MC_DONE]: begin
                fsm_mc_done_ns[i][MC_IDLE] = 1;
            end
        endcase
    end
end

// sequence logic

always@(posedge clk_vc or negedge vc_rst_z) begin
    if(~vc_rst_z)
        cu_empty_n_reg <= 0;
    else if(reg_slice_go)
        cu_empty_n_reg <= 0;
    else if(neib_cu_start)
        cu_empty_n_reg <= cmdq_empty_n;
end

always@(posedge clk_vc or negedge vc_rst_z) begin
    if(~vc_rst_z) begin
        fsm_mv_gain_cs <= 1;
    end
    else if(reg_slice_go)
        fsm_mv_gain_cs <= 1;
    else if( fsm_mv_gain_cs != fsm_mv_gain_ns )begin
        fsm_mv_gain_cs <= fsm_mv_gain_ns;
    end
end

always@(posedge clk_vc or negedge vc_rst_z) begin
    if(~vc_rst_z) begin
        md_mvl[0] <= 0;
        md_mvl[1] <= 0;
        md_mvl[2] <= 0;
    end
    else if(reg_slice_go) begin
        md_mvl[0] <= 0;
        md_mvl[1] <= 0;
        md_mvl[2] <= 0;
    end
    else begin
        if(fsm_mv_gain_cs[MVG_BLK8] & mvg_cnt==5)
            md_mvl[0] <= mul_add_clip;
        if(fsm_mv_gain_cs[MVG_BLK16] & mvg_cnt==5)
            md_mvl[1] <= mul_add_clip;
        if(fsm_mv_gain_cs[MVG_BLK32] & mvg_cnt==5)
            md_mvl[2] <= mul_add_clip;
    end
end

always@(posedge clk_vc) begin
    if(md_cal_en_or & mvg_cnt>0 & mvg_cnt<5)
        mul_add_accu <= n_mul_add_accu;
end

always@(posedge clk_vc or negedge vc_rst_z)begin : mvg_cnt_blk // use adder as multiplier (6 items add 5 times)
    if(~vc_rst_z) begin
        mvg_cnt <= 0;
    end
    else if(reg_slice_go)
        mvg_cnt <= 0;
    else begin
        if( md_cal_en_or )
            if(mvg_cnt==5)
                mvg_cnt <= 0;
            else
                mvg_cnt <= mvg_cnt + 1;
    end
end

/*
always@(posedge clk_vc) begin
	if(cand_push_0 & !cand_push_1) 
		cand_mv_0_reg <= cand_mv0_blk_sz_sel;
end
*/

always@(posedge clk_vc or negedge vc_rst_z)begin : md_cal_en_blk
    integer i;
    if(~vc_rst_z) begin
        for(i=0; i<3; i++)
            md_cal_en[i] <= 0;
    end
    else if(reg_slice_go) begin
        for(i=0; i<3; i++)
            md_cal_en[i] <= 0;
    end
    else begin
        for(i=0; i<3; i++) begin
            if(irpu_mrg_hsk[i])
                md_cal_en[i] <= 0;
            else if(reg_avc_mode ? cand_push[2*i] : cand_push[2*i+1]) // 1, 3, 5
                md_cal_en[i] <= 1;
        end
    end
end

always@(posedge clk_vc or negedge vc_rst_z)begin : toggle_cost_blk
    integer i;
    if(~vc_rst_z) begin
        toggle_cost <= 0;
    end
    else if(reg_slice_go)
        toggle_cost <= 0;
    else if(~reg_avc_mode)begin
        for(i=0 ; i<3 ; i++) begin
            if(irpu_mrg_rdy[i] & irpu_mrg_ack[i])
                toggle_cost[i] <= 0;
            else if( mc2mrg_cost_hsk[i] )
                toggle_cost[i] <= !toggle_cost[i];
        end
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
                term_cnt[i] <= term_cnt[i] -1;
    end
    else if( cur_cu_terminate )begin
        for(i=0 ; i< MAX_BLK_SZ ; i=i+1)
            if(cur_cu_start[i])
                term_cnt[i] <= term_cnt[i] + 1;
    end
end

always@(posedge clk_vc ) begin : cost_q_reg_blk
    integer i;
    for(i=0 ; i<3 ; i++) begin
        if( !toggle_cost[i] & mc2mrg_cost_hsk[i] & ~reg_avc_mode) begin
            cost_q_reg[i] <= mc2mrg_cost_data[i];
        end
    end
end

always@(posedge clk_vc or negedge vc_rst_z)begin
    if(~vc_rst_z) begin
        fsm_term_cs <= 1;
    end
    else if(reg_slice_go)
        fsm_term_cs <= 1;
    else if( fsm_term_cs != fsm_term_ns )begin
        fsm_term_cs <= fsm_term_ns;
    end
end
/*
always@(posedge clk_vc or negedge vc_rst_z)begin
    if(~vc_rst_z) begin
        fsm_mrg_cand_cs[0] <= 1;
    end
    else if( fsm_mrg_cand_cs[0] != fsm_mrg_cand_ns[0] )begin
        fsm_mrg_cand_cs[0] <= fsm_mrg_cand_ns[0];
    end
end

always@(posedge clk_vc or negedge vc_rst_z)begin
    if(~vc_rst_z) begin
        fsm_mrg_cand_cs[1] <= 1;
    end
    else if( fsm_mrg_cand_cs[1] != fsm_mrg_cand_ns[1] )begin
        fsm_mrg_cand_cs[1] <= fsm_mrg_cand_ns[1];
    end
end
*/
always@(posedge clk_vc )begin : mrg_cand_blk
    integer i;
//    if( !cand_rdy ) begin
    if(reg_avc_mode ? cand_push[2] : cand_rdy[0])
        cand_r <= {cu_cmd_out_sel[16:14],cand_mv[0] };
//        for(i=0 ; i< 2 ; i=i+1) begin
//            if(cand_rdy[i])
//                cand_r[i] <= {cu_cmd_out_sel[16:14],cand_mv[i] };
//        end
//    end
end

always@(posedge clk_vc or negedge vc_rst_z)begin
    if(~vc_rst_z) begin
//        cuxy[1] <= 0;
//        cuxy[2] <= 0;
        cu_x16 <= 0;
        cu_y16 <= 0;
        cu_x32 <= 0;
        cu_y32 <= 0;
    end
    else if(reg_slice_go) begin
        cu_x16 <= 0;
        cu_y16 <= 0;
        cu_x32 <= 0;
        cu_y32 <= 0;
    end
    else if(|cur_cu_start[2:1])begin
        if(cur_cu_start[1]) begin
//            cuxy[1] <= {cur_cu_y, cur_cu_x};
            {cu_y16, cu_x16} <= {cur_cu_y[2:1], cur_cu_x[2:1]};
        end
        if(cur_cu_start[2]) begin
//            cuxy[2] <= {cur_cu_y, cur_cu_x};
            {cu_y32, cu_x32} <= {cur_cu_y[2], cur_cu_x[2]};
        end
    end
end

/*
always@(posedge clk_vc) begin
	if(|cur_cu_start) begin
        neib_b_avail[0] <=  cur_cu_b_avail[0][1];
		neib_b_avail[1] <= |cur_cu_start[2:1] ? cur_cu_b_avail[0][0] : 0;
		neib_b_avail[2] <=  cur_cu_start[2]   ? cur_cu_b_avail[1][0] : 0;
		neib_b_avail[3] <=  cur_cu_start[2]   ? cur_cu_b_avail[2][1] : 0;

        neib_a_avail[0] <=  cur_cu_a_avail[0][1];
		neib_a_avail[1] <= |cur_cu_start[2:1] ? cur_cu_a_avail[1][1] : 0;
		neib_a_avail[2] <=  cur_cu_start[2]   ? cur_cu_a_avail[1][0] : 0;
		neib_a_avail[3] <=  cur_cu_start[2]   ? cur_cu_a_avail[2][1] : 0;
    end
end
*/

always@(posedge clk_vc) begin
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
    end

    if(cur_cu_start[0]) begin
        blk8_neib_b_avail <= cur_cu_b_avail[0][1];
        blk8_neib_a_avail <= cur_cu_a_avail[0][1];
    end
end

always@(posedge clk_vc or negedge vc_rst_z) begin : mrg_cand_rdy_0_blk
    integer i;
    if(~vc_rst_z) begin
        for(i=0 ; i<3 ; i++) begin
            mrg_cand_rdy[i][0] <= 0;
        end
    end
    else if(reg_slice_go) begin
        for(i=0 ; i<3 ; i++) begin
            mrg_cand_rdy[i][0] <= 0;
        end
    end
	else begin
		for(i=0 ; i<3 ; i++) begin
            if(reg_avc_mode ? (i == 1 & avc_mvp_push) : (cand_rdy[0] & cu_cmd_out_sel[14+i]))
				mrg_cand_rdy[i][0] <= 1;
			else if(mrg2mc_cand_hsk[i] & mrg_cand_rdy[i][0])
                mrg_cand_rdy[i][0] <= 0;
		end
    end
end

always@(posedge clk_vc or negedge vc_rst_z) begin : mrg_cand_rdy_1_blk
    integer i;
    if(~vc_rst_z) begin
        for(i=0 ; i<3 ; i++) begin
            mrg_cand_rdy[i][1]   <= 0;
            mrg2mc_cand_nb[i]    <= 0;
        end
    end
    else if(reg_slice_go)begin
        for(i=0 ; i<3 ; i++) begin
            mrg_cand_rdy[i][1]   <= 0;
            mrg2mc_cand_nb[i]    <= 0;
        end
    end
    else begin
        for(i=0 ; i<3 ; i++) begin
            if(cand_rdy[1] & cu_cmd_out_sel[14+i])
                {mrg2mc_cand_nb[i], mrg_cand_rdy[i][1]} <= {2{cand1_ena[i]}};
//            if(cand_rdy[1] & cu_cmd_out_sel[14+i]) begin
//                if(cand_rdy[0])begin
//                    mrg_cand_rdy[i][1] <= cand_mv[0][0+:34]    != cand_mv[1][0+:34];
//                    mrg2mc_cand_nb[i] <= cand_mv[0][0+:34]    != cand_mv[1][0+:34];
//                end
//                else begin
//                    mrg_cand_rdy[i][1] <= cand_q[i*2+0][0+:34] != cand_mv[1][0+:34];
//                    mrg2mc_cand_nb[i] <= 0;
//                end
//            end
            else if(mrg2mc_cand_hsk[i] & !mrg_cand_rdy[i][0])begin
                mrg_cand_rdy[i][1]   <= 0;
                mrg2mc_cand_nb[i]    <= 0;
            end
        end
    end
end

always@(posedge clk_vc or negedge vc_rst_z) begin : cand_diff_blk
    integer i;
    if(~vc_rst_z) begin
        for(i=0 ; i<3 ; i++) begin
            cand_diff[i] <= 0;
        end
    end
    else if(reg_slice_go)
        cand_diff    <= 0;
    else begin
        for(i=0 ; i<3 ; i++) begin
            if(cand_rdy[1] & cu_cmd_out_sel[14+i]) cand_diff[i]    <= cand1_ena[i];
//            if( &cand_rdy & cu_cmd_out_sel[14+i]) begin
//                cand_diff[i] <= cand_mv[0][0+:34]    != cand_mv[1][0+:34];
//            end
//            else if(cand_rdy[1] & cu_cmd_out_sel[14+i] ) begin
//                cand_diff[i] <= cand_q[i*2+0][0+:34] != cand_mv[1][0+:34];
//            end
        end
    end
end

always@(*)begin: cal_mv_diff
    integer i;
    reg [1:0][1:0] ref_idx;
    reg [1:0][15:0] mvx;
    reg [1:0][15:0] mvy;
    reg cand_eq;
    reg cand_gt_thr;

    cand_eq          = 0;
    cand_gt_thr      = 0;
    cand1_ena        = 0;
    {ref_idx[1], mvy[1], mvx[1]}        = cand_mv[1][0+:34];
    for(i = 0; i < 3; i++)begin
        if(&cand_rdy) {ref_idx[0], mvy[0], mvx[0]}      = cand_mv[0][0+:34];
//        else           {ref_idx[0], mvy[0], mvx[0]}      = cand_mv[i*2][0+:34];
        else           {ref_idx[0], mvy[0], mvx[0]}      = cand_r[0+:34];

        cand_eq     = {ref_idx[1], mvy[1], mvx[1]} == {ref_idx[0], mvy[0], mvx[0]};
        if(i==0)
            cand_gt_thr = mrg_cons_mv(mvx[0], mvy[0], mvx[1], mvy[1], reg_enc_mrg_mvx_thr, reg_enc_mrg_mvy_thr);
        else
            cand_gt_thr = !cand_eq;

        if(cand_eq)
            cand1_ena[i]    = 0;
        else if(reg_enc_cons_mrg & ref_idx[1] == ref_idx[0])
            cand1_ena[i]    = cand_gt_thr;
        else
            cand1_ena[i]    = 1;
    end
end

function mrg_cons_mv;
    input [15:0] mvx0;
    input [15:0] mvy0;
    input [15:0] mvx1;
    input [15:0] mvy1;
    input [ 3:0] reg_enc_mrg_mvx_thr;
    input [ 3:0] reg_enc_mrg_mvy_thr;
    reg signed [16:0] diff_mvx;
    reg signed [16:0] diff_mvy;
    reg signed [15:0] abs_mvx;
    reg signed [15:0] abs_mvy;
begin
    diff_mvx    = $signed(mvx0) - $signed(mvx1);
    diff_mvy    = $signed(mvy0) - $signed(mvy1);
    abs_mvx     = diff_mvx[16] ? -diff_mvx[15:0] : diff_mvx[15:0];
    abs_mvy     = diff_mvy[16] ? -diff_mvy[15:0] : diff_mvy[15:0];
    mrg_cons_mv = abs_mvx >= reg_enc_mrg_mvx_thr |
                  abs_mvy >= reg_enc_mrg_mvy_thr;
end
endfunction

always@(posedge clk_vc or negedge vc_rst_z) begin : fsm_mrg_flow_cs_blk
    integer i;
    if(~vc_rst_z) begin
        for(i=0 ; i<3 ; i++) begin
            fsm_mrg_flow_cs[i*2+0] <= 1;
            fsm_mrg_flow_cs[i*2+1] <= 1;
        end
    end
    else begin
        for(i=0 ; i<3 ; i++) begin
            if(fsm_mrg_flow_cs[i*2+0] != fsm_mrg_flow_ns[i*2+0])
                fsm_mrg_flow_cs[i*2+0] <= fsm_mrg_flow_ns[i*2+0];
            if(fsm_mrg_flow_cs[i*2+1] != fsm_mrg_flow_ns[i*2+1])
                fsm_mrg_flow_cs[i*2+1] <= fsm_mrg_flow_ns[i*2+1];
        end
    end
end

always@(posedge clk_vc or negedge vc_rst_z) begin : fsm_mc_done_cs_blk
    integer i;
    if(~vc_rst_z) begin
        for(i=0 ; i<3 ; i++)
            fsm_mc_done_cs[i] <= 1;
    end
    else if(reg_slice_go)begin
        fsm_mc_done_cs[1]    <= 1;
        if(reg_avc_mode)begin
            fsm_mc_done_cs[0]   <= (1 << MC_DONE);
            fsm_mc_done_cs[2]   <= (1 << MC_DONE);
        end
        else begin
            fsm_mc_done_cs[0]   <= 1;
            fsm_mc_done_cs[2]   <= 1;
        end
    end
    else begin
        if(~reg_avc_mode & fsm_mc_done_cs[0] != fsm_mc_done_ns[0]) fsm_mc_done_cs[0]   <= fsm_mc_done_ns[0];
        if(                  fsm_mc_done_cs[1] != fsm_mc_done_ns[1]) fsm_mc_done_cs[1]   <= fsm_mc_done_ns[1];
        if(~reg_avc_mode & fsm_mc_done_cs[2] != fsm_mc_done_ns[2]) fsm_mc_done_cs[2]   <= fsm_mc_done_ns[2];
    end
end

always@(posedge clk_vc) begin : md_mv_blk
    integer i;
    for(i=0 ; i<3 ; i++) begin
        if( cand_push[i*2+0] )
            md_mv[i][0] <= cand_mv0_sel; 
        if( cand_push[i*2+1] )
            md_mv[i][1] <= cand_mv1_sel; 
    end
end

always@(posedge clk_vc) begin
    if(mvg_cnt==0)
        md_abs_sum_clip <= n_md_abs_sum_clip;
end

endmodule
