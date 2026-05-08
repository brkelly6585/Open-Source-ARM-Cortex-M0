`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/26/2025 05:12:19 PM
// Design Name: 
// Module Name: IFID
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
module IFID(
    input clk,
    input IFID_EN,
    input IFID_consume,
    input IFID_wipe,
    input [31:0] PC_in, Instr_in,
    output reg consumed,
    output reg [31:0] PC_out, Instr_out
);
    parameter [15:0] NOP = 16'hBF00;
    always @(negedge clk) begin
        if (IFID_wipe) begin
            PC_out    <= 32'hFFFF;
            Instr_out <= {NOP, NOP};
            consumed  <= 1'b1;
        end else if (IFID_EN && (PC_in != PC_out)) begin
            PC_out    <= PC_in;
            Instr_out <= Instr_in;
            consumed  <= 1'b0;
        end else if (IFID_consume && !consumed) begin
            // Used to track when prefetch is fully consumed
            if (PC_out[1]) begin
                consumed <= 1'b1;
                Instr_out <= {NOP, NOP};
            end else if (IFID_EN) begin
                // If the buffer is enabled, but PC hasn't moved due to fetch,
                // Can still inc by 2 to process next half
                PC_out   <= PC_out + 32'd2;
                consumed <= 1'b0;
            end
        end else if (consumed) begin
            // Wait for new fetch
            Instr_out <= {NOP, NOP};
        end
    end
endmodule