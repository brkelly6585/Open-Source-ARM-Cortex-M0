`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/09/2026 03:12:03 PM
// Design Name: 
// Module Name: Barrier_Unit
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

//   type
// 00: No Barrier
// 01: DSB
// 10: DMB
// 11: ISB
module Barrier_Unit(
    input HCLK,
    input HRESETn,
    input [1:0] type,
    input ready_i,
    input write_ready,
    input write_buf,
    output reg stall,
    output reg flush
    );
    parameter [1:0] IDLE = 2'b00, CYCLE_1 = 2'b01, CYCLE_2 = 2'b10, WAIT =2'b11;
    reg [1:0] curr_state, next_state;
    reg [1:0] type_q;
    
    always @ (posedge HCLK) begin
        if(HRESETn) curr_state <= IDLE;
        else curr_state <= next_state;
        
        if(curr_state == IDLE && type != 2'b00)
            type_q <= type;
        
        if(curr_state == WAIT && next_state == IDLE)
            type_q <= 2'b00;
    end
    
    wire complete = 
                    (type == 2'b01) ? ~write_buf & ready_i :
                    (type == 2'b10) ? write_ready & ~write_buf & ready_i :
                    (type == 2'b11) ? 1'b1 : 1'b0;
                    
    always @(*) begin
        next_state = curr_state;
        
        case(curr_state)
            IDLE: if(|type) next_state = CYCLE_1;
            
            //M0 waits for 3 cycles all the time
            CYCLE_1: next_state = CYCLE_2;
            CYCLE_2: next_state = WAIT;
            
            WAIT: if (complete) next_state = IDLE;
            
            default: next_state = IDLE;
         endcase
    end
    
    always @(*) begin
        stall = 1'b0;
        flush = 1'b0;
        
        if(curr_state != IDLE) stall = 1'b1;
        
        if(curr_state == WAIT && complete && type == 2'b11) flush = 1'b1;
    end
    
    
endmodule
