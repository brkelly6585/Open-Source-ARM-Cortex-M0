`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/04/2026 05:32:26 AM
// Design Name: 
// Module Name: Special_Register_File
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


module Special_Register_File(
    input HCLK, HRESETn,
    
    input flags_EX,
    input [3:0] flags,
    
    input sr_op,
    input mrs,             // 1=MRS(read), 0=MSR(write)
    input ipsr_we, apsr_we,
    input [3:0] apsr_data,
    input [5:0] ipsr_data,
    input [7:0] SYSm,
    input [31:0] wdata,
    output reg [31:0] rdata_o,
    output [31:0] APSR_o,
    output PRIMASK_o,
    output [5:0] IPSR_o
);
   
    reg [4:0]  APSR_flags;   // N,Z,C,V,Q - bits [31:27]
    reg PRIMASK;
    reg [1:0] CONTROL;      // [1]=SPSEL, [0]=nPRIV
    reg [5:0] IPSR;

    assign APSR_o = {APSR_flags, 27'b0};
    assign PRIMASK_o = PRIMASK;
    assign IPSR_o = IPSR;

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            APSR_flags <= 5'b0;
            PRIMASK <= 1'b0;
            CONTROL <= 2'b0;
            IPSR <= 6'b0;
        end else if (sr_op && !mrs) begin 
            case (SYSm[7:3])
                5'b00000: begin
                    case (SYSm[2:0])
                    3'b000: APSR_flags <= wdata[31:27];
                    endcase
                end
                5'b00010: begin
                    case (SYSm[2:0])
                        3'b000: PRIMASK <= wdata[0];
                        3'b100: CONTROL <= wdata[1:0];
                        
                    endcase
                end
                
                default: ;
            endcase
        end
        if(ipsr_we) IPSR <= ipsr_data;
        if(apsr_we) APSR_flags[4:1] <= apsr_data;
    end
    
    // Flag bypass from ALU
    always @ (negedge HCLK)
        if (flags_EX)
            APSR_flags[4:1] = flags;

    always @(*) begin
        rdata_o = 32'b0;
        if (sr_op && mrs) begin
            case (SYSm[7:3])
                5'b00000: begin
                    if (!SYSm[2]) rdata_o[31:27] = APSR_flags;
                    if (SYSm[0]) rdata_o[8:0] = {3'b0, IPSR};
                end
                5'b00010: begin
                    case (SYSm[2:0])
                        3'b000: rdata_o[0] = PRIMASK;
                        3'b100: rdata_o[1:0] = CONTROL;
                    endcase
                end
                default: ;
            endcase
        end
    end
endmodule
