`include "ve_defines.v"
module vc_mvp_cand_prior
#(
    parameter	MVP_SCALE_EN = 0,
	parameter	AMVP_OR_MRG = 1,
	parameter   A_W = AMVP_OR_MRG ? 4 : 2,
    parameter   B_W = AMVP_OR_MRG ? 6 : 3
)
(
    //*************************
    //         Output
    //*************************
    output [A_W-1:0] cand_a,
    output [B_W-1:0] cand_b,
    output [3:0]     cand_c,
    //*************************
    //         Input
    //*************************
    //neighbor available (available & not intra)
    input       a0_avail,
    input       a1_avail,
    input       b0_avail,
    input       b1_avail,
    input       b2_avail,
    input       c0_avail,
    input       c1_avail,
    input       reg_tmp_mvp_flag,
    input       reg_avc_mode,
    // current ref info
    input   [ 7:0]  cur_pocdif,
    input   [31:0]  ref_poc,
    input           ref_long,
    //neighbor long
    input           a0_long,
    input           a1_long,
    input           b0_long,
    input           b1_long,
    input           b2_long,
    //neighbor POC
    input   [31:0]  a0_poc,  
    input   [31:0]  a1_poc,        
    input   [31:0]  b0_poc, 
    input   [31:0]  b1_poc, 
    input   [31:0]  b2_poc, 
    //col info (POC diff, intra, long)
    input   [ 7:0]  c0_pocdif,
    input           c0_intra,
    input           c0_long,
    input   [ 7:0]  c1_pocdif,
    input           c1_intra,
    input           c1_long
);
// local parameter

// register declaration

// wire declaration
    wire            is_scaleflag;
    wire            is_a0_unscale;
    wire			is_a1_unscale;
	wire			is_b0_unscale;
    wire			is_b1_unscale;
	wire			is_b2_unscale;
    wire			is_a0_scale;  
	wire			is_a1_scale;  
	wire			is_b0_scale; 
    wire			is_b1_scale;  
	wire			is_b2_scale;  
	wire			is_c0_unscale;
    wire            is_c1_unscale;
    wire            is_c0_scale;
    wire            is_c1_scale; 

// combination logic
generate
    if(AMVP_OR_MRG) begin : amvp_cand_con
        // spec 8.5.3.2.7
        assign  is_a0_unscale 	= a0_avail & ( (ref_poc == a0_poc) | (ref_long & a0_long) );
		assign	is_a1_unscale 	= a1_avail & ( (ref_poc == a1_poc) | (ref_long & a1_long) );
        assign	is_b0_unscale 	= b0_avail & ( (ref_poc == b0_poc) | (ref_long & b0_long) );
		assign	is_b1_unscale 	= b1_avail & ( (ref_poc == b1_poc) | (ref_long & b1_long) );
		assign	is_b2_unscale 	= b2_avail & ( (ref_poc == b2_poc) | (ref_long & b2_long) );

        if(MVP_SCALE_EN) begin: amvp_scale_en
            assign	is_scaleflag 	= a0_avail | a1_avail; // one of a1 cands is available
			assign	is_a0_scale 	= a0_avail & (ref_long == a0_long);
			assign	is_a1_scale 	= a1_avail & (ref_long == a1_long);
            assign	is_b0_scale 	= b0_avail & (ref_long == b0_long) & !is_scaleflag;
			assign	is_b1_scale 	= b1_avail & (ref_long == b1_long) & !is_scaleflag;
			assign	is_b2_scale 	= b2_avail & (ref_long == b2_long) & !is_scaleflag;
        end
        else begin: amvp_scale_dis
            assign	is_scaleflag 	= 0;
			assign	is_a0_scale 	= 0;
			assign	is_a1_scale 	= 0;
            assign	is_b0_scale 	= 0;
			assign	is_b1_scale 	= 0;
			assign	is_b2_scale 	= 0;
		end
    end
    else begin: merge_cand_con
        assign	is_a0_unscale 	= a0_avail;// & ( (ref_poc == a0_poc) | (ref_long & a0_long) );
		assign	is_a1_unscale 	= a1_avail;// & ( (ref_poc == a1_poc) | (ref_long & a1_long) );
		assign	is_b0_unscale 	= b0_avail;// & ( (ref_poc == b0_poc) | (ref_long & b0_long) );
        assign	is_b1_unscale 	= b1_avail;// & ( (ref_poc == b1_poc) | (ref_long & b1_long) );
		assign	is_b2_unscale 	= b2_avail;// & ( (ref_poc == b0_poc) | (ref_long & b2_long) );
    end
endgenerate

    assign  is_c0_unscale = reg_tmp_mvp_flag & c0_avail & !c0_intra & (ref_long == c0_long) & ( ref_long | (cur_pocdif == c0_pocdif) ); 
	assign	is_c1_unscale = reg_tmp_mvp_flag & c1_avail & !c1_intra & (ref_long == c1_long) & ( ref_long | (cur_pocdif == c1_pocdif) );

generate
    if(MVP_SCALE_EN) begin : col_scale_en
        assign  is_c0_scale	= reg_tmp_mvp_flag & c0_avail & !c0_intra & (ref_long == c0_long) & ( !ref_long & cur_pocdif != c0_pocdif );
		assign	is_c1_scale	= reg_tmp_mvp_flag & c1_avail & !c1_intra & (ref_long == c1_long) & ( !ref_long & cur_pocdif != c1_pocdif );
    end
    else begin : col_scale_dis
        assign  is_c0_scale = 0;
        assign  is_c1_scale = 0;
    end
endgenerate

generate
    if(AMVP_OR_MRG) begin : amvp_cand_one_hot
        assign	cand_a[0] = is_a0_unscale;
		assign	cand_a[1] = is_a1_unscale &   ~cand_a[0];
		assign	cand_a[2] = is_a0_scale   & (~|cand_a[1:0]);
		assign	cand_a[3] = is_a1_scale   & (~|cand_a[2:0]);

        assign	cand_b[0] = is_b0_unscale;
		assign	cand_b[1] = is_b1_unscale &   ~cand_b[0];
		assign	cand_b[2] = is_b2_unscale & (~|cand_b[1:0]);
		assign	cand_b[3] = is_b0_scale;
		assign	cand_b[4] = is_b1_scale   & (~|cand_b[3]);
		assign	cand_b[5] = is_b2_scale   & (~|cand_b[4:3]);
    end
    else begin : mrg_cand_one_hot
        assign	cand_a[1] = is_a1_unscale;
		assign	cand_b[1] = is_b1_unscale;
		assign	cand_b[0] = is_b0_unscale;
		assign	cand_a[0] = is_a0_unscale;
		assign	cand_b[2] = is_b2_unscale;
    end
endgenerate

        assign	cand_c[0] = is_c0_unscale;
		assign	cand_c[2] = is_c0_scale   &   ~cand_c[0];
		assign	cand_c[1] = is_c1_unscale & ( ~cand_c[0] & ~cand_c[2]);
		assign	cand_c[3] = is_c1_scale   & (~|cand_c[2:0]);

// function/task

// instantiation

// state machine

// sequence logic

endmodule
