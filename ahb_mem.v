`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01/25/2026
// Design Name: 
// Module Name: ahb_mem.v
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: Synchronous memory for AHB slave
// 
// Dependencies: None
// 
// Revision:
// Revision 0.02 - Modified to ensure read was truly synchronous and counteracts RAW hazard
// Additional Comments:
// 1024 words = 4KB
// 
//////////////////////////////////////////////////////////////////////////////////

module ahb_mem#(
    parameter INIT_FILE = ""
)(
    input HCLK,
    
    // Memory interface from ahb_slave
    input mem_write,
    input [31:0] mem_raddr,
    input [31:0] mem_waddr,
    input [31:0] mem_wdata,
    input [3:0] mem_byte_en,
    output [31:0] mem_rdata
);
    // MEMORY ARRAY (1024 words = 4KB)
    reg [31:0] mem [0:4095]; 

    // For addressing, ignore byte offset bits [1:0]
    wire [9:0] wr_word_addr = mem_waddr[11:2];
    reg [9:0] rd_word_addr;
    always @(negedge HCLK) rd_word_addr <= mem_raddr[11:2];
    
    initial if (INIT_FILE != "") $readmemh(INIT_FILE, mem);

    // WRITE OPERATION
    reg [7:0] wdata_byte0, wdata_byte1, wdata_byte2, wdata_byte3;
    reg wen0, wen1, wen2, wen3;
    
    always @(*) begin
        wdata_byte0 = mem_wdata[7:0];
        wdata_byte1 = mem_wdata[7:0];
        wdata_byte2 = mem_wdata[7:0];
        wdata_byte3 = mem_wdata[7:0];
        wen0 = 1'b0; 
        wen1 = 1'b0; 
        wen2 = 1'b0; 
        wen3 = 1'b0;
        if (mem_byte_en[0] & mem_byte_en[1] & mem_byte_en[2] & mem_byte_en[3]) begin
            wdata_byte0 = mem_wdata[7:0];
            wdata_byte1 = mem_wdata[15:8];
            wdata_byte2 = mem_wdata[23:16];
            wdata_byte3 = mem_wdata[31:24];
            wen0 = 1'b1; 
            wen1 = 1'b1; 
            wen2 = 1'b1; 
            wen3 = 1'b1;
        end
        else if ((mem_byte_en[0] & mem_byte_en[1]) & ~(mem_byte_en[2] & mem_byte_en[3])) begin
            wdata_byte0 = mem_wdata[7:0];
            wdata_byte1 = mem_wdata[15:8];
            wen0 = 1'b1; 
            wen1 = 1'b1;
        end
        else if (~(mem_byte_en[0] & mem_byte_en[1]) & (mem_byte_en[2] & mem_byte_en[3])) begin
            wdata_byte2 = mem_wdata[7:0];
            wdata_byte3 = mem_wdata[15:8];
            wen2 = 1'b1; 
            wen3 = 1'b1;
        end
        else if (mem_byte_en[0]) begin 
            wdata_byte0 = mem_wdata[7:0]; 
            wen0 = 1'b1; 
        end
        else if (mem_byte_en[1]) begin 
            wdata_byte1 = mem_wdata[7:0]; 
            wen1 = 1'b1; 
        end
        else if (mem_byte_en[2]) begin 
            wdata_byte2 = mem_wdata[7:0]; 
            wen2 = 1'b1; 
        end
        else if (mem_byte_en[3]) begin 
            wdata_byte3 = mem_wdata[7:0]; 
            wen3 = 1'b1; 
        end
    end

    always @(posedge HCLK) begin
        if (mem_write && wen0) mem[wr_word_addr][7:0] <= wdata_byte0;
        if (mem_write && wen1) mem[wr_word_addr][15:8] <= wdata_byte1;
        if (mem_write && wen2) mem[wr_word_addr][23:16] <= wdata_byte2;
        if (mem_write && wen3) mem[wr_word_addr][31:24] <= wdata_byte3;
    end

    // READ OPERATION + FORWARDING
    reg [31:0] mem_rdata_reg;
    always @(posedge HCLK) mem_rdata_reg <= mem[rd_word_addr];

    reg fwd, fwd_en0, fwd_en1, fwd_en2, fwd_en3;
    reg [7:0] fwd_byte0, fwd_byte1, fwd_byte2, fwd_byte3;
    always @(posedge HCLK) begin
        fwd <= mem_write && (wr_word_addr == rd_word_addr);
        fwd_en0 <= mem_write && wen0;
        fwd_en1 <= mem_write && wen1;
        fwd_en2 <= mem_write && wen2;
        fwd_en3 <= mem_write && wen3;
        fwd_byte0 <= wdata_byte0;
        fwd_byte1 <= wdata_byte1;
        fwd_byte2 <= wdata_byte2;
        fwd_byte3 <= wdata_byte3;
    end

    wire [7:0] out0 = (fwd && fwd_en0) ? fwd_byte0 : mem_rdata_reg[7:0];
    wire [7:0] out1 = (fwd && fwd_en1) ? fwd_byte1 : mem_rdata_reg[15:8];
    wire [7:0] out2 = (fwd && fwd_en2) ? fwd_byte2 : mem_rdata_reg[23:16];
    wire [7:0] out3 = (fwd && fwd_en3) ? fwd_byte3 : mem_rdata_reg[31:24];

    assign mem_rdata = {out3, out2, out1, out0};
endmodule
