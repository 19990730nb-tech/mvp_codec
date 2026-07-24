// -----------------------------------------------------------------------------
// Parameterized request sequencer for one neighbor-memory class (A, B,
// colocated, or reference list).  Metadata for every accepted request is kept
// in a FIFO so a later mem2ip_rd_lat pulse can be matched to the correct slot.
// -----------------------------------------------------------------------------
`include "ve_defines.v"
module vc_mvp_rd_mem
#(
    parameter NEIB_DIR_TYPE = 0,  // 0:B, 1:A, 2:Col, 3: other
    parameter AVAIL_W       = 3,
    parameter MEM_ADDR_W    = 6,
    parameter DEPTH         = 4,
    parameter VC_CTU_X_NB   = 7,
    parameter ADDR_LG2_W    = $clog2(DEPTH),
    parameter DATA_W        = AVAIL_W + 3, // neib a,b default value
    parameter RST_EN        = 1
)
(
// Output

output reg                ip2mem_req,
output reg [MEM_ADDR_W-1:0] ip2mem_addr, // limitation 0~63
output      [DATA_W-1:0]  cmdq2ip_info,
output                    rd_mem_idle,

// Input

input                     clk_vc,
input                     vc_rst_z,
input                     reg_avc_mode,
input                     reg_slice_go,
input [VC_CTU_X_NB-1:0]   reg_pic_width_ctu_m1,
input                     ip_cu_start,
input [ 2:0]              ctux, // ctux 0~7
input                     ctuy, // ctuy even, odd
input [ 2:0]              cux,
input [ 2:0]              cuy,
input [AVAIL_W-1:0]       ip_avail,
input [ 3:0]              mem_avail_cnt,

// from mem
input                     mem2ip_gnt,
input                     mem2ip_rd_lat
);

// local parameter

localparam MEM_IDLE     =0,
           MEM_GET      =1,
           MEM_CHK_DQ   =2;

// Registers Declaration

reg    [ 2:0]    fsm_mem_cs;
reg    [ 3:0]    mem_cnt;
reg   [DATA_W-1:0] ip2cmdq_info;

// Wire Declaration

wire   [ 3:0]    mem_cnt_ptr;
reg    [ 2:0]    fsm_mem_ns;
wire             ip2mem_req_n;
reg   [MEM_ADDR_W-1:0] ip2mem_addr_n;
wire             last_hsk;
//wire  [ 3:0]    mem_avail_cnt;

wire   [DATA_W-1:0] d,q;
reg   [DATA_W-1:0] ip2cmdq_info_n;
wire             full_n;
wire             n_full_n;
wire             empty_n;
wire             n_empty_n;
wire             push;
wire             pop;
wire   [2:0]     neib_b_addr;
wire   [1:0]     col_c_addr;
reg unsigned [2:0] x32_c0;
reg unsigned [2:0] y32_c0;
reg unsigned [2:0] x16_c0;
reg unsigned [2:0] y16_c0;
reg unsigned [3:0] x8_c0;
reg unsigned [3:0] y8_c0;
wire             blk8_b2_con;

// combinational logic

// fifo io
// The memory can return responses after the request address has advanced.
// Queue one-hot destination metadata on every accepted request, then pop that
// metadata with the matching read-latency pulse to route the returned payload.
assign push      = ip2mem_req & mem2ip_gnt;
assign pop       = mem2ip_rd_lat;
assign d         = ip2cmdq_info;
assign cmdq2ip_info= q;

assign rd_mem_idle = fsm_mem_cs[MEM_IDLE] | (fsm_mem_cs[MEM_CHK_DQ] & mem2ip_rd_lat);
assign ip2mem_req_n = (fsm_mem_cs[MEM_IDLE]   & ip_cu_start)   |   // req neib 0
                      (fsm_mem_cs[MEM_CHK_DQ] & ip_cu_start)   |
                      (fsm_mem_cs[MEM_GET]   & mem2ip_gnt & (mem_cnt !=(mem_avail_cnt-1)));   // req neib 1 (2)
assign last_hsk = ( mem_cnt == (mem_avail_cnt-1) ) & mem2ip_gnt;

assign mem_cnt_ptr = ( ip2mem_req & mem2ip_gnt ) ? (mem_cnt + 1) : mem_cnt;

assign neib_b_addr = { (reg_pic_width_ctu_m1[2] ? ctux[2] : (ctux[2]^(reg_avc_mode ? cuy[1] : ctuy))), ctux[1:0] };

generate
    if( NEIB_DIR_TYPE == 0 ) begin : mem_neib_b_dir

        // B-memory words each contain two horizontal neighbor entries.  The
        // metadata bit selects which pair in the eight-entry staging cache is
        // updated when this request returns.
        always@(*) begin : ip2cmdq_info_n_blk
            ip2cmdq_info_n = 0;
            if(mem_cnt_ptr==0)
                ip2cmdq_info_n[cux[1]+cux[0]] = 1; // 000,100=>0, 001,101=>1, 010,110=>1, 011,111=>2
            else if(mem_cnt_ptr==1)
                ip2cmdq_info_n[cux[1]+cux[0]+1] = 1;
            else if(mem_cnt_ptr==2)
                if(cux[1:0]==0)
                    ip2cmdq_info_n[2] = 1;
                else // cux[1:0]==2
                    ip2cmdq_info_n[3] = 1;
            else // mem_cnt_ptr==3
                ip2cmdq_info_n[3] = 1;
        end

        always@(*) begin
            if(mem_cnt_ptr==0) begin
                ip2mem_addr_n[5:3] = (cux[2:0] == 3'd0) ? neib_b_addr-3'd1 : neib_b_addr;
                ip2mem_addr_n[2:0] = cux-1;
            end
            else if(mem_cnt_ptr==1) begin
                ip2mem_addr_n[5:3] = (cux[2:0] == 3'd7) ? neib_b_addr+3'd1 : neib_b_addr;
                ip2mem_addr_n[2:0] = (cux[1:0] == 2'd0) ? {cux[2],2'd0} :
                                     (cux[1:0] == 2'd1) ? {cux[2],2'd2} :
                                     (cux[1:0] == 2'd2) ? {cux[2],2'd2} :
                                                          {!cux[2],2'd0};
            end
            else if(mem_cnt_ptr==2) begin
                ip2mem_addr_n[5:3] = (cux[2:0] == 3'd6) ? neib_b_addr+3'd1 : neib_b_addr;
                ip2mem_addr_n[2:0] = (cux[1:0] == 2'd0) ? {cux[2],2'd2} : cux+2;
            end
            else begin
                ip2mem_addr_n[5:3] = (cux[2:0] == 3'd4) ? neib_b_addr+3'd1 : neib_b_addr;
                ip2mem_addr_n[2:0] = (cux[2:0] == 3'd0) ? 3'd4 : 3'd0;
            end
        end

    end
    else if (NEIB_DIR_TYPE == 1 ) begin : mem_neib_a_dir
        // A-memory uses the same scheme vertically, with three possible word
        // destinations covering the six-entry staging cache.
        always@(*) begin : ip2cmdq_info_n_blk
            ip2cmdq_info_n=0;
            if(mem_cnt_ptr==0)
                ip2cmdq_info_n[cuy[1]] = 1;
            else if(mem_cnt_ptr==1)
                ip2cmdq_info_n[cuy[1]+1] = 1;
            else // mem_cnt_ptr==2
                ip2cmdq_info_n[2] = 1;
        end

        always@(*) begin
            if(mem_cnt_ptr==0) begin
                ip2mem_addr_n[2:0] = cuy;
            end
            else if(mem_cnt_ptr==1) begin
                ip2mem_addr_n[2:0] = (cuy[1:0] == 2'd0) ? {cuy[2],2'd2} :
                                     (cuy[1:0] == 2'd1) ? {cuy[2],2'd2} :
                                     (cuy[1:0] == 2'd2) ? 3'd4 :
                                                          3'd4;
            end
            else begin
                ip2mem_addr_n[2:0] = 3'd4;
            end
        end
    end
    else if ( NEIB_DIR_TYPE == 2)begin : mem_neib_col_dir
        // Colocated storage is tiled in 16x16 units.  The first request reads
        // the tile containing the CU; later requests move right/down according
        // to the CU size so both temporal-candidate positions are available.
        always@(*) begin : ip2cmdq_info_n_blk
            integer i;
            for(i=0; i<3 ; i++)
                ip2cmdq_info_n[i] = mem_cnt_ptr==4'(i);
        end

        assign col_c_addr = { (reg_pic_width_ctu_m1[1] ? ctux[1] : (ctux[1]^ctuy) ), ctux[0] };

        always@(*) begin
            x32_c0 = cux[2:1] + 2;
            y32_c0 = cuy[2:1] + 2;
            x16_c0 = cux[2:1] + 1;
            y16_c0 = cuy[2:1] + 1;
        end

        always@(*) begin
            if(mem_cnt_ptr==0) begin
                ip2mem_addr_n[5:4] = col_c_addr;
                ip2mem_addr_n[3:0] = {cuy[2],cux[2],cuy[1],cux[1]};
            end
            else if(mem_cnt_ptr==1) begin
                ip2mem_addr_n[5:4] = (cuy[0]==1 & cux[0]==0) ? col_c_addr : col_c_addr+x16_c0[2];
                ip2mem_addr_n[3:0] = ( cux[0]&!cuy[0]) ? {cuy[2],x16_c0[1],cuy[1],x16_c0[0]}: // hor  Ex c1,c4
                                      (!cux[0]& cuy[0]) ? {y16_c0[1],cux[2],y16_c0[0],cux[1]}: // ver  Ex c1,c3
                                                          {y16_c0[1],x16_c0[1],y16_c0[0],x16_c0[0]}; // dia Ex c1, c6
            end
            else begin
                ip2mem_addr_n[5:4] = col_c_addr+x32_c0[2];
                ip2mem_addr_n[3:0] = {y32_c0[1],x32_c0[1],y32_c0[0],x32_c0[0]};
            end
        end
    end
    else begin : others_mem
        // Reference-list reads use a linear address and one metadata bit per
        // active reference index.
        always@(*) begin : ip2cmdq_info_n_blk
            integer i;
            for(i=0 ; i<AVAIL_W ; i++) begin
                ip2cmdq_info_n[i] = ip_avail[i] & mem_cnt_ptr == i[3:0];
            end
        end

        always@(*) begin
            //integer i;
            //for(i=0 ; i<AVAIL_W ; i=i+1) begin
            ip2mem_addr_n = (ip2mem_req&mem2ip_gnt)? 4'(mem_cnt+1) : 4'(mem_cnt);
            //end
        end
    end
endgenerate

// function/task



// instantiation

sht_mdl
#(
    .DEPTH     (DEPTH),
    .ADDR_LG2_W (ADDR_LG2_W),
    .DATA_W    (DATA_W),
    .RST_EN    (RST_EN)
)
mem_cmd_fifo(
// output
    .full_n    (full_n),
    .n_full_n  (n_full_n),
    .empty_n   (empty_n),
    .n_empty_n (n_empty_n),
    .q         (q),
// input
    .clk       (clk_vc),
    .rstz      (vc_rst_z),
    .push      (push),
    .pop       (pop),
    .d         (d)
);

// state machine

// MEM_GET issues all reads for one CU.  MEM_CHK_DQ then prevents a new batch
// from reusing the metadata FIFO until every outstanding response has drained.
always@(*) begin : fsm_mem
    fsm_mem_ns = 0;
    case(1) //synopsys parallel_case
        fsm_mem_cs[MEM_IDLE] : begin
            if( ip_cu_start )
                fsm_mem_ns[MEM_GET] = 1;
            else
                fsm_mem_ns[MEM_IDLE] = 1;
        end
        fsm_mem_cs[MEM_GET] : begin
            if( last_hsk )
                fsm_mem_ns[MEM_CHK_DQ] = 1;
            else
                fsm_mem_ns[MEM_GET] = 1;
        end
        fsm_mem_cs[MEM_CHK_DQ] : begin
            if( !n_empty_n )
                fsm_mem_ns[MEM_IDLE] = 1;
            else
                fsm_mem_ns[MEM_CHK_DQ] = 1;
        end
    endcase
end

// sequence logic

always@(posedge clk_vc or negedge vc_rst_z)begin
    if(~vc_rst_z)
        fsm_mem_cs       <= 1;
    else if(reg_slice_go)
        fsm_mem_cs       <= 1;
    else if( fsm_mem_cs != fsm_mem_ns )
        fsm_mem_cs       <= fsm_mem_ns;
end

always@(posedge clk_vc or negedge vc_rst_z)begin
    if(~vc_rst_z)
        mem_cnt <= 0;
    else if(reg_slice_go)
        mem_cnt <= 0;
    else if( last_hsk )
        mem_cnt <= 0;
    else if( fsm_mem_cs[MEM_GET] & ip2mem_req & mem2ip_gnt)
        mem_cnt <= mem_cnt + 1;
end

always@(posedge clk_vc or negedge vc_rst_z)begin
    if(~vc_rst_z)begin
        ip2mem_req   <= 0;
        ip2mem_addr  <= 0;
        ip2cmdq_info <= 0;
    end
    else if(reg_slice_go) begin
        ip2mem_req   <= 0;
        ip2mem_addr  <= 0;
        ip2cmdq_info <= 0;
    end
    else begin
        if( ip2mem_req & mem2ip_gnt & !ip2mem_req_n )
            ip2mem_req <= 0;
        else if( ip2mem_req_n )
            ip2mem_req <= 1;

        if( ip2mem_req_n ) begin
            ip2mem_addr  <= ip2mem_addr_n;
            ip2cmdq_info <= ip2cmdq_info_n;
        end
    end
end

endmodule
