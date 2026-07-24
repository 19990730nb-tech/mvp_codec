`include "ve_defines.v"
module  vc_mvp_ctrl
#(  parameter MAX_BLK_SZ = 2, // 3:(blk32, blk16, blk8), 2:(blk16, blk8), 1:blk8
    parameter NUM_REF = 2,
    parameter VC_CTU_X_NB = 7,
    parameter VC_CTU_Y_NB = 7,
    parameter AMVP_OR_MRG = 1   // 1:amvp, 0:merge
)
(
// output

output      [3:0]           cur_ref_idx,
output      [2:0]           cu_blk_en,
output      [2:0][13:0]     cu_cmd_out,
output      [2:0]           empty_n,
output                      blk_sz_lat,
output      [2:0]           n_blk_sz,
// neib
output                      neib_cu_start,
// cand
output                      cand_cu_start,
// mode
output  reg [MAX_BLK_SZ-1:0]pop,
// dbg
output  [6:0]               dbg_fsm_mvp_cs,

// input

input                       clk_vc,
input                       vc_rst_z,
input                       reg_avc_mode,
input                       reg_i_slice,
input                       reg_slice_go,
input   [ 3:0]              reg_num_ref_l0_act_m1,
// CTU Layer
input                       cur_ctu_start,
// CU Layer
input   [ 2:0]              cur_cu_start,
input   [ 2:0]              cur_cu_x,
input   [ 2:0]              cur_cu_y,
input   [ 2:0][ 2:0]        cur_cu_b_avail,
input   [ 2:0][ 1:0]        cur_cu_a_avail,
input                       cur_cu_is_zmv,
input                       cur_cu_is_skip,
input                       cur_cu_terminate,
input   [2:0]               is_pic_right,
// neib
input                       neib_done_con,
// cand
input                       cand_blk_done,
input                       cand_blk_idle
//input [1:0]               cand_blk_sz
);

// local parameter

localparam  AMVP_IDLE = 0,
            AMVP_WAIT_CU_START = 1,
            AMVP_WAIT_NEIB_DONE= 2,
            AMVP_CAND_BLK8= 3,
            AMVP_CAND_BLK16= 4,
            AMVP_CAND_BLK32= 5,
            AMVP_BLK_DONE = 6;

// register declaration

reg     [ 3:0]  ref_idx [0:MAX_BLK_SZ-1] ;
reg     [ 6:0]  fsm_mvp_cs;
reg             blk_sz_smallest_only;

// wire declaration

reg     [ 6:0]  fsm_mvp_ns;
reg     [MAX_BLK_SZ-1:0]        push;
//reg   [MAX_BLK_SZ-1:0]        pop;
wire    [MAX_BLK_SZ-1:0]        full_n;
//wire  [MAX_BLK_SZ-1:0]        empty_n;
wire    [MAX_BLK_SZ-1:0]        n_empty_n;
reg     [MAX_BLK_SZ-1:0][13:0]  cu_cmdq_in; 
wire    [MAX_BLK_SZ-1:0][13:0]  cu_cmdq_out; 
//reg   [13+2:0]    cu_cmd_out; // cu_cmdq_out, with blk_sz
reg     [MAX_BLK_SZ-1:0]        chk_ref_done;
reg     [MAX_BLK_SZ-1:0]        cur_ref_upd;
reg     [MAX_BLK_SZ-1:0]        chk_ref_equal;
wire    [2:0]       cux;
wire    [2:0]       cuy;
wire    [2:0]       cand_blk_sz;
wire    [2:0]       cmdq_cu_start;
wire    [3:0]       num_ref;
wire    [3:0]       num_ref_m1;
wire    [3:0]       ref_idx_sel;
wire                neib_cu_start_w;

genvar              sz;

// combinational logic

assign dbg_fsm_mvp_cs = fsm_mvp_cs;

assign cu_blk_en[0] =  fsm_mvp_cs[AMVP_CAND_BLK8];
assign cu_blk_en[1] =  fsm_mvp_cs[AMVP_CAND_BLK16];
assign cu_blk_en[2] =  fsm_mvp_cs[AMVP_CAND_BLK32];

assign num_ref = reg_num_ref_l0_act_m1 + 1;
assign num_ref_m1 = reg_num_ref_l0_act_m1;

// cux[0+:3], cuy[3+:3], avail_b[6+:3], avail_a[9+:2], zmv[11], skip[12], term[13]
always@(*) begin : ccu_cmd_queue_blk
    integer i;
    for( i=0 ; i<MAX_BLK_SZ ; i=i+1 ) begin
        // cu_cmdq_in
        cu_cmdq_in[i] = {   
                            cur_cu_terminate,       // 13
                            cur_cu_is_skip,         // 12
                            cur_cu_is_zmv,          // 11       
                            cur_cu_a_avail[i][1:0], // 10:9
                            {reg_avc_mode & (AMVP_OR_MRG == 1) & ~is_pic_right[i] ? 1'b0 : cur_cu_b_avail[i][2], cur_cu_b_avail[i][1:0]},   // 8:6
                            cur_cu_y,               // 5:3
                            cur_cu_x                // 2:0
                        };
    end
end

generate
    if(AMVP_OR_MRG==1) begin : gen_amvp_ccu_cmd_push_pop_blk

        always@(*) begin : for_amvp_ccu_cmd_push_pop_blk
            integer i;
            for( i=0 ; i<MAX_BLK_SZ ; i=i+1 ) begin
                // push
                push[i] = cur_cu_start[i] & ~reg_i_slice & !cur_cu_is_skip & !cur_cu_terminate;

                // pop
                if( cand_blk_sz[i] & cand_blk_done )
                    pop[i] = ref_idx[i] == num_ref_m1;
                else
                    pop[i] = 0;

                // chk_ref_done
                chk_ref_done[i] = ref_idx[i] == (num_ref);

                // cur_ref_upd
                if(i==0 )
                    cur_ref_upd[i] = ref_idx[i] == cur_ref_idx;
                else
                    cur_ref_upd[i] = ref_idx[i] > cur_ref_idx;

                // chk_ref_equal
                chk_ref_equal[i] = (ref_idx[i] == cur_ref_idx);
            end // for
        end // always
    end // if parameter

    else begin : gen_mrg_ccu_cmd_push_pop_blk

        always@(*) begin : for_mrg_ccu_cmd_push_pop_blk
            integer i;
            for( i=0 ; i<MAX_BLK_SZ ; i=i+1 ) begin
                // push
                push[i] = cur_cu_start[i] & ~reg_i_slice & !cur_cu_is_zmv & !cur_cu_terminate;

                // pop
                if( cand_blk_sz[i] & cand_blk_done )
                    pop[i] = 1;
                else
                    pop[i] = 0;
            end
        end // always
    end // if parameter
endgenerate
        
generate
    if( MAX_BLK_SZ == 2 & AMVP_OR_MRG==1) begin : cu_cmd_out_amvp_max_16_blk
        assign cu_cmd_out[2] = 0;
        assign cu_cmd_out[1:0] = cu_cmdq_out[1:0];
        assign empty_n[2] = 0;
        assign cmdq_cu_start[2] = 0;
        assign cmdq_cu_start[1] = fsm_mvp_cs[AMVP_WAIT_CU_START] & empty_n[1];
        assign cmdq_cu_start[0] = fsm_mvp_cs[AMVP_WAIT_CU_START] & empty_n[0];
        assign ref_idx_sel = cand_blk_sz[1] ? ref_idx[1] : ref_idx[0];
        /*
        assign cand_cu_start = (fsm_mvp_cs[AMVP_WAIT_NEIB_DONE] & neib_done_con) |
                                (fsm_mvp_cs[AMVP_CAND_BLK8]    & cand_blk_idle);
        */
        assign cand_cu_start = (fsm_mvp_cs[AMVP_CAND_BLK8]   & !cand_blk_done) |
                               (fsm_mvp_cs[AMVP_CAND_BLK16]  & !cand_blk_done);
    end
    else if(MAX_BLK_SZ == 3 & AMVP_OR_MRG==1)begin : cu_cmd_out_amvp_max_32_blk
        assign cu_cmd_out[2:0] = cu_cmdq_out[2:0];
        assign cmdq_cu_start[2] = fsm_mvp_cs[AMVP_WAIT_CU_START] & empty_n[2];
        assign cmdq_cu_start[1] = fsm_mvp_cs[AMVP_WAIT_CU_START] & empty_n[1];
        assign cmdq_cu_start[0] = fsm_mvp_cs[AMVP_WAIT_CU_START] & empty_n[0];
        assign ref_idx_sel = cand_blk_sz[1] ? ref_idx[1] :
                                                 ref_idx[0];
        assign cand_cu_start = (fsm_mvp_cs[AMVP_CAND_BLK8]  & !cand_blk_done) |
                               (fsm_mvp_cs[AMVP_CAND_BLK16] & !cand_blk_done) |
                               (fsm_mvp_cs[AMVP_CAND_BLK32] & !cand_blk_done);
    end
    else if( AMVP_OR_MRG==0 ) begin : cu_cmd_out_merge_blk
        assign cu_cmd_out[2:0] = cu_cmdq_out[2:0];
        assign cmdq_cu_start[2] =0;// fsm_mvp_cs[AMVP_WAIT_CU_START] & empty_n[2];
        assign cmdq_cu_start[1] =0;// fsm_mvp_cs[AMVP_WAIT_CU_START] & empty_n[1];
        assign cmdq_cu_start[0] =0;// fsm_mvp_cs[AMVP_WAIT_CU_START] & empty_n[0];
        assign cand_cu_start = (fsm_mvp_cs[AMVP_CAND_BLK8]  & !cand_blk_done) |
                               (fsm_mvp_cs[AMVP_CAND_BLK16] & !cand_blk_done) |
                               (fsm_mvp_cs[AMVP_CAND_BLK32] & !cand_blk_done);
    end
endgenerate

assign  cand_blk_sz = cu_blk_en;
assign  cux = cu_cmd_out[0][0+:3];
assign  cuy = cu_cmd_out[0][3+:3];    
assign  neib_cu_start_w = fsm_mvp_cs[AMVP_WAIT_CU_START] & (|empty_n) |
                          fsm_mvp_cs[AMVP_BLK_DONE] & (|empty_n);

assign  neib_cu_start = neib_cu_start_w;

assign  n_blk_sz   =  {fsm_mvp_ns[AMVP_CAND_BLK32], fsm_mvp_ns[AMVP_CAND_BLK16], fsm_mvp_ns[AMVP_CAND_BLK8]};
assign  blk_sz_lat =  !fsm_mvp_cs[AMVP_CAND_BLK8]   & fsm_mvp_ns[AMVP_CAND_BLK8]  |
                      !fsm_mvp_cs[AMVP_CAND_BLK16]  & fsm_mvp_ns[AMVP_CAND_BLK16] |
                      !fsm_mvp_cs[AMVP_CAND_BLK32]  & fsm_mvp_ns[AMVP_CAND_BLK32];

// function/task



// instantiation

generate
    for(sz=0; sz< MAX_BLK_SZ ; sz=sz+1) begin : ccu_cmdq_blk
        sht_mdl
        #(
            //.DEPTH       (2**(2-sz)),
            .DEPTH       (1),
            //.ADDR_LG2_W  (sz), // 2:32, 1:16, 0:8
            .DATA_W      (14),
            .RST_EN      (1)
        )
        ccu_cmdq(
        // output
            .full_n      (full_n[sz]),
            .n_full_n    (),
            .empty_n     (empty_n[sz]),
            .n_empty_n   (n_empty_n[sz]),
            .q           (cu_cmdq_out[sz]),
        // input
            .clk         (clk_vc),
            .rstz        (vc_rst_z),
            .push        (push[sz]),
            .pop         (pop[sz]),
            .d           (cu_cmdq_in[sz])
        );
    end
endgenerate

// state machine

generate
if(AMVP_OR_MRG) begin : fsm_amvp_ctrl

    always@(*) begin : fsm_mvp_ctrl
        fsm_mvp_ns = 0;
        case(1) //synopsys parallel_case
            fsm_mvp_cs[AMVP_IDLE]: begin
                if( cur_ctu_start & ~reg_i_slice )
                    fsm_mvp_ns[AMVP_WAIT_CU_START] = 1;
                else
                    fsm_mvp_ns[AMVP_IDLE] = 1;
            end
            fsm_mvp_cs[AMVP_WAIT_CU_START] : begin
                if( |empty_n)
                    fsm_mvp_ns[AMVP_WAIT_NEIB_DONE] = 1;
                else
                    fsm_mvp_ns[AMVP_WAIT_CU_START] = 1;
            end
            fsm_mvp_cs[AMVP_WAIT_NEIB_DONE] : begin
                if( neib_done_con )
                    fsm_mvp_ns[AMVP_CAND_BLK8] = 1;
                else
                    fsm_mvp_ns[AMVP_WAIT_NEIB_DONE] = 1;
            end
            fsm_mvp_cs[AMVP_CAND_BLK8] : begin
                if( cand_blk_done ) begin
                    if(empty_n[1])
                        fsm_mvp_ns[AMVP_CAND_BLK16] = 1;
                    else if(empty_n[2])
                        fsm_mvp_ns[AMVP_CAND_BLK32] = 1;
                    else
                        fsm_mvp_ns[AMVP_BLK_DONE] = 1;
                end
                else
                    fsm_mvp_ns[AMVP_CAND_BLK8] = 1;
            end
            fsm_mvp_cs[AMVP_CAND_BLK16] : begin
                if( cand_blk_done ) begin
                    if(empty_n[2])
                        fsm_mvp_ns[AMVP_CAND_BLK32] = 1;
                    else// if(empty_n[2])
                        fsm_mvp_ns[AMVP_BLK_DONE] = 1;
                end
                else
                    fsm_mvp_ns[AMVP_CAND_BLK16] = 1;
            end
            fsm_mvp_cs[AMVP_CAND_BLK32] : begin
                if( cand_blk_done )
                    fsm_mvp_ns[AMVP_BLK_DONE] = 1;
                else
                    fsm_mvp_ns[AMVP_CAND_BLK32] = 1;
            end
            fsm_mvp_cs[AMVP_BLK_DONE] : begin // amvp diff to mrg
                if( &chk_ref_done ) begin
                    if(cux==7 & cuy==7)
                        fsm_mvp_ns[AMVP_IDLE] = 1;
                    else
                        fsm_mvp_ns[AMVP_WAIT_CU_START] = 1;
                end
                else
                    fsm_mvp_ns[AMVP_WAIT_NEIB_DONE] = 1;
            end
        endcase
    end
end // if parameter

else begin : fsm_merge_ctrl

    always@(*) begin : fsm_mvp_ctrl
        fsm_mvp_ns = 0;
        case(1) //synopsys parallel_case
            fsm_mvp_cs[AMVP_IDLE]: begin
                if( cur_ctu_start & ~reg_i_slice)
                    fsm_mvp_ns[AMVP_WAIT_CU_START] = 1;
                else
                    fsm_mvp_ns[AMVP_IDLE] = 1;
            end
            fsm_mvp_cs[AMVP_WAIT_CU_START] : begin
                if( |empty_n )
                    fsm_mvp_ns[AMVP_WAIT_NEIB_DONE] = 1;
                else
                    fsm_mvp_ns[AMVP_WAIT_CU_START] = 1;
            end
            fsm_mvp_cs[AMVP_WAIT_NEIB_DONE] : begin
                if( neib_done_con )
                    fsm_mvp_ns[AMVP_CAND_BLK8] = 1;
                else
                    fsm_mvp_ns[AMVP_WAIT_NEIB_DONE] = 1;
            end
            fsm_mvp_cs[AMVP_CAND_BLK8] : begin
                if( cand_blk_done ) begin
                    if(empty_n[1])
                        fsm_mvp_ns[AMVP_CAND_BLK16] = 1;
                    else if(empty_n[2])
                        fsm_mvp_ns[AMVP_CAND_BLK32] = 1;
                    else
                        fsm_mvp_ns[AMVP_BLK_DONE] = 1;
                end
                else
                    fsm_mvp_ns[AMVP_CAND_BLK8] = 1;
            end
            fsm_mvp_cs[AMVP_CAND_BLK16] : begin
                if( cand_blk_done ) begin
                    if(empty_n[2])
                        fsm_mvp_ns[AMVP_CAND_BLK32] = 1;
                    else// if(empty_n[2])
                        fsm_mvp_ns[AMVP_BLK_DONE] = 1;
                end
                else
                    fsm_mvp_ns[AMVP_CAND_BLK16] = 1;
            end
            fsm_mvp_cs[AMVP_CAND_BLK32] : begin
                if( cand_blk_done )
                    fsm_mvp_ns[AMVP_BLK_DONE] = 1;
                else
                    fsm_mvp_ns[AMVP_CAND_BLK32] = 1;
            end
            fsm_mvp_cs[AMVP_BLK_DONE] : begin // mrg diff to amvp
                if(cux==7 & cuy==7)
                    fsm_mvp_ns[AMVP_IDLE] = 1;
                else
                    fsm_mvp_ns[AMVP_WAIT_CU_START] = 1;
            end
        endcase
    end
end // if parameter
endgenerate

// sequence logic

generate
    if(AMVP_OR_MRG==1) begin : amvp_ref_idx_blk

        always@( posedge clk_vc or negedge vc_rst_z ) begin
            if( ~vc_rst_z ) begin
                blk_sz_smallest_only <= 0;
            end
            else if( |cmdq_cu_start ) begin
                if( reg_num_ref_l0_act_m1 >= 1 & cmdq_cu_start == 3'b001 )begin
                    blk_sz_smallest_only <= 1;
                end
                else begin
                    blk_sz_smallest_only <= 0;
                end
            end
        end

        always@(posedge clk_vc or negedge vc_rst_z)begin : ref_idx_seq_blk
            integer i;
            if(~vc_rst_z) begin
                for(i=0 ; i<MAX_BLK_SZ ; i=i+1) begin
                    ref_idx[i] <= 0;
                end
            end
            else if( |cmdq_cu_start ) begin
                for(i=0 ; i<MAX_BLK_SZ ; i=i+1) begin
                    if(cmdq_cu_start[i])
                        ref_idx[i] <= 0;
                    else
                        ref_idx[i] <= num_ref;
                end
            end
            else if( &chk_ref_done & fsm_mvp_cs[AMVP_BLK_DONE] ) begin
                for(i=0 ; i<MAX_BLK_SZ ; i=i+1) begin
                    ref_idx[i] <= 0;
                end
            end
            else if( cand_blk_done ) begin
                for(i=0 ; i<MAX_BLK_SZ ; i=i+1) begin
                    if( cand_blk_sz[i] )
                        ref_idx[i] <= ref_idx[i] + 1;
                end
            end
        end

        reg [3:0] cur_ref_idx_r;
        assign cur_ref_idx = cur_ref_idx_r;
        always@(posedge clk_vc or negedge vc_rst_z)begin
            if(~vc_rst_z) begin
                cur_ref_idx_r <= 0;
            end
            else if( cand_blk_done & (&cur_ref_upd) ) begin
                if(cur_ref_idx_r == num_ref_m1 )
                    cur_ref_idx_r <= 0;
                else
                    cur_ref_idx_r <= cur_ref_idx_r +1;
            end
        end
    end
    else begin : merge_ref_idx_blk
        assign cur_ref_idx = 0;
    end
endgenerate

always@(posedge clk_vc or negedge vc_rst_z)begin 
    if(~vc_rst_z) begin
        fsm_mvp_cs <= 1;
    end
    else if(reg_slice_go) begin
        fsm_mvp_cs <= 1;
    end
    else if( fsm_mvp_cs != fsm_mvp_ns )begin
        fsm_mvp_cs <= fsm_mvp_ns;
    end
end 

endmodule
