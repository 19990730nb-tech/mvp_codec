// -----------------------------------------------------------------------------
// AMVP scheduling and result-queue wrapper shared by encoder-compatible and
// decoder-compatible operation. It runs candidate generation per block size,
// exchanges encoder candidates with FME/CCU, and joins a separately registered
// decoder MVD transaction with the unique AVC median predictor.
//
// reg_avc_mode selects the AVC algorithm; codec_mode selects encode/decode
// direction.  The two controls are intentionally independent.
// -----------------------------------------------------------------------------
`include "ve_defines.v"
module	vc_amvp_top
#(
    parameter	NUM_REF = 2,
	parameter	MUL_REF = (NUM_REF > 1),
	parameter	MVP_SCALE_EN = 0,
    parameter	MAX_BLK_SZ = 2, // 3:blk32, 2:blk16
	parameter	VC_EN_BI_DIR = 0,  // 0: ref0 only, 1: bi direction
	parameter	VC_SATD_NB = 20,
    parameter	VC_SSE_NB = 40,
	parameter	VC_PIC_X_NB = 12,
	parameter	VC_PIC_Y_NB = 12,
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
// [DEC] Reconstructed motion transaction for the shared MC interface.
output                          irpu2ccu_rdy,
output                          dec_pending,
output                          dec_mv_valid,
output  [1:0][15:0]             dec_final_mv,
output  [1:0]                   dec_ref_idx,
output                          dec_part_mode,
output  [1:0]                   dec_sub_idx,
output  [2:0]                   dec_cu_x,
output  [2:0]                   dec_cu_y,
output  [VC_PIC_X_NB-1:0]       dec_pic_x,
output  [VC_PIC_Y_NB-1:0]       dec_pic_y,
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
// [DECODER] 0: encoder path, 1: decoder path. Decoder path is implemented
//           only when reg_avc_mode is also 1'b1.
input                           codec_mode,
// [DEC] CCU transaction.  [0] is X and [1] is Y.
input                           ccu2irpu_valid,
input   [1:0][15:0]             ccu2irpu_mvd,
input   [3:0]                   ccu2irpu_ref_idx,
input                           ccu2irpu_is_skip,
input                           ccu2irpu_part_mode,
input   [1:0]                   ccu2irpu_sub_idx,
input                           dec_mc_accept,
// CCU
input	[ 2:0]					irpu_amvp_ack,
// FME
input	[ 1:0]					fme2amvp_cand_rdy,
// Encoder input: {blk_sz[1:0], ref_idx[1:0], actual_mv_yx[31:0]}.
input	[1:0][36-1:0]			fme2amvp_cand_mv,
// CTU
input							cur_ctu_start,
// CU
input	[ 2:0]					cur_cu_start,
input	[ 2:0]					cur_cu_x,
input	[ 2:0]					cur_cu_y,
input   [VC_PIC_X_NB-1:0]       cur_pic_x,
input   [VC_PIC_Y_NB-1:0]       cur_pic_y,
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
wire	[MAX_BLK_SZ-1:0][CAND_NUM-1:0][51:0]cand_q;
reg		[MAX_BLK_SZ-1:0][CAND_NUM-1:0][51:0]cand_d;
reg		[MAX_BLK_SZ-1:0][CAND_NUM-1:0]		cand_push;
reg		[MAX_BLK_SZ-1:0]					cand_pop;

//reg		[MAX_BLK_SZ-1:0]	fme2amvp_cand_hsk;
reg		[MAX_BLK_SZ-1:0]	irpu_amvp_hsk;
wire	[AMVP2CCU_DW-1:0]	irpu_amvp_wd;
//cand sel
wire						fme_ref_idx;
wire	[51:0]				sel_cand_0;
wire	[51:0]				sel_cand_1;
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
// [DECODER] avc_dec_en deliberately excludes codec_mode=1/reg_avc_mode=0;
//           the HEVC-like decoder path is outside the scope of this revision.
wire                        avc_dec_en;
wire signed [15:0]          mv_data_x;
wire signed [15:0]          mv_data_y;
wire signed [15:0]          selected_mvp_x;
wire signed [15:0]          selected_mvp_y;
wire signed [16:0]          dec_mv_x_sum;
wire signed [16:0]          dec_mv_y_sum;
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

// [DEC] CCU transaction register and one-entry reconstructed-MV holding stage.
reg                         dec_pending_q;
reg     [1:0][15:0]         dec_mvd_q;
reg     [1:0]               dec_ref_idx_q;
reg                         dec_is_skip_q;
reg                         dec_part_mode_q;
reg     [1:0]               dec_sub_idx_q;
reg     [2:0]               dec_cu_x_q;
reg     [2:0]               dec_cu_y_q;
reg     [VC_PIC_X_NB-1:0]   dec_pic_x_q;
reg     [VC_PIC_Y_NB-1:0]   dec_pic_y_q;
reg                         dec_mv_valid_q;
reg     [1:0][15:0]         dec_final_mv_q;
reg                         dec_p8_active;
reg     [1:0]               dec_expected_sub_idx;
reg     [2:0]               dec_p8_base_x;
reg     [2:0]               dec_p8_base_y;

wire                        dec_order_ok;
wire                        dec_ref_idx_ok;
wire                        dec_partition_ok;
wire                        dec_input_queues_empty;
wire                        dec_accept;
wire                        dec_result_fire;
wire    [MAX_BLK_SZ-1:0]    dec_context_match;
wire    [MAX_BLK_SZ-1:0]    dec_cand_set_ready;
wire    [2:0]               dec_input_cu_x;
wire    [2:0]               dec_input_cu_y;
wire    [VC_PIC_X_NB-1:0]   dec_input_pic_x;
wire    [VC_PIC_Y_NB-1:0]   dec_input_pic_y;
wire    [2:0]               ctrl_cur_cu_start;
wire    [2:0]               ctrl_cur_cu_x;
wire    [2:0]               ctrl_cur_cu_y;
reg     [2:0][1:0]          ctrl_cur_cu_a_avail;
reg     [2:0][2:0]          ctrl_cur_cu_b_avail;
wire                        ctrl_cur_cu_is_skip;
wire    [3:0]               ctrl_num_ref_l0_act_m1;
wire    [1:0][33:0]         mv_fifo_d;

`ifndef SYNTHESIS
reg     [VC_PIC_X_NB+VC_PIC_Y_NB+42:0] dec_payload_prev;
reg                                     dec_stall_prev;
`endif

genvar						i,j,dec_i;

// combinational logic
// Normalize the differently sized neighbor arrays into [size][position]
// tables.  size 0/1/2 denotes 8x8/16x16/32x32; unused positions are zero.
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

// [DEC] P8x8 uses 8x8-slot coordinates in raster order.  The transaction is
// accepted only after the preceding sub-block has reached MC and updated the
// neighbor cache, so one pending record identifies the candidate context.
assign  dec_input_cu_x  = cur_cu_x + {2'd0, ccu2irpu_part_mode & ccu2irpu_sub_idx[0]};
assign  dec_input_cu_y  = cur_cu_y + {2'd0, ccu2irpu_part_mode & ccu2irpu_sub_idx[1]};
assign  dec_input_pic_x = cur_pic_x +
                          (ccu2irpu_part_mode & ccu2irpu_sub_idx[0] ? VC_PIC_X_NB'(8) : {VC_PIC_X_NB{1'b0}});
assign  dec_input_pic_y = cur_pic_y +
                          (ccu2irpu_part_mode & ccu2irpu_sub_idx[1] ? VC_PIC_Y_NB'(8) : {VC_PIC_Y_NB{1'b0}});

assign  dec_order_ok = !ccu2irpu_part_mode ?
                       ccu2irpu_sub_idx == 2'd0 && !dec_p8_active :
                       !dec_p8_active        ? ccu2irpu_sub_idx == 2'd0 :
                                              ccu2irpu_sub_idx == dec_expected_sub_idx &&
                                              cur_cu_x == dec_p8_base_x &&
                                              cur_cu_y == dec_p8_base_y;
assign  dec_ref_idx_ok = ccu2irpu_ref_idx[3:2] == 2'b00 &&
                         ccu2irpu_ref_idx[1:0] < NUM_REF;
assign  dec_partition_ok = !ccu2irpu_is_skip || !ccu2irpu_part_mode;
assign  dec_input_queues_empty = all_queue_empty && ~|mv_empty_n;
assign  irpu2ccu_rdy = avc_dec_en && !dec_pending_q && !dec_mv_valid_q &&
                       dec_input_queues_empty && dec_order_ok && dec_ref_idx_ok &&
                       dec_partition_ok;
assign  dec_accept = ccu2irpu_valid && irpu2ccu_rdy;

assign  dec_pending   = dec_pending_q;
assign  dec_mv_valid  = dec_mv_valid_q;
assign  dec_final_mv  = dec_final_mv_q;
assign  dec_ref_idx   = dec_ref_idx_q;
assign  dec_part_mode = dec_part_mode_q;
assign  dec_sub_idx   = dec_sub_idx_q;
assign  dec_cu_x      = dec_cu_x_q;
assign  dec_cu_y      = dec_cu_y_q;
assign  dec_pic_x     = dec_pic_x_q;
assign  dec_pic_y     = dec_pic_y_q;

assign  ctrl_cur_cu_start = avc_dec_en ?
                            (dec_accept ? (ccu2irpu_part_mode ? 3'b001 : 3'b010) : 3'b000) :
                            cur_cu_start;
assign  ctrl_cur_cu_x = avc_dec_en ? dec_input_cu_x : cur_cu_x;
assign  ctrl_cur_cu_y = avc_dec_en ? dec_input_cu_y : cur_cu_y;
assign  ctrl_cur_cu_is_skip = avc_dec_en ? 1'b0 : cur_cu_is_skip;
assign  ctrl_num_ref_l0_act_m1 = reg_num_ref_l0_act_m1;

always@(*) begin : dec_avail_mux
    ctrl_cur_cu_a_avail = cur_cu_a_avail;
    ctrl_cur_cu_b_avail = cur_cu_b_avail;
    // A1 is the reconstructed block on the left; B1 is the reconstructed block above.
    if(avc_dec_en && ccu2irpu_part_mode && ccu2irpu_sub_idx[0])
        ctrl_cur_cu_a_avail[0][1] = 1'b1;
    if(avc_dec_en && ccu2irpu_part_mode && ccu2irpu_sub_idx[1])
        ctrl_cur_cu_b_avail[0][1] = 1'b1;
end

assign  mv_fifo_d[0] = avc_dec_en ? {ccu2irpu_ref_idx[1:0], ccu2irpu_mvd} :
                                     fme2amvp_cand_mv[0][33:0];
assign  mv_fifo_d[1] = avc_dec_en ? {ccu2irpu_ref_idx[1:0], ccu2irpu_mvd} :
                                     fme2amvp_cand_mv[1][33:0];

generate
	if( NUM_REF == 1 ) begin : num_ref_equal_1_blk
		// Candidate FIFO index is ref_idx*CAND_NUM + candidate_idx.  A block
		// can leave the generator only after every required ref/candidate slot
		// is present (AVC consumes only its median candidate at index zero).
		always@(*) begin : cand_fifo_rdy_blk
            integer i;
			for(i=0 ; i<MAX_BLK_SZ ; i++) begin
				cand_fifo_rdy[i] = avc_dec_en ? dec_cand_set_ready[i] :
                                     (reg_avc_mode ? cand_empty_n[i][0] : &cand_empty_n[i]);
			end
        end
	end
	else if(NUM_REF == 2) begin : num_ref_equal_2_blk
        always@(*) begin : cand_fifo_rdy_blk
			integer i;
			for(i=0 ; i<MAX_BLK_SZ ; i++) begin
                cand_fifo_rdy[i] = avc_dec_en ? dec_cand_set_ready[i] :
                    ((reg_num_ref_l0_act_m1==0) ?
                     (reg_avc_mode ? cand_empty_n[i][0] : &cand_empty_n[i][1:0]) :
                     &cand_empty_n[i]);
			end
		end
	end
endgenerate

generate
    if(NUM_REF == 1) begin : dec_one_ref_ready
        for(dec_i=0 ; dec_i<MAX_BLK_SZ ; dec_i=dec_i+1)
            assign dec_cand_set_ready[dec_i] = cand_empty_n[dec_i][0];
    end
    else begin : dec_two_ref_ready
        for(dec_i=0 ; dec_i<MAX_BLK_SZ ; dec_i=dec_i+1)
            assign dec_cand_set_ready[dec_i] = cand_empty_n[dec_i][0] &&
                (reg_num_ref_l0_act_m1 == 0 || cand_empty_n[dec_i][2]);
    end
endgenerate

always@(*) begin : amvp_itf_blk
	integer i;
	for(i=0 ; i<MAX_BLK_SZ ; i++) begin
        amvp2fme_cand_ack[i]= avc_dec_en ? 1'b0 : mv_full_n[i];
		fme2amvp_cand_hsk[i]= fme2amvp_cand_rdy[i] & amvp2fme_cand_ack[i];
		irpu_amvp_dlat[i] 	= avc_dec_en ? 1'b0 : fme2amvp_cand_hsk[i];
        irpu_amvp_mv_info[i]= fme2amvp_cand_mv[i][33:0];
	end
end

assign	zmv = cu_cmd_out_sel[11];
assign  avc_dec_en = reg_avc_mode & codec_mode;

always@(*) begin : cand_out_fifio_ctrl
	// Store each generated candidate in its block-size/reference slot.  Because
	// cand_rdy[0] and cand_rdy[1] can arrive separately, pushes are independent.
	integer i,j;
	for(j=0 ; j<MAX_BLK_SZ ; j++) begin
        for(i=0 ; i<CAND_NUM ; i++) begin
			cand_push[j][i] = blk_sz[j] & (cur_ref_idx[0] == i[1]) & cand_rdy[i[0]];
			// Keep coordinates with the candidate so the decoder rendezvous can
			// prove that MVP and MVD describe the same partition.
			cand_d[j][i]	= {cu_cmd_out_sel[5:0], cu_cmd_out_sel[16:14], cand_mv[i[0]]};
		end
    end
end

generate
    for(dec_i=0 ; dec_i<MAX_BLK_SZ ; dec_i=dec_i+1) begin : dec_context_match_gen
        assign dec_context_match[dec_i] = dec_pending_q &&
            (dec_part_mode_q ? dec_i == 0 : dec_i == 1) &&
            mv_q[dec_i][33:32] == dec_ref_idx_q &&
            cand_q[dec_i][dec_ref_idx_q[0]*NUM_REF][51:49] == dec_cu_y_q &&
            cand_q[dec_i][dec_ref_idx_q[0]*NUM_REF][48:46] == dec_cu_x_q &&
            cand_q[dec_i][dec_ref_idx_q[0]*NUM_REF][45:43] ==
                (dec_i == 0 ? 3'b001 : 3'b010);
    end
endgenerate

always@(*) begin : max_blk_sz_assign_blk
	// Match one FME/MVD entry with a complete candidate set.  Give 8x8 priority
	// when both size queues are ready so only one result is assembled per cycle.
	integer j;
	for(j=0 ; j<MAX_BLK_SZ ; j++) begin
        if(avc_dec_en) begin
            cand_pop[j] = mv_empty_n[j] & cand_fifo_rdy[j] &
                          !dec_mv_valid_q & dec_context_match[j];
            mv_push[j] = dec_accept & (ccu2irpu_part_mode ? j == 0 : j == 1);
        end
        else begin
            if(j==0)
                cand_pop[j] = mv_empty_n[j] & cand_fifo_rdy[j];
            else
                cand_pop[j] = mv_empty_n[j] & cand_fifo_rdy[j] & !cand_pop[0];
            mv_push[j] = fme2amvp_cand_rdy[j] & amvp2fme_cand_ack[j];
        end
	end
end

assign	fme_ref_idx = cand_pop[1] ? mv_q[1][32] : mv_q[0][32];
// The FME/MVD FIFO carries {ref_idx, y, x}; use ref_idx to pick the two
// candidates generated for the same reference and block-size transaction.
assign	sel_cand_0 	= cand_pop[1] ? cand_q[1][fme_ref_idx*NUM_REF  ] : cand_q[0][fme_ref_idx*NUM_REF  ];
assign	sel_cand_1 	= cand_pop[1] ? cand_q[1][fme_ref_idx*NUM_REF+1] : cand_q[0][fme_ref_idx*NUM_REF+1];
assign  mv_data_x = cand_pop[1] ? mv_q[1][15: 0] : mv_q[0][15: 0];
assign  mv_data_y = cand_pop[1] ? mv_q[1][31:16] : mv_q[0][31:16];

// [DEC] AVC decoding always uses cand0 (the unique median predictor).  MVD is
// held in the transaction register, independently of candidate-generation time.
assign  selected_mvp_x = sel_cand_0[15: 0];
assign  selected_mvp_y = sel_cand_0[31:16];
assign  dec_mv_x_sum   = $signed({selected_mvp_x[15], selected_mvp_x}) +
                         $signed({dec_mvd_q[0][15], dec_mvd_q[0]});
assign  dec_mv_y_sum   = $signed({selected_mvp_y[15], selected_mvp_y}) +
                         $signed({dec_mvd_q[1][15], dec_mvd_q[1]});

// Encoder arithmetic remains unchanged; decoder final MV is held separately.
assign	mvx = zmv ? 16'sd0 : mv_data_x;
assign	mvy = zmv ? 16'sd0 : mv_data_y;

assign	{mvdabs_cand0[0], mvd_cand0[0]} = mvdabs_mvd(mvx, sel_cand_0[15: 0]); // cand0 x
assign	{mvdabs_cand0[1], mvd_cand0[1]} = mvdabs_mvd(mvy, sel_cand_0[31:16]); // cand0 y
assign	{mvdabs_cand1[0], mvd_cand1[0]} = mvdabs_mvd(mvx, sel_cand_1[15: 0]); // cand1 x
assign	{mvdabs_cand1[1], mvd_cand1[1]} = mvdabs_mvd(mvy, sel_cand_1[31:16]); // cand1 y
assign	mvdcost_cand0_sum = mvd_cost0[0] + mvd_cost0[1];
assign	mvdcost_cand1_sum = mvd_cost1[0] + mvd_cost1[1];
assign	cand_sel = ~codec_mode & ~reg_avc_mode &
                  (mvdcost_cand0_sum > mvdcost_cand1_sum);
assign	irpu_amvp_wd[31: 0] = {mvy, mvx};
assign	irpu_amvp_wd[47:32] = cand_sel ? mvd_cand1[0] : mvd_cand0[0];
assign	irpu_amvp_wd[63:48] = cand_sel ? mvd_cand1[1] : mvd_cand0[1];
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
	// Boundary strength is calculated against every edge segment covered by the
	// current block.  AVC additionally derives a 16x16 strength from its median
	// predictor for the encoder-side AMVP-to-Merge shortcut.
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

// Termination is delayed until commands, generated candidates and completed
// output records have drained.  TERM_FLUSH then emits any pending edge counts.
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
        amvp2ccu_push[i] = !avc_dec_en &&
                           ((fsm_term_cs[TERM_FLUSH] & msb_one[i]) | cand_pop[i]);
		irpu_amvp_hsk[i] = irpu_amvp_rdy[i] & irpu_amvp_ack[i] & !avc_dec_en;
	end
end

// [DECODER] The AVC AMVP-to-Merge candidate evaluation loop is encoder-only.
assign  avc_mvp_push    =   reg_avc_mode & ~codec_mode & amvp2ccu_push[1];
assign  avc_ref_idx     =   {1'b0, fme_ref_idx};
assign  avc_is_long     =   sel_cand_0[42];
assign  avc_pocdiff     =   sel_cand_0[34+:8];
assign	avc_mvd_gt4     =   {avc_bs_b, avc_bs_a};

assign  avc_zero_motion[0]  =   s_is_pic_top16  | (mvbs_b_avail[1][0] & mvbs_neib_b[1][0] == 0);
assign  avc_zero_motion[1]  =   s_is_pic_left16 | (mvbs_a_avail[1][0] & mvbs_neib_a[1][0] == 0);
assign  avc_mvpxy           =   |avc_zero_motion ? 0 : sel_cand_0[0+:32];
assign  dec_result_fire     = |cand_pop & dec_pending_q & !dec_mv_valid_q;

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
.reg_num_ref_l0_act_m1(ctrl_num_ref_l0_act_m1),
.cur_ctu_start      (cur_ctu_start),
.cur_cu_start       (ctrl_cur_cu_start),
.cur_cu_x           (ctrl_cur_cu_x),
.cur_cu_y           (ctrl_cur_cu_y),
.cur_cu_b_avail     (ctrl_cur_cu_b_avail),
.cur_cu_a_avail     (ctrl_cur_cu_a_avail),
.cur_cu_is_zmv      (cur_cu_is_zmv),
.cur_cu_is_skip     (ctrl_cur_cu_is_skip),
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
			// One-entry rendezvous slot per size/reference/candidate.  Payload:
			// y/x[51:46], blk_sz[45:43], long[42], pocdiff[41:34],
			// ref_idx[33:32], mv[31:0].
			sht_mdl 
            #(
				.DEPTH		(1),
				//.ADDR_LG2_W (1),
				.DATA_W 	(52),
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

// FME (encoder) or parsed MVD (decoder) is queued independently of candidate
// generation.  The common pop above joins the oldest motion record with its
// complete candidate set.
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
.d			(mv_fifo_d[1])
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
.d			(mv_fifo_d[0])
);

// Final AMVP-to-CCU record.  Low fields are common to encoder/decoder:
// pocdiff[77:70], longterm[69], mvp_l0_flag[68], ref_idx[67:64],
// mvd[63:32], mv[31:0]; wider configurations prepend SATD/SSE fields.
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
// On a terminate marker, stop producing the synthetic flush record until every
// in-flight queue is empty; then flush one block size at a time, MSB first.
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
// [DEC] CCU transaction register. It is released only after MC acceptance;
// that edge is also used by vc_mvp_top to update the neighbor cache.
always@(posedge clk_vc or negedge vc_rst_z) begin : dec_transaction_reg
    if(~vc_rst_z) begin
        dec_pending_q        <= 0;
        dec_mvd_q            <= 0;
        dec_ref_idx_q        <= 0;
        dec_is_skip_q        <= 0;
        dec_part_mode_q      <= 0;
        dec_sub_idx_q        <= 0;
        dec_cu_x_q           <= 0;
        dec_cu_y_q           <= 0;
        dec_pic_x_q          <= 0;
        dec_pic_y_q          <= 0;
        dec_mv_valid_q       <= 0;
        dec_final_mv_q       <= 0;
        dec_p8_active        <= 0;
        dec_expected_sub_idx <= 0;
        dec_p8_base_x        <= 0;
        dec_p8_base_y        <= 0;
    end
    else if(reg_slice_go || !avc_dec_en) begin
        dec_pending_q        <= 0;
        dec_mvd_q            <= 0;
        dec_ref_idx_q        <= 0;
        dec_is_skip_q        <= 0;
        dec_part_mode_q      <= 0;
        dec_sub_idx_q        <= 0;
        dec_cu_x_q           <= 0;
        dec_cu_y_q           <= 0;
        dec_pic_x_q          <= 0;
        dec_pic_y_q          <= 0;
        dec_mv_valid_q       <= 0;
        dec_final_mv_q       <= 0;
        dec_p8_active        <= 0;
        dec_expected_sub_idx <= 0;
        dec_p8_base_x        <= 0;
        dec_p8_base_y        <= 0;
    end
    else begin
        if(|cur_cu_start && !dec_pending_q && !dec_accept) begin
            dec_p8_active        <= 0;
            dec_expected_sub_idx <= 0;
        end
        if(dec_accept) begin
            dec_pending_q   <= 1;
            dec_mvd_q       <= ccu2irpu_mvd;
            dec_ref_idx_q   <= ccu2irpu_ref_idx[1:0];
            dec_is_skip_q   <= ccu2irpu_is_skip;
            dec_part_mode_q <= ccu2irpu_part_mode;
            dec_sub_idx_q   <= ccu2irpu_sub_idx;
            dec_cu_x_q      <= dec_input_cu_x;
            dec_cu_y_q      <= dec_input_cu_y;
            dec_pic_x_q     <= dec_input_pic_x;
            dec_pic_y_q     <= dec_input_pic_y;
            if(ccu2irpu_part_mode && ccu2irpu_sub_idx == 0) begin
                dec_p8_active        <= 1;
                dec_expected_sub_idx <= 0;
                dec_p8_base_x        <= cur_cu_x;
                dec_p8_base_y        <= cur_cu_y;
            end
            else if(!ccu2irpu_part_mode) begin
                dec_p8_active        <= 0;
                dec_expected_sub_idx <= 0;
            end
        end
        // [DEC] Reconstruct final MV: MV = MVP + MVD. P_Skip reuses the
        // existing AVC zero/median derivation and ignores parsed MVD.
        if(dec_result_fire) begin
            dec_mv_valid_q    <= 1;
            dec_final_mv_q[0] <= dec_is_skip_q ? avc_mvpxy[0] : dec_mv_x_sum[15:0];
            dec_final_mv_q[1] <= dec_is_skip_q ? avc_mvpxy[1] : dec_mv_y_sum[15:0];
        end
        if(dec_mc_accept) begin
            dec_pending_q  <= 0;
            dec_mv_valid_q <= 0;
            if(dec_part_mode_q) begin
                if(dec_sub_idx_q == 3) begin
                    dec_p8_active        <= 0;
                    dec_expected_sub_idx <= 0;
                end
                else begin
                    dec_p8_active        <= 1;
                    dec_expected_sub_idx <= dec_sub_idx_q + 1'b1;
                end
            end
        end
    end
end

`ifndef SYNTHESIS
always@(posedge clk_vc) begin : dec_protocol_checks
    if(vc_rst_z && avc_dec_en) begin
        if(ccu2irpu_valid && !dec_pending_q && !dec_ref_idx_ok)
            $error;
        if(ccu2irpu_valid && !dec_pending_q &&
           !ccu2irpu_part_mode && ccu2irpu_sub_idx != 0)
            $error;
        if(ccu2irpu_valid && !dec_pending_q && ccu2irpu_is_skip &&
           ccu2irpu_part_mode)
            $error;
        if(ccu2irpu_valid && !dec_pending_q && dec_p8_active &&
           !ccu2irpu_part_mode)
            $error;
        if(ccu2irpu_valid && !dec_pending_q && ccu2irpu_part_mode &&
           ccu2irpu_sub_idx != dec_expected_sub_idx)
            $error;
        if(dec_result_fire && !dec_is_skip_q &&
           dec_mv_x_sum[16] != dec_mv_x_sum[15])
            $warning;
        if(dec_result_fire && !dec_is_skip_q &&
           dec_mv_y_sum[16] != dec_mv_y_sum[15])
            $warning;
        if(dec_pending_q && !dec_mv_valid_q &&
           mv_empty_n[dec_part_mode_q ? 0 : 1] &&
           cand_fifo_rdy[dec_part_mode_q ? 0 : 1] &&
           !dec_context_match[dec_part_mode_q ? 0 : 1])
            $error;
        if(dec_stall_prev && dec_mv_valid_q && !dec_mc_accept &&
           dec_payload_prev !== {dec_final_mv_q, dec_ref_idx_q,
                                  dec_part_mode_q, dec_sub_idx_q,
                                  dec_cu_x_q, dec_cu_y_q,
                                  dec_pic_x_q, dec_pic_y_q})
            $error;
    end
