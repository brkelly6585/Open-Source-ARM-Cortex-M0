`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/26/2025 04:46:56 PM
// Design Name: 
// Module Name: Instr_decode
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


module Instr_decode(
    input clk, half,
    input [31:0] Instr,
    output reg [31:0] Instr_out,
    output reg [31:0] Imm,
    output reg [3:0] Rd, Rm, Rn
    );
    
    wire [15:0] Instr16b;
    
    assign Instr16b = half ? Instr[31:16] : Instr[15:0];
    
    always @ (posedge clk) begin
        Instr_out = Instr16b;
        casex(Instr[15:10])
            6'b11101x: begin Instr_out = Instr; end //32 bit instr
            6'b11110x: begin Instr_out = Instr; end //32 bit instr
            6'b11111x: begin Instr_out = Instr; end //32 bit instr
            6'b00xxxx: begin //Shift add sub etc 
                casex(Instr16b[13:11])
                    3'b000: begin
                        Rd = Instr16b[2:0];
                        Rn = Instr16b[5:3];
                        Imm = Instr16b[10:6];
                    end
                    3'b001: begin
                        Rd = Instr16b[2:0];
                        Rn = Instr16b[5:3];
                        Imm = Instr16b[10:6];
                    end
                    3'b010: begin
                        Rd = Instr16b[2:0];
                        Rn = Instr16b[5:3];
                        Imm = Instr16b[10:6];
                    end
                    3'b011: begin
                        Rm = Instr16b[8:6];
                        Imm = Instr16b[8:6];
                        Rd = Instr16b[5:3];
                        Rn = Instr16b[2:0];
                        /*
                        case(Instr[10:9])
                            2'b00: $display("ADD REG");
                            2'b01: $display("SUB REG");
                            2'b10: $display("ADD 3bIMM");
                            2'b11: $display("SUB 3bIMM");
                        endcase
                        */
                    end
                    3'b1xx: begin
                        Rd = Instr16b[10:8];
                        Rn = Instr16b[10:8];
                        Imm = Instr16b[7:0];
                        /*
                        case(Instr[12:11])
                            2'b00: $display("MOV IMM");
                            2'b01: $display("CMP IMM");
                            2'b10: $display("ADD 8bIMM");
                            2'b11: $display("SUB 8bIMM");
                        endcase
                        */
                    end
                endcase
            end
            6'b010000: begin //Data Process
                Rm = Instr16b[5:3];
                Rd = Instr16b[2:0];
                Rn = Instr16b[2:0];
                /* //These are the instructions in this category by code; may be useful for control
                case(Instr16b[9:6])
                    4'h0: begin //AND
                        
                    end
                    4'h1: begin //XOR
                    
                    end
                    4'h2: begin //LSL
                    
                    end
                    4'h3: begin //LSR
                    
                    end
                    4'h4: begin //ASR
                    
                    end
                    4'h5: begin //ADC
                    
                    end
                    4'h6: begin //SBC
                    
                    end
                    4'h7: begin //ROR
                    
                    end
                    4'h8: begin //TST
                    
                    end
                    4'h9: begin //RSB
                    
                    end
                    4'ha: begin //CMP
                    
                    end
                    4'hb: begin //CMN
                    
                    end
                    4'hc: begin //ORR
                    
                    end
                    4'hd: begin //MUL
                    
                    end
                    4'he: begin //BIC
                    
                    end
                    4'hf: begin //MVN
                    
                    end
                endcase
                */
            end
            6'b010001: begin //Special Data Instruct
                Rm = Instr16b[6:3];
                Rd = {Instr16b[7],Instr16b[2:0]};
                Rn = {Instr16b[7],Instr16b[2:0]};
                /*
                casex(Instr16b[9:6])
                    2'b00xx: // ADD REG
                    2'b0100: // UNPREDICTABLE
                    2'b0101: // CMP REG (T2)
                    2'b011x: // CMP REG (T2)
                    2'b10xx: // MOV REG
                    2'b110x: // BX
                    2'b111x: // BLX
                endcase
                */
            
            end
            6'b01001x: begin //LDR(literal)
                Rd = Instr16b[10:8];
                Imm = Instr16b[7:0];
            end
            6'b0101xx: begin
            
            end
            6'b011xxx: begin
            
            end
            6'b100xxx: begin //Load/store
            
            end
            6'b1010xx: begin //ADR & ADD(SP +)
                Rd = Instr16b[10:8];
                Imm = Instr16b[7:0];
                /*
                if (Instr16b[11]); //ADD (SP +)
                else ; //ADR
                */
            end
            6'b1011xx: begin //Misc
            
            end
            6'b11000x: begin //Store mult
            
            end
            6'b11001x: begin //Load Mult
            
            end
            6'b1101xx: begin //Branch
                if (Instr[11:8] != 3'b111) begin //B
                    Imm = Instr16b[7:0];
                    Rn = Instr16b[11:8];
                end else begin //UDF and SVC
                    Imm = Instr16b[7:0];
                end
            
            end
            6'b11100x: begin //Uncond branch
                Imm = Instr16b[10:0];
            end
            default: Instr_out = Instr16b;
        endcase
    end
    
    
endmodule
