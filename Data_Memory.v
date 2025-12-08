`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/13/2025 06:06:41 PM
// Design Name: 
// Module Name: Data_Memory
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


module Data_Memory(
    input clk,
    input re,
    input we,
    input [31:0] addr,
    input [31:0] data_in,
    output reg [31:0] data_out
    );
    
    
    
    reg [31:0] data [4095:0];
    
    
    //Use for prefilled data
    initial begin
        data[1] = 3;
    end
    
    always @ (negedge clk) begin
        if(we)
           data[addr[11:0]] = data_in;
    end
    
    always @ (posedge clk) begin
        if(re)
            data_out = data[addr[11:0]];
    end
    
endmodule
