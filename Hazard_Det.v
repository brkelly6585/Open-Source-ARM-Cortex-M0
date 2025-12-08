`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 12/01/2025 05:40:44 AM
// Design Name: 
// Module Name: Hazard_Det
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


module Hazard_Det(
    input clk,
    input [31:0] PC,
    input memread,
    input memwrite,
    output reg PC_EN,
    output reg IFID_EN,
    output reg IDEX_EN
    );
    
    
    always @ (PC, memread, memwrite, clk) begin
        if (~PC) begin
            PC_EN = 1;
            IFID_EN = 1;
            IDEX_EN = 1;

        end
        /*if ((memread | memwrite)) begin
            PC_EN <= ~PC_EN;
            IFID_EN <= ~IFID_EN;
            
        end*/
        else begin
            PC_EN = 1;
            IFID_EN = 1;
            IDEX_EN = 1;
        end
                
    end
    
    
endmodule
