module	ve_irpu_expg_bits
#( 	
    parameter IN_BW = 10, // ===> set this only!!!
    parameter IN_MAX_ABS = 2**(IN_BW-1),
	parameter SIGN_INV = IN_MAX_ABS * 2 + 1,
	parameter MSB_POS = $clog2(SIGN_INV),
    parameter OUT_VAL = MSB_POS * 2 +1,
	parameter OUT_BW = $clog2(OUT_VAL) 
)
(
    output reg unsigned [7:0]	val_out,
    input signed	[IN_BW-1:0]		val_in
);
// local parameter



// register declaration



// wire declaration

wire	[IN_BW-1:0]		val_in_abs;
wire	[IN_BW  :0]		val_sign_inv;
wire	[OUT_BW-1:0]	val_bitcnt;

// combinational logic

assign	val_in_abs	= val_in[IN_BW-1] ? (-val_in) : val_in;
assign	val_sign_inv= {val_in_abs,(val_in[IN_BW-1] | val_in==0) };
assign	val_bitcnt	= val_bits(val_sign_inv);

always@(*) begin
	val_out = 0;
	val_out[0+:OUT_BW] = val_bitcnt;
end

// function/task

function [OUT_BW-1:0] val_bits;
input [IN_BW:0]	val_sign_inv;
integer 		i;
begin
	val_bits = 0;
    for(i=IN_BW ; i>=0 ; i=i-1 ) begin
		if(val_sign_inv[i]) begin
			val_bits = i*2+1;
			break;
		end	
	end
end
endfunction

// instantiation



// state machine


// sequence logic


endmodule
