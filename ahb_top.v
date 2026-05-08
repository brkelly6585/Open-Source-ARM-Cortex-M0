`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01/25/2026
// Design Name: 
// Module Name: ahb_top.v
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: AHB-Lite top level interconnect
//              
// 
// Dependencies: ahb_master, ahb_decoder, ahb_mux, ahb_slave, ahb_mem, ahb_default_slave
// 
// Revision:
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module ahb_top (
    input HCLK,
    input HRESETn,
    input [31:0] addr_i,
    input [31:0] wdata_i,
    input read_req_i,
    input write_req_i,
    input [1:0] size_i,
    output [31:0] rdata_o,
    output ready_o,
    output error_o
);
    wire [31:0] HADDR;
    wire [2:0] HBURST;
    wire HMASTLOCK;
    wire [3:0] HPROT;
    wire [2:0] HSIZE;
    wire [1:0] HTRANS;
    wire [31:0] HWDATA;
    wire HWRITE;
    wire [31:0] HRDATA;
    wire HREADY;
    wire HRESP;
    wire HSEL0;
    wire HSEL1;
    wire HSEL_DEFAULT;
    wire [31:0] HRDATA0;
    wire HREADYOUT0;
    wire HRESP0;
    wire mem0_write;
    wire [31:0] mem0_raddr;
    wire [31:0] mem0_waddr;
    wire [31:0] mem0_wdata;
    wire [31:0] mem0_rdata;
    wire [3:0] mem0_byte_en;
	
    wire [31:0] HRDATA1;
    wire HREADYOUT1;
    wire HRESP1;
    wire mem1_write;
    wire [31:0] mem1_raddr;
    wire [31:0] mem1_waddr;
    wire [31:0] mem1_wdata;
    wire [31:0] mem1_rdata;
    wire [3:0] mem1_byte_en;
	
	wire [31:0] HRDATA2;
    wire HREADYOUT2;
    wire HRESP2;
    wire mem2_write;
    wire [31:0] mem2_raddr;
    wire [31:0] mem2_waddr;
    wire [31:0] mem2_wdata;
    wire [31:0] mem2_rdata;
    wire [3:0] mem2_byte_en;
	
	wire [31:0] HRDATA3;
    wire HREADYOUT3;
    wire HRESP3;
    wire mem3_write;
    wire [31:0] mem3_raddr;
    wire [31:0] mem3_waddr;
    wire [31:0] mem3_wdata;
    wire [31:0] mem3_rdata;
    wire [3:0] mem3_byte_en;
	
    wire [31:0] HRDATA_DEFAULT;
    wire HREADYOUT_DEFAULT;
    wire HRESP_DEFAULT;

    ahb_main u_main (
        .HCLK(HCLK), 
        .HRESETn(HRESETn),
        .HRDATA(HRDATA), 
        .HREADY(HREADY), 
        .HRESP(HRESP),
        .HADDR(HADDR), 
        .HBURST(HBURST), 
        .HMASTLOCK(HMASTLOCK),
        .HPROT(HPROT), 
        .HSIZE(HSIZE), 
        .HTRANS(HTRANS),
        .HWDATA(HWDATA), 
        .HWRITE(HWRITE),
        .addr_i(addr_i), 
        .wdata_i(wdata_i),
        .read_req_i(read_req_i), 
        .write_req_i(write_req_i),
        .size_i(size_i), 
        .rdata_o(rdata_o),
        .ready_o(ready_o), 
        .error_o(error_o)
    );

    ahb_decoder u_decoder (
        .HADDR(HADDR),
        .HSEL0(HSEL0), 
        .HSEL1(HSEL1), 
		.HSEL2(HSEL2),
		.HSEL3(HSEL3),
        .HSEL_DEFAULT(HSEL_DEFAULT)
    );

    ahb_mux u_mux (
        .HCLK(HCLK), 
        .HRESETn(HRESETn), 
        .HTRANS(HTRANS),
        .HSEL0(HSEL0), 
        .HSEL1(HSEL1), 
		.HSEL2(HSEL2),
		.HSEL3(HSEL3),
        .HREADYOUT(HREADY),
		
        .HRDATA0(HRDATA0), 
        .HREADYOUT0(HREADYOUT0), 
        .HRESP0(HRESP0),
		
        .HRDATA1(HRDATA1), 
        .HREADYOUT1(HREADYOUT1), 
        .HRESP1(HRESP1),
		
		.HRDATA2(HRDATA2), 
        .HREADYOUT2(HREADYOUT2), 
        .HRESP2(HRESP2),
		
		.HRDATA3(HRDATA3), 
        .HREADYOUT3(HREADYOUT3), 
        .HRESP3(HRESP3),
		
        .HRDATA_DEFAULT(HRDATA_DEFAULT),
        .HREADYOUT_DEFAULT(HREADYOUT_DEFAULT),
        .HRESP_DEFAULT(HRESP_DEFAULT),
		
        .HRDATA(HRDATA), 
        .HREADY(HREADY), 
        .HRESP(HRESP)
    );

    ahb_second secondary0 (
        .HCLK(HCLK), 
        .HRESETn(HRESETn),
        .HSEL(HSEL0), 
        .HADDR(HADDR), 
        .HTRANS(HTRANS),
        .HWRITE(HWRITE), 
        .HSIZE(HSIZE), 
        .HWDATA(HWDATA), 
        .HREADY(HREADY),
        .HRDATA(HRDATA0), 
        .HREADYOUT(HREADYOUT0), 
        .HRESP(HRESP0),
        .mem_write(mem0_write),
        .mem_raddr(mem0_raddr),
        .mem_waddr(mem0_waddr),
        .mem_wdata(mem0_wdata),
        .mem_byte_en(mem0_byte_en),
        .mem_rdata(mem0_rdata)
    );

    ahb_mem#(.INIT_FILE("branch_test.hex")) IMEM (
        .HCLK(HCLK),
        .mem_write(mem0_write),
        .mem_raddr(mem0_raddr),
        .mem_waddr(mem0_waddr),
        .mem_wdata(mem0_wdata),
        .mem_byte_en(mem0_byte_en),
        .mem_rdata(mem0_rdata)
    );

    ahb_second secondary1 (
        .HCLK(HCLK), 
        .HRESETn(HRESETn),
        .HSEL(HSEL1), 
        .HADDR(HADDR), 
        .HTRANS(HTRANS),
        .HWRITE(HWRITE), 
        .HSIZE(HSIZE), 
        .HWDATA(HWDATA), 
        .HREADY(HREADY),
        .HRDATA(HRDATA1), 
        .HREADYOUT(HREADYOUT1), 
        .HRESP(HRESP1),
        .mem_write(mem1_write),
        .mem_raddr(mem1_raddr),
        .mem_waddr(mem1_waddr),
        .mem_wdata(mem1_wdata),
        .mem_byte_en(mem1_byte_en),
        .mem_rdata(mem1_rdata)
    );

    ahb_mem#(.INIT_FILE("dmem.hex")) DMEM (
        .HCLK(HCLK),
        .mem_write(mem1_write),
        .mem_raddr(mem1_raddr),
        .mem_waddr(mem1_waddr),
        .mem_wdata(mem1_wdata),
        .mem_byte_en(mem1_byte_en),
        .mem_rdata(mem1_rdata)
    );
	
	ahb_second secondary2 (
        .HCLK(HCLK), 
        .HRESETn(HRESETn),
        .HSEL(HSEL2), 
        .HADDR(HADDR), 
        .HTRANS(HTRANS),
        .HWRITE(HWRITE), 
        .HSIZE(HSIZE), 
        .HWDATA(HWDATA), 
        .HREADY(HREADY),
        .HRDATA(HRDATA2), 
        .HREADYOUT(HREADYOUT2), 
        .HRESP(HRESP2),
        .mem_write(mem2_write),
        .mem_raddr(mem2_raddr),
        .mem_waddr(mem2_waddr),
        .mem_wdata(mem2_wdata),
        .mem_byte_en(mem2_byte_en),
        .mem_rdata(mem2_rdata)
    );

    ahb_mem#(.INIT_FILE("dmem.hex")) D2MEM (
        .HCLK(HCLK),
        .mem_write(mem2_write),
        .mem_raddr(mem2_raddr),
        .mem_waddr(mem2_waddr),
        .mem_wdata(mem2_wdata),
        .mem_byte_en(mem2_byte_en),
        .mem_rdata(mem2_rdata)
    );
	
	ahb_second secondary3 (
        .HCLK(HCLK), 
        .HRESETn(HRESETn),
        .HSEL(HSEL3), 
        .HADDR(HADDR), 
        .HTRANS(HTRANS),
        .HWRITE(HWRITE), 
        .HSIZE(HSIZE), 
        .HWDATA(HWDATA), 
        .HREADY(HREADY),
        .HRDATA(HRDATA3), 
        .HREADYOUT(HREADYOUT3), 
        .HRESP(HRESP3),
        .mem_write(mem3_write),
        .mem_raddr(mem3_raddr),
        .mem_waddr(mem3_waddr),
        .mem_wdata(mem3_wdata),
        .mem_byte_en(mem3_byte_en),
        .mem_rdata(mem3_rdata)
    );

    ahb_mem#(.INIT_FILE("dmem.hex")) D3MEM (
        .HCLK(HCLK),
        .mem_write(mem3_write),
        .mem_raddr(mem3_raddr),
        .mem_waddr(mem3_waddr),
        .mem_wdata(mem3_wdata),
        .mem_byte_en(mem3_byte_en),
        .mem_rdata(mem3_rdata)
    );

    ahb_default_second u_default_secondary (
        .HCLK(HCLK), 
        .HRESETn(HRESETn),
        .HSEL(HSEL_DEFAULT), 
        .HTRANS(HTRANS), 
        .HREADY(HREADY),
        .HRDATA(HRDATA_DEFAULT),
        .HREADYOUT(HREADYOUT_DEFAULT),
        .HRESP(HRESP_DEFAULT)
    );
endmodule