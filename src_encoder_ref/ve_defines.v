// Video Encoder Define
`ifndef _VE_DEFINES_V_
    `define _VE_DEFINES_V_

    // Global REG struct
    `include "ve_reg_struct.v"

    // Global defines
    // Block Size
    `define BLK_4X4     0
    `define BLK_8X8     1
    `define BLK_16X16   2
    `define BLK_32X32   3
    `define BLK_64X64   4

    // Block Width
    `define BLK_W4      0
    `define BLK_W8      1
    `define BLK_W16     2
    `define BLK_W32     3
    `define BLK_W64     4

    // Block Height
    `define BLK_H4      0
    `define BLK_H8      1
    `define BLK_H16     2
    `define BLK_H32     3
    `define BLK_H64     4

    // Cache Set
    `define CL4_SET32X4     8'd0
    `define CL4_SET32X8     8'd1
    `define CL4_SET32X16    8'd2
    `define CL4_SET32X32    8'd3
    `define CL4_SET64X4     8'd4
    `define CL4_SET64X8     8'd5
    `define CL4_SET64X16    8'd6
    `define CL4_SET64X32    8'd7
    `define CL4_SET128X8    8'd8
    `define CL4_SET128X16   8'd9

    `define CL8_SET32X4     8'd16
    `define CL8_SET32X8     8'd17
    `define CL8_SET32X16    8'd18
    `define CL8_SET32X32    8'd19
    `define CL8_SET64X4     8'd20
    `define CL8_SET64X8     8'd21
    `define CL8_SET64X16    8'd22
    `define CL8_SET64X32    8'd23
    `define CL8_SET128X8    8'd24
    `define CL8_SET128X16   8'd25

    // FPGA
    `ifdef FPGA_SOURCE
        `define VC_FPGA_DBG_ENA
    `endif

`endif