`include "ve_defines.v"
module vc_mvp_get_neib
#(
    parameter VC_CTU_X_NB = 7,
    parameter VC_CTU_Y_NB = 7,
    parameter VC_CU_X_NB  = 9,
    parameter VC_CU_Y_NB  = 9,
    parameter NUM_REF = 2,
    parameter MAX_BLK_SZ = 2,
    parameter VC_EN_BI_DIR = 0
)
(
// Output

output                        neib_done_amvp,
output                        neib_done_mrg,
// neib b
output     [ 4:0]             irpu2neib_b_req,
output     [ 4:0]             irpu2neib_b_addr,
output reg [2:0] [33:0]       amvp_neib_b,
output reg [2:0] [33:0]       mrg_neib_b,
output reg [3:0] [31:0]       blk32_neib_b_r,
output reg [1:0] [31:0]       blk16_neib_b_r,
output reg          [31:0]    blk8_neib_b_r,
// neib a
output     [ 1:0]             irpu2neib_a_req,
output     [ 1:0]             irpu2neib_a_addr,
output reg [1:0] [33:0]       amvp_neib_a,
output reg [1:0] [33:0]       mrg_neib_a,
output reg [3:0] [31:0]       blk32_neib_a_r,
output reg [1:0] [31:0]       blk16_neib_a_r,
output reg          [31:0]    blk8_neib_a_r,
// neib col
output                        irpu2col_req,
output     [ 4:0]             irpu2col_addr,
output     [1:0] [41:0]       amvp_col_c,
output     [1:0] [41:0]       mrg_col_c,
output     [1:0]              amvp_col_c_avail,
output     [1:0]              mrg_col_c_avail,
// reflist
output                       irpu2ref_req,
output     [3+VC_EN_BI_DIR:0] irpu2ref_addr,
output reg [NUM_REF-1:0][32:0] reflist_info,

//****************************
//          Input
//****************************
// enc_top
input                        clk_vc,
input                        vc_rst_z,
input      [1:0][2:0]        cmdq_empty_n,
input      [2:0]             amvp_blk_sz,
input      [2:0]             mrg_blk_sz,
// register
input                        reg_avc_mode,
input                        reg_slice_go,
input                        reg_i_slice,
input      [VC_CTU_X_NB-1:0] reg_pic_width_ctu_m1,
input      [VC_CU_X_NB-1:0]  reg_pic_width_cu_m1,
input      [VC_CU_Y_NB-1:0]  reg_pic_height_cu_m1,
input                        reg_tmp_mvp_flag,
input      [3:0]             reg_num_ref_l0_act_m1,
// CTU Layer
input                        cur_ctu_start,
input      [VC_CTU_X_NB-1:0] ctux,
input      [VC_CTU_Y_NB-1:0] ctuy,
// CU Layer
input      [11:0]            pic_x,
input      [11:0]            pic_y,
input                        amvp_cu_start,
input                        mrg_cu_start,
input      [2:0][13:0]       amvp_cmd_out,
input      [2:0][13:0]       mrg_cmd_out,
// mode decision
input                        cur_cu_upd,
input      [1:0]             cur_cu_upd_sz,
input      [2:0]             cur_cu_upd_x,
input      [2:0]             cur_cu_upd_y,
input      [15:0]            cur_cu_upd_mvx,
input      [15:0]            cur_cu_upd_mvy,
input      [1:0]             cur_cu_upd_refidx,
// neib b
input                        neib_b2irpu_gnt,
input                        neib_b2irpu_rd_lat,
input      [34*2-1:0]        neib_b2irpu_rd,
// neib a
input                        neib_a2irpu_gnt,
input                        neib_a2irpu_rd_lat,
input      [34*2-1:0]        neib_a2irpu_rd,
// neib col
input                        col2irpu_gnt,
input                        col2irpu_rd_lat,
input      [42*2-1:0]        col2irpu_rd,
// reflist
input                        ref2irpu_gnt,
input                        ref2irpu_rd_lat,
input      [32:0]            ref2irpu_rd,
// lat
input                        blk_sz_lat_mrg,
input                        blk_sz_lat_amvp,
input      [2:0]             n_blk_sz_mrg,
input      [2:0]             n_blk_sz_amvp
);

// local parameter

localparam		NEIB_IDLE = 0,
				NEIB_WAIT_DONE = 1;

localparam		ARB_IDLE = 0,
				ARB_AMVP = 1,
				ARB_MRG  = 2;

localparam		COL_IDLE = 0,
				COL_COL_0= 1,
				COL_COL_1= 2,
				COL_FULL = 3,
				COL_START = 4;

// register declaration

reg		[ 1:0]				fsm_neib_cs;
reg		[ 3:0][33:0]		b_0_reg;
reg		[ 3:0][33:0]		a_0_reg; 
reg		[ 5:0][33:0]		buf_reg;

reg		[7:0][33:0]			mvp_neib_b_reg;
reg		[5:0][33:0]			mvp_neib_a_reg;
reg		[5:0][41:0]			mvp_col_c_reg;
reg							blk_8_start_b_con;
reg							blk_8_start_a_con;

// wire declaration

reg     [ 1:0]                fsm_neib_ns;
wire    [ 2:0] [33:0]         n_amvp_neib_b_sel;
wire    [ 2:0] [33:0]         n_mrg_neib_b_sel;
wire    [ 1:0] [33:0]         n_amvp_neib_a_sel;
wire    [ 1:0] [33:0]         n_mrg_neib_a_sel;
wire    [ 2:0]                cmdq_b_cmdq_avail;
wire    [ 2:0]                cmdq_a_blk_sz;
wire    [ 1:0]                cmdq_a_cmdq_avail;
wire    [NUM_REF-1:0]         ref_avail;

wire                          get_neib_a_idle;
wire                          get_neib_b_idle;
wire                          get_neib_c_idle;
wire                          get_ref_idle;
wire                          cmdq_cu_start;
wire                          neib_a_cu_start;
wire                          neib_b_cu_start;
wire                          neib_c_cu_start;

// col neib fifo
wire    [ 1:0]                full_n;
wire    [ 1:0]                n_full_n;
wire    [ 1:0]                empty_n;
wire    [ 1:0]                n_empty_n;
wire    [ 1:0]                push;
wire    [41:0]                q [0:1];
wire    [41:0]                d [0:1];

wire    [ 2:0]                neib_a_info;
wire    [ 3:0]                neib_b_info;
wire    [ 2:0]                col_c_info;
wire                          cmdq_b_sel;
wire                          cmdq_a_sel;
wire                          cmdq_c_sel;
wire    [ 2:0]                blk_sz;
wire    [ 2:0]                cux;
wire    [ 2:0]                cuy;
wire    [ 2:0]                neib_b_avail;
wire    [ 1:0]                neib_a_avail;
wire                          terminate;
wire                          zmv;
wire                          skip;
wire    [NUM_REF-1:0]         ref_info;

wire    [13:0]                cu_cmd_out;
wire    [ 5:0]                irpu2neib_b_addr_full;
wire    [ 2:0]                irpu2neib_a_addr_full;
wire    [ 5:0]                irpu2col_addr_full;
wire    [ 3:0]                b_avail_cnt;
wire    [ 3:0]                a_avail_cnt;
wire    [ 3:0]                c_avail_cnt;
wire    [ 3:0]                ref_avail_cnt;
wire    [33:0]                cur_cu_upd_cand;

wire    [2:0] [33:0]          n_amvp_neib_b;
wire    [2:0] [33:0]          n_mrg_neib_b;
wire    [1:0] [33:0]          n_amvp_neib_a;
wire    [1:0] [33:0]          n_mrg_neib_a;

wire                          col0_32_valid_con;
wire                          col0_16_valid_con;
wire                          col0_8_valid_con;
wire                          neib_done_con;

// new architecture
//wire  [5:0][1:0]             neib_b_wr_info;
//wire  [4:0][1:0]             neib_a_wr_info;
//wire  [2:0][1:0]             col_c_wr_info;
wire                          ctu0_start;
wire                          neib_b_avail_32_or;
wire                          neib_b_avail_16_or;
wire                          neib_b_avail_8_or;
wire                          neib_b_avail_or;
wire                          neib_a_avail_32_or;
wire                          neib_a_avail_16_or;
wire                          neib_a_avail_8_or;
wire                          n_blk_8_start_b_con;
wire                          n_blk_8_start_a_con;
wire    [2:0]                 g_cmdq_empty_n;

wire    [3:0][31:0]           blk32_neib_b;
wire    [3:0][31:0]           blk32_neib_a;

reg     [7:0][33:0]           n_mvp_neib_b_reg;
reg     [5:0][33:0]           n_mvp_neib_a_reg;
reg     [5:0][33:0]           n_buf_reg;

// combbinational logic

assign ctu0_start = cur_ctu_start & !reg_i_slice & ctux==0 & ctuy==0;

assign cur_cu_upd_cand = {cur_cu_upd_refidx, cur_cu_upd_mvy, cur_cu_upd_mvx};
assign irpu2neib_b_addr = irpu2neib_b_addr_full[5:1];
assign irpu2neib_a_addr = irpu2neib_a_addr_full[2:1];
assign irpu2col_addr    = irpu2col_addr_full[5:1];
//assign   cmdq_cu_start    = reg_avc_mode ? amvp_cu_start : mrg_cu_start;//fsm_arb_cs[ARB_IDLE] & ( amvp_cu_start | mrg_cu_start );
//assign   cu_cmd_out       = reg_avc_mode ? amvp_cmd_out[0] : mrg_cmd_out[0];
assign cmdq_cu_start    = amvp_cu_start;//fsm_arb_cs[ARB_IDLE] & ( amvp_cu_start | mrg_cu_start );
assign cu_cmd_out       = amvp_cmd_out[0];
assign g_cmdq_empty_n   = cmdq_empty_n[reg_avc_mode];

assign neib_b_avail_32_or  = |{mrg_cmd_out[0][8:6],mrg_cmd_out[1][6],mrg_cmd_out[2][7:6]};
assign neib_b_avail_16_or  = |{reg_avc_mode ? amvp_cmd_out[1][8:6] : mrg_cmd_out[0][8:6],
                                 reg_avc_mode ? amvp_cmd_out[1][6]   : mrg_cmd_out[1][6]};
assign neib_b_avail_8_or   = |{reg_avc_mode ? amvp_cmd_out[0][8:6] : mrg_cmd_out[0][8:6]};
assign neib_b_avail_or     = g_cmdq_empty_n[2] ? neib_b_avail_32_or :
                             g_cmdq_empty_n[1] ? neib_b_avail_16_or :
                                                  neib_b_avail_8_or;

assign neib_a_avail_32_or  = |{mrg_cmd_out[0][10:9],mrg_cmd_out[1][9],mrg_cmd_out[2][10:9]};
assign neib_a_avail_16_or  = |{reg_avc_mode ? amvp_cmd_out[0][10:9] : mrg_cmd_out[0][10:9],
                                 reg_avc_mode ? amvp_cmd_out[1][9]   : mrg_cmd_out[1][9]};
assign neib_a_avail_8_or   = |{reg_avc_mode ? amvp_cmd_out[0][10:9] : mrg_cmd_out[0][10:9]};

assign blk32_neib_b = get_blk32_neib_b(mvp_neib_b_reg[5:2], b_0_reg, cuy[0], cux[1:0]);
assign blk32_neib_a = get_blk32_neib_a(mvp_neib_a_reg[3:0], a_0_reg, cux[0], cuy[1:0]);

/*
always@(*) begin
    integer i;
    for(i=0 ; i<4 ; i++) begin
        mvbs_neib_b[2][i] = blk32_neib_b_r[i];
        mvbs_neib_a[2][i] = blk32_neib_a_r[i];
    end
end

always@(*) begin
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

always@(*) begin
    integer i;
    for(i=0 ; i<4 ; i++) begin
        if(i<1) begin
            mvbs_neib_b[0][i] = blk8_neib_b_r[i];
            mvbs_neib_a[0][i] = blk8_neib_a_r[i];
        end
        else begin
            mvbs_neib_b[0][i] = 0;
            mvbs_neib_a[0][i] = 0;
        end
    end
end
*/

// blk32
//    b2 b3 b4 b5  -> from mvp_neib_b_reg
//    -  -  -  -
// a0 |  |  |  |  |
//    -  -  -  -
// a1 |  |  |  |  |
//    -  -  -  -
// a2 |  |  |  |  |
//    -  -  -  -
// a3 |  |  |  |  |
//     -- -- -- --

// neib B
//        ctux-1    |          ctux            | ctux+1
//                  | set0 | set1 | set2 | set3 |
//                  | b0 | b1| b2| b3| b4| b5| b6| b7|   |   |
//    set0 | set1 | set2 | set3 |
//    b0 | b1| b2| b3| b4| b5| b6| b7|   |   |
//    -------------------------------
//    |   |   |   |   |   |   |   |   |   |
//    cux   | 0  | 1  | 2  | 3  | 4  | 5  | 6  | 7  |
//    |   |   |   |   |   |   |   |   |   |

//            idx    0  1    2  3    4  5    6  7
//  blk8,16,32   x=0,4=> b1,  b2b3,  b4b5,  b6
//  blk8         x=1,5=>      b2b3,  b4
//  blk8,16      x=2,6=>      b3,  b4b5,  b6
//  blk8         x=3,7=>          b4b5,  b6
//                      set0  set1  set2  set3

//        mem_cnt_ptr=   0      1      2      3
//        ======================================
//        x=0,4=>    0,     1,     2,     3   (x00)
//        x=1,5=>    1,     2,     x,     x   (x01)
//        x=2,6=>    1,     2,     3,     x   (x10)
//        x=3,7=>    2,     3,     x     x   (x11)

// neib A
//        ctux-1    |          ctux            | ctux+1
//          7     | 0  1  2  3 | 4  5  6  7 | 0
//    -------------------------------
//          a0|    8_0    |           |
//    -------------------------------
//          a1|    8_1    |           |
//    -------------------------------
//          a2|    8_2    |           |
//    -------------------------------
//          a3|    8_3    |           |
//    ctuy    -------------------------------
//          a4|    8_4    |           |
//    -------------------------------
//          |    8_5    |           |
//    -------------------------------
//          |    8_6    |           |
//    -------------------------------
//          |    8_7    |           |
//    -------------------------------
//    ctuy+1    0  |           |           |

//    blk8,16,32   y=0,4=> a0a1,  a2a3,  a4
//    blk8         y=1,5=>      a1,  a2
//    blk8,16      y=2,6=>      a2a3,  a4
//    blk8         y=3,7=>          a3,  a4
//                      set0   set1   set2

// col c
//        ctux-1    |          ctux            | ctux+1
//          7     | 0  1 | 2  3 | 4  5 | 6  7 | 0
//    -------------------------------
//    0 | 0       | 1     | 4     | 5     | 0
//    1 |         |       |       |       |
//    -------------------------------
//    2 | 2       | 3     | 6     | 7     | 2
//    3 |         |       |       |       |
//    ctuy    -------------------------------
//    4 | 8       | 9     | 12    | 13    | 8
//    5 |         |       |       |       |
//    -------------------------------
//    6 | 10      | 11    | 14    | 15    | 10
//    7 |         |       |       |       |
//    -------------------------------
//    ctuy+1    0  |       |       |       | 0

//    blk8,16,32     blk32 => Ex. c0c3c12(3), c1c6c13(3) ...
//    blk8,16        blk16 => Ex. c0c3(2),    c1c6(2) ...
//    blk8           blk8  => Ex. c0c2(2) or c0c3(2) or c0c1(1)

assign	cux				 = cu_cmd_out[0+:3];
assign	cuy				 = cu_cmd_out[3+:3];

assign ref_avail = 16'hffff >> (16 - ref_avail_cnt);

assign b_avail_cnt = g_cmdq_empty_n[2] ? (neib_b_avail_32_or ? 4 : 0) :
                     g_cmdq_empty_n[1] ? (neib_b_avail_16_or ? 3 : 0) :
                     cuy[0]            ? 0 :
                                         (neib_b_avail_8_or  ? 2 : 0);
                                         //(cuy[0] ? 0:2 ); // y dir odd blk8 => necessary read

assign a_avail_cnt = g_cmdq_empty_n[2] ? (neib_a_avail_32_or ? 3 : 0) :
                     g_cmdq_empty_n[1] ? (neib_a_avail_16_or ? 2 : 0) :
                     cux[0]            ? 0 :
                                         (neib_a_avail_8_or  ? 2: 0);
                                         //(cux[0] ? 0:2 ); // x dir odd blk8 => necessary read

assign c_avail_cnt = g_cmdq_empty_n[2] ? 3 :
                     (cux[1:0]==2'b01 &!cuy[0]) ? 1 : 2; // blk8 when cux[1:0]=2'b01, cuy even => ex. blk16_0 & blk16_1 are in the same addr
assign ref_avail_cnt = reg_num_ref_l0_act_m1 + 1;

assign neib_b_cu_start = cmdq_cu_start & |b_avail_cnt;
assign neib_a_cu_start = cmdq_cu_start & |a_avail_cnt;
assign neib_c_cu_start = cmdq_cu_start & reg_tmp_mvp_flag;

//assign   neib_done_con = get_neib_a_idle & get_neib_b_idle & get_neib_c_idle & get_ref_idle;// & !fsm_arb_cs[ARB_IDLE] ; // a, b, reflist, c
assign neib_done_con = (get_neib_a_idle | blk_8_start_a_con) &
                       (get_neib_b_idle | blk_8_start_b_con) &
                        get_neib_c_idle & get_ref_idle;// & !fsm_arb_cs[ARB_IDLE] ; // a, b, reflist, c

assign n_blk_8_start_b_con = neib_b2irpu_rd_lat & ( neib_b_info[1] &  cux[1:0]==0 |
                                                    neib_b_info[2] & (cux[1:0]==1 | cux[1:0]==2) |
                                                    neib_b_info[3] &  cux[1:0]==3);
assign n_blk_8_start_a_con = (neib_a2irpu_rd_lat & (neib_a_info[0] & !cuy[0] | neib_a_info[1] & cuy[0]));

assign neib_done_amvp = neib_done_con;
assign neib_done_mrg  = neib_done_con;

// col
assign col0_32_valid_con = ( pic_x[11:3]+4 <= reg_pic_width_cu_m1 ) & ( pic_y[11:3]+4 <= reg_pic_height_cu_m1 );
assign col0_16_valid_con = ( pic_x[11:3]+2 <= reg_pic_width_cu_m1 ) & ( pic_y[11:3]+2 <= reg_pic_height_cu_m1 );
assign col0_8_valid_con  = ( pic_x[11:3]+1 <= reg_pic_width_cu_m1 ) & ( pic_y[11:3]+1 <= reg_pic_height_cu_m1 );

assign amvp_col_c_avail[1] =  reg_tmp_mvp_flag;
assign amvp_col_c_avail[0] =  amvp_blk_sz[2] ? ( cuy!= 3'd4 & ( col0_32_valid_con & reg_tmp_mvp_flag) ) : // cuy==4 => 0
                              amvp_blk_sz[1] ? ( cuy!= 3'd6 & ( col0_16_valid_con & reg_tmp_mvp_flag) ) : // cuy==6 => 0
                                              ( cuy!= 3'd7 & ( col0_8_valid_con  & reg_tmp_mvp_flag) ); // cuy==7 => 0

assign mrg_col_c_avail[1] =  reg_tmp_mvp_flag;
assign mrg_col_c_avail[0] =  mrg_blk_sz[2] ? ( cuy!= 3'd4 & ( col0_32_valid_con & reg_tmp_mvp_flag) ) : // cuy==4 => 0
                              mrg_blk_sz[1] ? ( cuy!= 3'd6 & ( col0_16_valid_con & reg_tmp_mvp_flag) ) : // cuy==6 => 0
                                              ( cuy!= 3'd7 & ( col0_8_valid_con  & reg_tmp_mvp_flag) ); // cuy==7 => 0

always@(*) begin : get_neib_a_b_blk
    integer i;
    for(i=0 ; i<4 ; i++) begin
        if(neib_b_info[i] & neib_b2irpu_rd_lat) begin
        //if(neib_b_info[i]) begin
            n_mvp_neib_b_reg[i*2  ] = neib_b2irpu_rd[ 0+:34];
            n_mvp_neib_b_reg[i*2+1] = neib_b2irpu_rd[34+:34];
        end
        else begin
            n_mvp_neib_b_reg[i*2  ] = mvp_neib_b_reg[i*2  ];
            n_mvp_neib_b_reg[i*2+1] = mvp_neib_b_reg[i*2+1];
        end
    end

    for(i=0 ; i<3 ; i++) begin
        if(neib_a_info[i] & neib_a2irpu_rd_lat) begin
        //if(neib_a_info[i]) begin
            n_mvp_neib_a_reg[i*2  ] = neib_a2irpu_rd[ 0+:34];
            n_mvp_neib_a_reg[i*2+1] = neib_a2irpu_rd[34+:34];
        end
        else begin
            n_mvp_neib_a_reg[i*2  ] = mvp_neib_a_reg[i*2  ];
            n_mvp_neib_a_reg[i*2+1] = mvp_neib_a_reg[i*2+1];
        end
    end
end

always@(*) begin
    n_buf_reg = buf_reg;

    if(neib_b2irpu_rd_lat & neib_b_info[1]) begin
        if( cux[1:0]==2'd1 & cuy[1:0]==2'd0 |
            cux[1:0]==2'd1 & cuy[1:0]==2'd2) begin
            n_buf_reg[0] = neib_b2irpu_rd[34+:34]; // store rd_b1 to buf0
        end
    end

    if(neib_a2irpu_rd_lat) begin
        if( cux[1:0]==2'd0 & cuy[1:0]==2'd2 & neib_a_info[0] ) begin
            n_buf_reg[2] = neib_a2irpu_rd[0+:34]; // store rd_a1 to buf2
        end
        else if( cux[1:0]==2'd0 & cuy[1:0]==2'd2 & neib_a_info[1]) begin
            n_buf_reg[2] = neib_a2irpu_rd[0+:34]; // store rd_a1 to buf2
        end
    end

    if(neib_b2irpu_rd_lat & neib_b_info[0]) begin
        if( cux[2:0]==3'd3 & cuy[1:0]==2'd0 ) begin
            n_buf_reg[3] = neib_b2irpu_rd[34+:34]; // store rd_b1 to buf3
        end
    end

    if(neib_b2irpu_rd_lat & neib_b_info[0]) begin
        if( cux[2:0]==3'd7 & cuy[2:0]==3'd0 ) begin
            n_buf_reg[4] = neib_b2irpu_rd[34+:34]; // store rd_b1 to buf4
        end
    end

    if(neib_b2irpu_rd_lat & neib_b_info[0]) begin
		if(	cux[2:0]==3'd7 & cuy[2:0]==3'd4 ) begin
			n_buf_reg[5] = neib_b2irpu_rd[34+:34];
		end
	end
end

// neib b
assign n_amvp_neib_b_sel= get_rd_neib_b(n_mvp_neib_b_reg, n_blk_sz_amvp, cux, reg_avc_mode);
assign n_mrg_neib_b_sel = get_rd_neib_b(n_mvp_neib_b_reg, n_blk_sz_mrg , cux, 1'b0);
// neib a
assign n_amvp_neib_a_sel= get_rd_neib_a(n_mvp_neib_a_reg, n_blk_sz_amvp, cuy, reg_avc_mode);
assign n_mrg_neib_a_sel = get_rd_neib_a(n_mvp_neib_a_reg, n_blk_sz_mrg , cuy, 1'b0);
// col c
assign amvp_col_c     = get_rd_col_c(mvp_col_c_reg, amvp_blk_sz, cux, cuy);
assign mrg_col_c      = get_rd_col_c(mvp_col_c_reg, mrg_blk_sz, cux, cuy);

assign n_amvp_neib_b = get_neib_b(n_amvp_neib_b_sel, b_0_reg, n_buf_reg, n_blk_sz_amvp, cux, cuy, reg_avc_mode);
assign n_mrg_neib_b  = get_neib_b(n_mrg_neib_b_sel , b_0_reg, n_buf_reg, n_blk_sz_mrg , cux, cuy, 1'b0);
assign n_amvp_neib_a = get_neib_a(n_amvp_neib_a_sel, a_0_reg, n_blk_sz_amvp[0], cux[0], cuy[1:0]);
assign n_mrg_neib_a  = get_neib_a(n_mrg_neib_a_sel , a_0_reg, n_blk_sz_mrg[0] , cux[0], cuy[1:0]);
//assign amvp_neib_b = neib_done_amvp ? amvp_neib_b_w : amvp_neib_b_r;
//assign amvp_neib_a = neib_done_amvp ? amvp_neib_a_w : amvp_neib_a_r;
//assign mrg_neib_b  = neib_done_mrg  ? mrg_neib_b_w  : mrg_neib_b_r;
//assign mrg_neib_a  = neib_done_mrg  ? mrg_neib_a_w  : mrg_neib_a_r;

always@(posedge clk_vc) begin : amvp_mrg_neib_b_seq_blk
    integer i;
    for(i=0 ; i<3 ; i++) begin
        if(neib_b2irpu_rd_lat)
            amvp_neib_b[i] <= n_amvp_neib_b[i];
        else if(blk_sz_lat_amvp)
            amvp_neib_b[i] <= n_amvp_neib_b[i];

        if(neib_b2irpu_rd_lat)
            mrg_neib_b[i]  <= n_mrg_neib_b[i];
        else if(blk_sz_lat_mrg)
            mrg_neib_b[i]  <= n_mrg_neib_b[i];
    end
end

always@(posedge clk_vc) begin : amvp_mrg_neib_a_seq_blk
	integer i;
	for(i=0 ; i<2 ; i++) begin
        if(neib_a2irpu_rd_lat)
			amvp_neib_a[i]  <= n_amvp_neib_a[i];
		else if(blk_sz_lat_amvp)
			amvp_neib_a[i]	<= n_amvp_neib_a[i];

        if(neib_a2irpu_rd_lat)
			mrg_neib_a[i]	<= n_mrg_neib_a[i];
		else if(blk_sz_lat_mrg)
			mrg_neib_a[i]	<= n_mrg_neib_a[i];
	end
end

// function/task

function [2:0][33:0] get_rd_neib_b;
    input [7:0][33:0] rd_neib; // 0, 7 redundant
    input [2:0]       blk_en;
    input [2:0]       cux;
    input             avc_mode;
begin
    if(blk_en[2]) begin // blk32
        get_rd_neib_b[0] = rd_neib[6];
        get_rd_neib_b[1] = rd_neib[5];
        get_rd_neib_b[2] = rd_neib[1];
    end
    else if (blk_en[1]) begin // blk16
        get_rd_neib_b[0] = cux[1] ? rd_neib[6] : rd_neib[4];
        get_rd_neib_b[1] = cux[1] ? avc_mode ? rd_neib[4] : rd_neib[5] :
                                    avc_mode ? rd_neib[2] : rd_neib[3];
        get_rd_neib_b[2] = cux[1] ? rd_neib[3] : rd_neib[1];
    end
    else begin // blk8
        get_rd_neib_b[0] = rd_neib[cux[1:0]+3];
        get_rd_neib_b[1] = rd_neib[cux[1:0]+2];
        get_rd_neib_b[2] = rd_neib[cux[1:0]+1];
    end
end
endfunction

function [1:0][33:0] get_rd_neib_a;
    input [5:0][33:0] rd_neib; // 5 redundant
    input [2:0]       blk_en;
    input [2:0]       cuy;
    input             avc_mode;
begin
    if(blk_en[2]) begin
        get_rd_neib_a[0] = rd_neib[4];
        get_rd_neib_a[1] = rd_neib[3];
    end
    else if(blk_en[1]) begin
        get_rd_neib_a[0] = cuy[1] ? rd_neib[4] : rd_neib[2];
        get_rd_neib_a[1] = cuy[1] ? avc_mode ? rd_neib[2] : rd_neib[3] :
                                    avc_mode ? rd_neib[0] : rd_neib[1];
    end
    else begin
        get_rd_neib_a[0] = rd_neib[cuy[1:0]+1];
        get_rd_neib_a[1] = rd_neib[cuy[1:0]  ];
    end
end
endfunction

function [1:0][41:0] get_rd_col_c;
    input [5:0][41:0] rd_neib;
    input [2:0]       blk_en;
    input [2:0]       cux;
    input [2:0]       cuy;
begin

    /*
    each number is blk16 for col

    =================
    blk32
    ----------------
    c0 = 4,  c1=3
    ----------------
       0   1
       2   3
			  4   5

	   ================
       blk16
	   ----------------
	
	   c0 = 4, c1=3
	   0   1
       2   3

       or

	   c0 = 2, c1=1
	   0   1	 
              2   3

       ================
	   blk8
	   ----------------

    */

    if(blk_en[2]) begin
        //get_rd_col_c[0] = cux[1] ? rd_neib[5] : rd_neib[4];
        //get_rd_col_c[1] = cux[1] ? rd_neib[2] : rd_neib[3];
        get_rd_col_c[0] = rd_neib[4];
        get_rd_col_c[1] = rd_neib[3];
    end
    else if(blk_en[1]) begin
        get_rd_col_c[0] = cux[1] ? rd_neib[2] : rd_neib[3];
         get_rd_col_c[1] = cux[1] ? rd_neib[1] : rd_neib[0];
    end
    else begin
        if(cux[0]==0 & cuy[0]==0) begin
            get_rd_col_c[0] = rd_neib[cux[1]];
            get_rd_col_c[1] = rd_neib[cux[1]];
        end
        else if(cux[0]==1 & cuy[0]==0) begin
            get_rd_col_c[0] = cux[1] ? rd_neib[2] : rd_neib[1];
            get_rd_col_c[1] = cux[1] ? rd_neib[1] : rd_neib[0];
        end
        else if(cux[0]==0 & cuy[0]==1) begin
            get_rd_col_c[0] = cux[1] ? rd_neib[3] : rd_neib[2];
            get_rd_col_c[1] = cux[1] ? rd_neib[1] : rd_neib[0];
        end
        else begin
            get_rd_col_c[0] = cux[1] ? rd_neib[2] : rd_neib[3];
            get_rd_col_c[1] = cux[1] ? rd_neib[1] : rd_neib[0];
        end
    end
end
endfunction

function [3:0][31:0] get_blk32_neib_a;
    input [3:0][33:0] neib_a_r;
    input [3:0][33:0] a0_reg;
    input             cux;
    input  [1:0]      cuy;
    reg   [3:0][33:0] neib_a_sel;
begin
    neib_a_sel = cux ? a0_reg : neib_a_r;
    case(cuy)
        2'd0: get_blk32_neib_a = {    neib_a_sel[3][31:0],neib_a_sel[2][31:0],neib_a_sel[1][31:0],neib_a_sel[0][31:0]};
        2'd1: get_blk32_neib_a = {32'd0,neib_a_sel[3][31:0],neib_a_sel[2][31:0],neib_a_sel[1][31:0]};
        2'd2: get_blk32_neib_a = {64'd0,neib_a_sel[3][31:0],neib_a_sel[2][31:0]};
        2'd3: get_blk32_neib_a = {96'd0,neib_a_sel[3][31:0]};
    endcase
end
endfunction

function [3:0][31:0] get_blk32_neib_b;
    input [3:0][33:0] neib_b_r;
    input [3:0][33:0] b0_reg;
    input             cuy;
    input  [1:0]      cux;
    reg   [3:0][33:0] neib_b_sel;
begin
    neib_b_sel = cuy ? b0_reg : neib_b_r;
    case(cux)
        2'd0: get_blk32_neib_b = {    neib_b_sel[3][31:0],neib_b_sel[2][31:0],neib_b_sel[1][31:0],neib_b_sel[0][31:0]};
        2'd1: get_blk32_neib_b = {32'd0,neib_b_sel[3][31:0],neib_b_sel[2][31:0],neib_b_sel[1][31:0]};
        2'd2: get_blk32_neib_b = {64'd0,neib_b_sel[3][31:0],neib_b_sel[2][31:0]};
        2'd3: get_blk32_neib_b = {96'd0,neib_b_sel[3][31:0]};
    endcase
end
endfunction

function [1:0][33:0] get_neib_a;
    input [1:0][33:0] neib_a_r;
    input [3:0][33:0] a0_reg;
    input             blk_8;
    input             cux;
    input  [1:0]      cuy;
begin
    get_neib_a[0] = neib_a_r[0];

    if(!blk_8) begin
        get_neib_a[1] = neib_a_r[1];
    end
    else begin
        if(cux)
            get_neib_a[1] = a0_reg[ cuy[1:0] ];
        else
            get_neib_a[1] = neib_a_r[1];
    end
end
endfunction

function [2:0][33:0] get_neib_b;
    input [2:0][33:0] neib_b_r;
    input [3:0][33:0] b0_reg;
    input [5:0][33:0] buf_reg;
    input [2:0]       blk_sz;
    input [2:0]       cux;
    input [2:0]       cuy;
    input             avc_mode;
    integer i;
begin
    if(blk_sz[1]) begin // blk16
        get_neib_b[0] = neib_b_r[0];
        get_neib_b[1] = neib_b_r[1];

        if({avc_mode, cux[2:0], cuy[1:0]} == {1'b0, 3'd4, 2'd0}) begin
            get_neib_b[2] = buf_reg[3]; // 4, 12
        end
        else if({avc_mode, cux[2:0], cuy[2:0]} == {1'b0, 3'd0, 3'd4} ) begin
            get_neib_b[2] = buf_reg[5];
        end
        else if({avc_mode, cux[2:0], cuy[2:0]} == {1'b0, 3'd0, 3'd0} ) begin
            get_neib_b[2] = buf_reg[4];
        end
        else begin
            case({avc_mode ? 4'd0 : {cux[1:0],cuy[1:0]}})
                {2'd2, 2'd0}: get_neib_b[2] = buf_reg[0]; // 1, 5, 9,  13
                {2'd2, 2'd2}: get_neib_b[2] = buf_reg[0]; // 3, 7, 11, 15
                {2'd0, 2'd2}: get_neib_b[2] = buf_reg[1]; // 2, 6, 10, 14
                default     : get_neib_b[2] = neib_b_r[2];// 0, 8
            endcase
        end
    end
    else if(blk_sz[0]) begin // blk8
        if(!cuy[0]) begin
            get_neib_b[0] = neib_b_r[0];
        end
        else begin
            if(cux[1:0]==3)
                get_neib_b[0] = 0; // unknown
            else
                get_neib_b[0] = b0_reg[cux[1:0] + 1];
        end

        if(cuy[0])
            get_neib_b[1] = b0_reg[ cux[1:0] ]; // odd
        else
            get_neib_b[1] = neib_b_r[1]; //even

        if(avc_mode & ~cuy[0])
            get_neib_b[2] = neib_b_r[2];
        else if({cux[2:0], cuy[1:0]} == {3'd4, 2'd0}) begin
            get_neib_b[2] = buf_reg[3]; // 16, 48
        end
        else if({cux[1], cuy[0]} == {1'd1, 1'd1}) begin
            get_neib_b[2] = cux[0] ? b0_reg[2] :   // 7, 15, 23, 31, 39, 47, 55, 63
                                    b0_reg[1];     // 6, 14, 22, 30, 38, 46, 54, 62
        end
        else if({cux[2:0], cuy[2:0]} == {3'd0, 3'd4} ) begin
            get_neib_b[2] = buf_reg[5]; // init b2 is unavail
        end
        else if({cux[2:0], cuy[2:0]} == {3'd0, 3'd0} ) begin
            get_neib_b[2] = buf_reg[4]; // init b2 is unavail
        end
        else begin
            case({cux[1:0],cuy[1:0]})
                {2'd2, 2'd0}: get_neib_b[2] = buf_reg[0]; // 4 , 20, 36, 52
                {2'd2, 2'd2}: get_neib_b[2] = buf_reg[0]; // 12, 28, 44, 60
                {2'd0, 2'd0}: get_neib_b[2] = buf_reg[1]; // 8 , 24, 40, 56
                {2'd0, 2'd1}: get_neib_b[2] = buf_reg[2]; // 2 , 18, 34, 50
                {2'd0, 2'd3}: get_neib_b[2] = buf_reg[2]; // 10, 26, 42, 58
                //-------------------------------
                {2'd1, 2'd1}: get_neib_b[2] = b0_reg[0]; // 3, 19, 35, 51
                {2'd1, 2'd3}: get_neib_b[2] = b0_reg[0]; // 11, 27, 43, 59

                default     : get_neib_b[2] = neib_b_r[2];// others
            endcase
        end
    end
    else begin // blk32
        get_neib_b[0] = neib_b_r[0];
        get_neib_b[1] = neib_b_r[1];

        if({cux[2:0], cuy[2:0]} == {3'd0, 3'd4 } ) begin
            get_neib_b[2] = buf_reg[5];
        end
        else if({cux[2:0], cuy[2:0]} == {3'd0, 3'd0 } ) begin
            get_neib_b[2] = buf_reg[4];
        end
        else if({cux[2:0], cuy[1:0]} == {3'd4, 2'd0 } ) begin
            get_neib_b[2] = buf_reg[3];
        end
        else begin
            get_neib_b[2] = neib_b_r[2];
        end
    end
end
endfunction

// instantiation

vc_mvp_rd_mem
#(
    .NEIB_DIR_TYPE (1), // a dir
    .AVAIL_W       (3), // a0a1, a2a3, a4
    .MEM_ADDR_W    (3), // 0~7
    .VC_CTU_X_NB   (VC_CTU_X_NB),
    // template sht_mdl
    .DEPTH         (3), // same as AVAIL_W
    .ADDR_LG2_W    (2),
    .DATA_W        (3)  // [2]a4, [1]a3a2, [0]a1a0
)
U_GET_NEIB_A(
// output
    .ip2mem_req       ( irpu2neib_a_req),
    .ip2mem_addr      ( irpu2neib_a_addr_full),
    .cmdq2ip_info     ( neib_a_info),
    .rd_mem_idle      ( get_neib_a_idle),
// input
    .clk_vc           ( clk_vc),
    .vc_rst_z         ( vc_rst_z),
    .reg_avc_mode     ( reg_avc_mode),
    .reg_slice_go     ( reg_slice_go),
    .reg_pic_width_ctu_m1( reg_pic_width_ctu_m1),
    .ip_cu_start      ( neib_a_cu_start),
    .ctux             ( ctux[2:0]),
    .ctuy             ( ctuy[0]),
    .cux              ( cux),
    .cuy              ( cuy),
    .ip_avail         ( 3'b111),
    .mem_avail_cnt    ( a_avail_cnt),
    .mem2ip_gnt       ( neib_a2irpu_gnt),
    .mem2ip_rd_lat    ( neib_a2irpu_rd_lat)
);

vc_mvp_rd_mem
#(
    .NEIB_DIR_TYPE (0), // b dir
    .AVAIL_W       (4), // b0, b1b2, b3b4, b5
    .MEM_ADDR_W    (6), // 0~63  8ctb,8cu
    .VC_CTU_X_NB   (VC_CTU_X_NB),
    // template sht_mdl
    .DEPTH         (4), // same as AVAIL_W
    .ADDR_LG2_W    (3),
    .DATA_W        (4)  // [3]:b5 ,[2]:b4b3, [1]:b2b1, [0]:b0
)
U_GET_NEIB_B(
// output
    .ip2mem_req       ( irpu2neib_b_req),
    .ip2mem_addr      ( irpu2neib_b_addr_full),
    .cmdq2ip_info     ( neib_b_info),
    .rd_mem_idle      ( get_neib_b_idle),
// input
    .clk_vc           ( clk_vc),
    .vc_rst_z         ( vc_rst_z),
    .reg_avc_mode     ( reg_avc_mode),
    .reg_slice_go     ( reg_slice_go),
    .reg_pic_width_ctu_m1( reg_pic_width_ctu_m1),
    .ip_cu_start      ( neib_b_cu_start),
    .ctux             ( ctux[2:0]),
    .ctuy             ( ctuy[0]),
    .cux              ( cux),
    .cuy              ( cuy),
    .ip_avail         ( 4'b1111),
    .mem_avail_cnt    ( b_avail_cnt),
    .mem2ip_gnt       ( neib_b2irpu_gnt),
    .mem2ip_rd_lat    ( neib_b2irpu_rd_lat)
);

vc_mvp_rd_mem
#(
    .NEIB_DIR_TYPE (2), // col dir
    .AVAIL_W       (3), // c0 c1 c2
    .MEM_ADDR_W    (6), // 0~63    4 ctb, 16 16x16
    .VC_CTU_X_NB   (VC_CTU_X_NB),
    // template sht_mdl
    .DEPTH         (3), // same as AVAIL_W
    .ADDR_LG2_W    (2),
    .DATA_W        (3)  //
)
U_GET_NEIB_C(
// output
    .ip2mem_req       ( irpu2col_req),
    .ip2mem_addr      ( irpu2col_addr_full),
    .cmdq2ip_info     ( col_c_info),
    .rd_mem_idle      ( get_neib_c_idle ),
// input
    .clk_vc           ( clk_vc),
    .vc_rst_z         ( vc_rst_z),
    .reg_avc_mode     ( reg_avc_mode),
    .reg_slice_go     ( reg_slice_go),
    .reg_pic_width_ctu_m1( reg_pic_width_ctu_m1),
    .ip_cu_start      ( neib_c_cu_start),
    .ctux             ( ctux[2:0]),
    .ctuy             ( ctuy[0]),
    .cux              ( cux),
    .cuy              ( cuy),
    .ip_avail         ( 3'b111),
    .mem_avail_cnt    ( c_avail_cnt),
    .mem2ip_gnt       ( col2irpu_gnt),
    .mem2ip_rd_lat    ( col2irpu_rd_lat)
);

vc_mvp_rd_mem
#(
    .NEIB_DIR_TYPE (3), // ref_list
    .AVAIL_W       (NUM_REF), // ref1, ref0
    .MEM_ADDR_W    (4+VC_EN_BI_DIR), //
    .VC_CTU_X_NB   (VC_CTU_X_NB),
    // template sht_mdl
    .DEPTH         (NUM_REF), // same as AVAIL_W
    .ADDR_LG2_W    (1),
    .DATA_W        (NUM_REF) // ref_idx1, ref_idx0, ref_idx 0~15
)
U_GET_REFLIST(
// output
    .ip2mem_req       ( irpu2ref_req),
    .ip2mem_addr      ( irpu2ref_addr),
    .cmdq2ip_info     ( ref_info),
    .rd_mem_idle      ( get_ref_idle),
// input
    .clk_vc           ( clk_vc),
    .vc_rst_z         ( vc_rst_z),
    .reg_avc_mode     ( reg_avc_mode),
    .reg_slice_go     ( reg_slice_go),
    .reg_pic_width_ctu_m1( reg_pic_width_ctu_m1),
    .ip_cu_start      ( ctu0_start),
    .ctux             ( ctux[2:0]),
    .ctuy             ( ctuy[0]),
    .cux              ( cux),
    .cuy              ( cuy),
    .ip_avail         ( ref_avail), // ref1, ref0
    .mem_avail_cnt    ( ref_avail_cnt),
    .mem2ip_gnt       ( ref2irpu_gnt),
    .mem2ip_rd_lat    ( ref2irpu_rd_lat)
);

// state machine

always@(*) begin : fsm_neib_done
    fsm_neib_ns = 0;
    case(1) //synopsys parallel_case
        fsm_neib_cs[NEIB_IDLE]: begin
            if( cmdq_cu_start )
                fsm_neib_ns[NEIB_WAIT_DONE] = 1;
            else
                fsm_neib_ns[NEIB_IDLE] = 1;
        end
        fsm_neib_cs[NEIB_WAIT_DONE]: begin
            if( neib_done_con )
                fsm_neib_ns[NEIB_IDLE] = 1;
            else
                fsm_neib_ns[NEIB_WAIT_DONE] = 1;
        end
    endcase
end

// sequence logic

always@(posedge clk_vc or negedge vc_rst_z)begin
    if(~vc_rst_z) begin
        blk_8_start_a_con <= 0;
        blk_8_start_b_con <= 0;
    end
    else if(reg_slice_go | cmdq_cu_start)begin
        blk_8_start_a_con <= 0;
        blk_8_start_b_con <= 0;
    end
    else begin
        if(n_blk_8_start_a_con)
            blk_8_start_a_con <= 1;

        if(n_blk_8_start_b_con)
            blk_8_start_b_con <= 1;
    end
end

always@(posedge clk_vc )begin : upd_even_line_reg_blk
    integer i;
    if(cur_cu_upd) begin
        if(cur_cu_upd_sz == 2'd1) begin // blk8
            if(cur_cu_upd_y[0]==1'b0)
                b_0_reg[cur_cu_upd_x[1:0]   ] <= cur_cu_upd_cand;
            if(cur_cu_upd_x[0]==1'b0)
                a_0_reg[cur_cu_upd_y[1:0]   ] <= cur_cu_upd_cand;
        end
        else if(cur_cu_upd_sz == 2'd2) begin // blk16
            b_0_reg[cur_cu_upd_x[1:0]   ] <= cur_cu_upd_cand;
            b_0_reg[cur_cu_upd_x[1:0]+1] <= cur_cu_upd_cand;
            a_0_reg[cur_cu_upd_y[1:0]   ] <= cur_cu_upd_cand;
            a_0_reg[cur_cu_upd_y[1:0]+1] <= cur_cu_upd_cand;
        end
        else begin // blk32
            for(i=0; i<4 ; i++) begin
                b_0_reg[i] <= cur_cu_upd_cand;
                a_0_reg[i] <= cur_cu_upd_cand;
            end
        end
    end
end

always@(posedge clk_vc ) begin
    buf_reg <= n_buf_reg;
end

// new architecture
always@(posedge clk_vc )begin : get_neib_seq_blk
    integer i;

    for(i=0 ; i<4 ; i++) begin
        if(neib_b_info[i] & neib_b2irpu_rd_lat) begin
            mvp_neib_b_reg[i*2  ] <= neib_b2irpu_rd[ 0+:34];
            mvp_neib_b_reg[i*2+1] <= neib_b2irpu_rd[34+:34];
        end
    end

    for(i=0 ; i<3 ; i++) begin
        if(neib_a_info[i] & neib_a2irpu_rd_lat) begin
            mvp_neib_a_reg[i*2  ] <= neib_a2irpu_rd[ 0+:34];
            mvp_neib_a_reg[i*2+1] <= neib_a2irpu_rd[34+:34];
        end
    end

    for(i=0 ; i<3 ; i++) begin
        if(col_c_info[i] & col2irpu_rd_lat) begin
            mvp_col_c_reg[i*2  ] <= col2irpu_rd[ 0+:42];
            mvp_col_c_reg[i*2+1] <= col2irpu_rd[42+:42];
        end
    end

    for(i=0 ; i<NUM_REF ; i=i+1) begin
        if(ref_info[i] & ref2irpu_rd_lat)
            reflist_info[i] <= ref2irpu_rd[32:0]; // 32: long, [31:0]: POC
    end
end

always@(posedge clk_vc or negedge vc_rst_z)begin
    if(~vc_rst_z)begin
        fsm_neib_cs <= 1;
    end
    else if(reg_slice_go) begin
        fsm_neib_cs <= 1;
    end
    else if( fsm_neib_cs != fsm_neib_ns ) begin
        fsm_neib_cs <= fsm_neib_ns;
    end
end

always@(posedge clk_vc) begin : blk32_neib_r
    integer i;
    for(i=0 ; i<4 ; i++) begin
        if(mrg_blk_sz[2]) begin
            blk32_neib_b_r[i] <= blk32_neib_b[i];
            blk32_neib_a_r[i] <= blk32_neib_a[i];
        end
    end
end

always@(posedge clk_vc) begin : blk16_neib_r
    integer i;
    for(i=0 ; i<2 ; i++) begin
        if(reg_avc_mode ? amvp_blk_sz[1] : mrg_blk_sz[1]) begin
            blk16_neib_b_r[i] <= blk32_neib_b[i];
            blk16_neib_a_r[i] <= blk32_neib_a[i];
        end
    end
end

always@(posedge clk_vc) begin : blk8_neib_r
	integer i;
	if(reg_avc_mode ? amvp_blk_sz[0] : mrg_blk_sz[0]) begin
        blk8_neib_b_r <= blk32_neib_b[0];
		blk8_neib_a_r <= blk32_neib_a[0];	
	end
end

endmodule
