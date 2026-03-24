`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02/09/2026 04:33:07 PM
// Design Name: 
// Module Name: M0_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module M0_top(

    );
    
    reg HCLK, HRESETn;
    
    wire ahb_ready, ahb_error;
    wire [31:0] ahb_rdata;
    
    wire ahb_read, ahb_write;
    wire [1:0] ahb_size;
    wire [31:0] ahb_addr, ahb_wdata;
    
    initial begin
        HCLK = 0;
        forever #5 HCLK = ~HCLK;
    end
    
    core core_dut(
                .HCLK(HCLK),
                .HRESETn(HRESETn),
                
                .rdata_i(ahb_rdata),
                .ready_i(ahb_ready),
                .error_i(ahb_error),
                
                .addr_o(ahb_addr),
                .wdata_o(ahb_wdata),
                .read_req_o(ahb_read),
                .write_req_o(ahb_write),
                .size_o(ahb_size)
              );
    
    ahb_top ahb(
                .HCLK(HCLK),
                .HRESETn(HRESETn),
                
                .addr_i(ahb_addr),
                .wdata_i(ahb_wdata),
                .read_req_i(ahb_read),
                .write_req_i(ahb_write),
                .size_i(ahb_size),
                
                .rdata_o(ahb_rdata),
                .ready_o(ahb_ready),
                .error_o(ahb_error)
               );
               
    initial begin
        HRESETn = 1'b0;
        #10
        HRESETn = 1'b1;
        #2000
        $finish;
    end
    
endmodule
