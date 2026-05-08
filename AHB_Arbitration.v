`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/27/2026 04:18:38 AM
// Design Name: 
// Module Name: AHB_Arbitration
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


module AHB_Arbitration(
    input clk,
    input rst_n,
    
    input [31:0] if_PC_i, branch_addr_i,
    input if_read_req_i,
    input fetch, branch,
    output reg [31:0] if_data_o,
    output reg if_ready_o, if_stall_o,
    
    input [31:0] dm_addr_i,  dm_data_i,
    input dm_read_req_i, dm_write_req_i,
    input [1:0] dm_size_i,
    output reg [31:0] dm_data_o,
    output reg dm_ready_o,
    
    input [31:0] ahb_data_i,
    input ahb_ready_i,
    output reg [31:0] ahb_addr_o,
    output reg [1:0] ahb_size_o,
    output reg ahb_write_req_o, ahb_read_req_o,
    output [31:0] ahb_data_o,
    
    
    input  [31:0] exc_addr_i, exc_data_i,
    input  exc_read_req_i, exc_write_req_i,
    input  [1:0] exc_size_i,
    output reg exc_ready_o,
    output reg [31:0] exc_data_o
    );
    
    parameter [2:0] IDLE = 3'b000, DM = 3'b001, IF = 3'b010, EXC = 3'b011, BRANCH = 3'b100;
    reg [2:0] curr_state, next_state;
    
    reg data_phase_if_r, data_phase_dm_r, data_write_r, data_phase_exc_r, data_write_exc_r; 
    reg [31:0] if_data_held, if_addr_held, addr_bus;
    reg if_data_valid, bus_valid;
    
    wire [4:0] instr_check_local = if_PC_i[1] ? if_data_o[31:27] : if_data_o[15:11];
    wire is_32bit_local = (instr_check_local == 5'b11101) || (instr_check_local[4:1] == 4'b1111);
    
    always @ (posedge clk) begin
        if(!rst_n) begin
            curr_state <= IDLE;
            data_phase_if_r <= 1'b0;
            data_phase_dm_r <= 1'b0;
            data_write_r <= 1'b0;
            data_phase_exc_r <= 1'b0;
            data_write_exc_r <= 1'b0;
            if_data_held  <= 32'b0;
            if_addr_held <= 32'b0;
            if_data_valid <= 1'b0;
            if_stall_o <= 1'b0;
            addr_bus <= 32'b0;
            bus_valid <= 1'b0;
        end
        else begin
            curr_state <= next_state;
            data_phase_if_r <= (next_state == IF);
            data_phase_dm_r <= (next_state == DM);
            data_write_r <= dm_write_req_i & (next_state == DM);
            data_phase_exc_r <= (next_state == EXC);
            data_write_exc_r <= exc_write_req_i & (next_state == EXC);
            if_stall_o <= fetch && ~if_ready_o;
            
            if (next_state == IF || next_state == BRANCH) begin
                addr_bus <= ahb_addr_o;
                bus_valid <= 1'b1;
            end
            
            if (branch) begin
                if_data_valid <= 1'b0;
                if_addr_held  <= 32'b0;
            end
            else if ((curr_state == IF || curr_state == BRANCH) && ahb_ready_i && bus_valid) begin
                if_data_held  <= ahb_data_i;
                if_addr_held <= ahb_addr_o;
                if_data_valid <= 1'b1;
            end
            else if (({if_PC_i[31:2], 2'b00} != {if_addr_held[31:2], 2'b00}))
                if_data_valid <= 1'b0;
        end
    end
    
    always @(*)begin
        case (curr_state)
            IDLE: begin
                if(branch) next_state = BRANCH;
                else if (exc_read_req_i || exc_write_req_i)
                    next_state = EXC;
                else if(dm_read_req_i || dm_write_req_i)
                    next_state = DM;
                else if (if_read_req_i)
                    next_state = IF;
                else next_state = IDLE;
            end
            DM: begin
                if(branch) next_state = BRANCH;
                else if(ahb_ready_i) begin
                    if (exc_read_req_i || exc_write_req_i)
                        next_state = EXC;
                    else if(dm_read_req_i || dm_write_req_i)
                        next_state = DM;
                    else if (if_read_req_i)
                        next_state = IF;
                    else next_state = IDLE;
                end
            end
            IF: begin
                if(branch) next_state = BRANCH;
                else if(ahb_ready_i) begin
                    if (exc_read_req_i || exc_write_req_i)
                        next_state = EXC;
                    else if(dm_read_req_i || dm_write_req_i)
                        next_state = IDLE;
                    else if (if_read_req_i)
                        next_state = IF;
                    else next_state = IDLE;
                end
            end
            EXC: begin
                if(branch) next_state = BRANCH;
                else if(ahb_ready_i) begin
                    if (exc_read_req_i || exc_write_req_i)
                        next_state = EXC;
                    else if(dm_read_req_i || dm_write_req_i)
                        next_state = IDLE;
                    else if (if_read_req_i)
                        next_state = IF;
                    else next_state = IDLE;
                end
            end
            BRANCH: begin
                if (ahb_ready_i) begin
                    if (exc_read_req_i || exc_write_req_i)
                        next_state = EXC;
                    else if(dm_read_req_i || dm_write_req_i)
                        next_state = IDLE;
                    else if (if_read_req_i)
                        next_state = IDLE;
                    else next_state = IDLE;
                end
            end
            default: next_state = IDLE;
        endcase
    end
    assign ahb_data_o = (next_state == DM) ? dm_data_i : exc_data_i;
    always @(*) begin
        ahb_addr_o = 32'b0;
        ahb_size_o = 2'b10;
        ahb_write_req_o = 1'b0;
        ahb_read_req_o = 1'b0;
       
        
        case(next_state)
            IDLE: begin
                ahb_addr_o = dm_addr_i;
                ahb_size_o = dm_size_i;
                ahb_write_req_o = dm_write_req_i;
            end
            DM: begin
                ahb_addr_o = dm_addr_i;
                ahb_size_o = dm_size_i;
                ahb_write_req_o = dm_write_req_i;
                ahb_read_req_o = dm_read_req_i;
                
            end
            IF: begin
                ahb_addr_o = {if_PC_i[31:2]+(fetch|is_32bit_local), 2'b0};
                ahb_size_o = 2'b10;
                ahb_read_req_o = 1'b1;
            end
            EXC: begin
                ahb_addr_o = exc_addr_i;
                ahb_size_o = exc_size_i;
                ahb_write_req_o = exc_write_req_i;
                ahb_read_req_o = exc_read_req_i;
            end
            BRANCH: begin
                ahb_addr_o = {branch_addr_i[31:2], 2'b0};
                ahb_size_o = 2'b10;
                ahb_read_req_o =  1'b1;
            end
            default: ;
        endcase
    end
    wire held_matches = ({if_PC_i[31:2], 2'b00} == {if_addr_held[31:2], 2'b00});
    always @(*) begin
        dm_data_o = 32'b0;
        dm_ready_o = 1'b0;
        if_ready_o = 1'b0;
        if_data_o = 32'b0;
        exc_ready_o = 1'b0;
        exc_data_o = 32'b0;
  
        if(curr_state == IDLE && fetch)
            if_data_o = if_data_o;
        else
            if_data_o = 32'b0;
        
        if (ahb_ready_i) begin
            if(data_phase_exc_r) begin
                exc_ready_o = ahb_ready_i;
                if(~data_write_exc_r)
                    exc_data_o = ahb_data_i;
            end
            else if(data_phase_dm_r) begin
                dm_ready_o = ahb_ready_i;
                if(~data_write_r)
                    dm_data_o = ahb_data_i;
            end
            
            
        end
        
        if_data_o  = data_phase_if_r ? ahb_data_i : if_data_held;
        
        

        if_ready_o = ((data_phase_if_r & ahb_ready_i)
                      | (if_data_valid & held_matches & ~fetch))
                     & ~branch
                     & (curr_state != BRANCH);
        
        
        
    end
        
    
endmodule