end

always@(posedge clk_vc or negedge vc_rst_z) begin : dec_stall_check_reg
    if(~vc_rst_z) begin
        dec_payload_prev <= 0;
        dec_stall_prev   <= 0;
    end
    else begin
        dec_payload_prev <= {dec_final_mv_q, dec_ref_idx_q,
                             dec_part_mode_q, dec_sub_idx_q,
                             dec_cu_x_q, dec_cu_y_q,
                             dec_pic_x_q, dec_pic_y_q};
        dec_stall_prev <= avc_dec_en && dec_mv_valid_q && !dec_mc_accept;
    end
end
`endif

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
        if(ctrl_cur_cu_start[2]) begin
	    	blk32_neib_b_avail[0] <= cur_cu_b_avail[0][1];
	    	blk32_neib_b_avail[1] <= cur_cu_b_avail[0][0];
	    	blk32_neib_b_avail[2] <= cur_cu_b_avail[1][0];
            blk32_neib_b_avail[3] <= cur_cu_b_avail[2][1];

	    	blk32_neib_a_avail[0] <= cur_cu_a_avail[0][1];
	    	blk32_neib_a_avail[1] <= cur_cu_a_avail[1][1];
	    	blk32_neib_a_avail[2] <= cur_cu_a_avail[1][0];
	    	blk32_neib_a_avail[3] <= cur_cu_a_avail[2][1];
        end

        if(ctrl_cur_cu_start[1]) begin
            blk16_neib_b_avail[0] <= ctrl_cur_cu_b_avail[0][1];
            blk16_neib_b_avail[1] <= ctrl_cur_cu_b_avail[0][0];

            blk16_neib_a_avail[0] <= ctrl_cur_cu_a_avail[0][1];
            blk16_neib_a_avail[1] <= ctrl_cur_cu_a_avail[1][1];

            s_is_pic_top16      <=  is_pic_top16;
            s_is_pic_left16     <=  is_pic_left16;
        end

        if(ctrl_cur_cu_start[0]) begin
            blk8_neib_b_avail <= ctrl_cur_cu_b_avail[0][1];
            blk8_neib_a_avail <= ctrl_cur_cu_a_avail[0][1];
	    end
    end
end

endmodule
