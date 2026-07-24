module sht_mdl
#(
    parameter DEPTH      = 2,
    parameter DATA_W     = 32,
    parameter ADDR_LG2_W = $clog2(DEPTH),
    parameter RST_EN     = 0
)
(
    // Output
    output reg          full_n,
    output reg          n_full_n,
    output reg          empty_n,
    output reg          n_empty_n,
    output [DATA_W-1:0] q,
    // Input
    input               clk,
    input               rstz,
    input               push,
    input               pop,
    input [DATA_W-1:0]  d
);

// loacal parameter

// register declaration

reg [DATA_W-1:0]    mem_cells [DEPTH-1:0];

// Wire Declaration

wire                g_push;
wire                g_pop;

reg [DATA_W-1:0]    n_mem_cells [DEPTH-1:0];

// Combinational Logic

// Control signals
assign g_push   = full_n & push;
assign g_pop    = empty_n & pop;
assign q        = mem_cells[0];

// Main block
generate
    if(ADDR_LG2_W == 0 & DEPTH == 1)begin: depth_1_buf
        reg single_full_n;

        always@(*)begin
            case({g_push, g_pop})
                {1'b0, 1'b1}: {n_full_n, n_empty_n} = {1'b1, 1'b0};
                {1'b1, 1'b0}: {n_full_n, n_empty_n} = {1'b0, 1'b1};
                default:      {n_full_n, n_empty_n} = {single_full_n, empty_n};
            endcase
        end

        always@(*)  full_n  =   single_full_n | g_pop;

        always@(*)begin
            if(g_push)
                n_mem_cells[0] = d;
            else
                n_mem_cells[0] = mem_cells[0];
        end

        always@(posedge clk or negedge rstz)begin
            if(~rstz)begin
                single_full_n  <= 1;
                empty_n        <= 0;
            end else if(g_push | g_pop)begin
                single_full_n  <= n_full_n;
                empty_n        <= n_empty_n;
            end
        end

    end else begin: normal_buf
        reg     [ADDR_LG2_W:0]   sh_ptr;
        reg     [ADDR_LG2_W-1:0] sh_ptr_m1;

        reg     [ADDR_LG2_W:0]   n_sh_ptr;
        reg     [ADDR_LG2_W:0]   n_sh_ptr_m1;
        reg     [DEPTH-1:0]      push_en;
        reg     [DEPTH-1:0]      pop_en;

        always@(*)begin
            case({g_push, g_pop})
                {1'b0, 1'b1}:   n_sh_ptr = sh_ptr - 1;
                {1'b1, 1'b0}:   n_sh_ptr = sh_ptr + 1;
                default:        n_sh_ptr = sh_ptr;
            endcase
        end

        always@(*)begin
            if(g_push ^ g_pop)
                n_sh_ptr_m1 =  |n_sh_ptr ? (n_sh_ptr - 1) : 0;
            else
                n_sh_ptr_m1 =  {1'b0, sh_ptr_m1};
        end

        always@(*)begin
            n_full_n    =   n_sh_ptr != DEPTH;
            n_empty_n   =   |n_sh_ptr;
        end

        always@(*)begin: gen_en_blk
            integer i;

            pop_en = 0; push_en = 0;
            for(i = 0; i < DEPTH; i = i + 1)begin
                // pop signals
                if(g_pop & (i < sh_ptr) & (i != DEPTH-1))
                    pop_en[i]   =   1'b1;

                // push signals
                case({g_push, g_pop})
                    2'b10:  push_en[i] = i == sh_ptr;
                    2'b11:  push_en[i] = i == sh_ptr_m1;
                endcase
            end
        end

        always@(*)begin: sht_blk
            integer i;

            for(i = 0; i < DEPTH; i = i + 1)begin
                n_mem_cells[i] = mem_cells[i];
                case({pop_en[i], push_en[i]})
                    2'b01,
                    2'b11:  n_mem_cells[i] = d;
                    2'b10:  begin
                        if(i != DEPTH-1)
                            n_mem_cells[i] = mem_cells[i+1];
                    end
                    default:n_mem_cells[i] = mem_cells[i];
                endcase
            end
        end

        always@(posedge clk or negedge rstz)begin
            if(~rstz)begin
                full_n      <= 1;
                empty_n     <= 0;
                sh_ptr      <= 0;
                sh_ptr_m1   <= 0;
            end else if(g_push | g_pop)begin
                full_n      <= n_full_n;
                empty_n     <= n_empty_n;
                sh_ptr      <= n_sh_ptr;
                sh_ptr_m1   <= n_sh_ptr_m1[0+:ADDR_LG2_W];
            end
        end

    end
endgenerate

// Function/Task



// Instantiation



// State Machine



// Sequence Logic

// Buffer Block
generate
    if(RST_EN == 1)begin: en_rst_buf
        always@(posedge clk or negedge rstz)begin: buf_blk
            integer i;

            if(~rstz)begin
                for(i = 0; i < DEPTH; i = i + 1)
                    mem_cells[i]    <= 0;
            end else if(g_push | g_pop)begin
                for(i = 0; i < DEPTH; i = i + 1)
                    mem_cells[i]    <= n_mem_cells[i];
            end
        end
    end else begin: dis_rst_buf
        always@(posedge clk)begin: buf_blk
            integer i;

            for(i = 0; i < DEPTH; i = i + 1)begin
                if(g_push | g_pop)
                    mem_cells[i]    <= n_mem_cells[i];
            end
        end
    end
endgenerate

endmodule
