`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/23/2026 07:46:17 PM
// Design Name: 
// Module Name: Reverser
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


module Reverser(
    input clk,
    input reverse,
    input sign,
    input size,
    input [31:0] data_i,
    output reg [31:0] data_o
    );
    
    always @ (posedge clk) begin
        if (size) begin
            data_o[7:0] = data_i[31:24];
            data_o[15:8] = data_i[23:16];
            data_o[23:16] = data_i[15:8];
            data_o[31:24] = data_i[7:0];
        end
        else if(sign) begin
            data_o[7:0] = data_i[15:8];
            data_o[15:8] = data_i[7:0];
            data_o[23:16] = {8{data_i[7]}};
            data_o[31:24] = {8{data_i[7]}};
        end
        else begin
            data_o[7:0] = data_i[15:8];
            data_o[15:8] = data_i[7:0];
            data_o[23:16] = data_i[31:24];
            data_o[31:24] = data_i[23:16];
        end
    end
    
    
endmodule
