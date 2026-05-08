`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01/19/2026
// Design Name: 
// Module Name: ahb_decoder.v
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: AHB-Lite address decoder module
// 
// Dependencies: None
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
// Memory Map (for now):
// 0x00000000 - 0x0FFFFFFF: Slave 0 (Instruction Memory)
// 0x10000000 - 0x1FFFFFFF: Slave 1 (Data Memory)
// All other addresses: Default Slave (Error)
//
//////////////////////////////////////////////////////////////////////////////////

module ahb_decoder (
    input [31:0] HADDR,
    
    // Slave selects
    output HSEL0,
    output HSEL1,
	output HSEL2,
	output HSEL3,
    output HSEL_DEFAULT
    
);

    // Top 4 bits select region (256MB per region)
    assign HSEL0 = (HADDR[31:28] == 4'h0); // Slave 0: 0x0xxxxxxx
    assign HSEL1 = (HADDR[31:28] == 4'h1);// Slave 1: 0x1xxxxxxx
	assign HSEL2 = (HADDR[31:28] == 4'h2); // Slave 2: 0x2xxxxxxx
    assign HSEL3 = (HADDR[31:28] == 4'h4);// Slave 3: 0x3xxxxxxx
    
    // Default: Everything else (update when adding more slave modules/peripherals)
    assign HSEL_DEFAULT = ~(HSEL0 | HSEL1 | HSEL2 | HSEL3);

endmodule