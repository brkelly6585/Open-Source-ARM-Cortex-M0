`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 12/01/2025 10:14:31 AM
// Design Name: 
// Module Name: Branch_Unit
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


module Branch_Unit(
    input branch,
    input [3:0] cond,
    input [31:0] PC,
    input [31:0] imm,
    input [31:0] Rm,
    input N,
    input Z,
    input C,
    input V,
    output reg branch_EX,
    output [31:0] PC_Branch,
    output exc_out
    );
    
    assign PC_Branch = &cond ? Rm : (PC+imm);
    
    //If we are ever at FFFFFFFx then its an excep call
    assign exc_out = &cond ? (Rm[31:4] == 28'hFFFFFFF) : 1'b0;
    
    always @ (*) begin
        branch_EX = 0;
        if (!PC[31:1]) branch_EX = 0;
        if(exc_out) branch_EX = 0;
        else if (branch) begin
        case(cond)
            4'h0:   if(Z==1) branch_EX = 1;
            4'h1:   if(Z==0) branch_EX = 1;
            4'h2:   if(C==1) branch_EX = 1;
            4'h3:   if(C==0) branch_EX = 1;
            4'h4:   if(N==1) branch_EX = 1;
            4'h5:   if(N==0) branch_EX = 1;
            4'h6:   if(V==1) branch_EX = 1;
            4'h7:   if(V==0) branch_EX = 1;
            4'h8:   if(C==1 && Z==0) branch_EX = 1;
            4'h9:   if(C==0 && Z==1) branch_EX = 1;
            4'ha:   if(N==V) branch_EX = 1;
            4'hb:   if(N!=V) branch_EX = 1;
            4'hc:   if(Z==0 && N==V) branch_EX = 1;
            4'hd:   if(Z==1 && N!=V) branch_EX = 1;
            4'he:   branch_EX = 1;
            4'hf:   branch_EX = 1;
            default: branch_EX = 0;
         endcase
         end else branch_EX = 0;
    end
    

endmodule
