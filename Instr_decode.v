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
    input half,
    input [31:0] Instr,
    output reg [31:0] Instr_out,
    output reg [31:0] Imm,
    output reg [3:0] Rd, Rn, Rm,
    output reg [3:0] ALU_op,
    output reg ALU_src, flags, memread, memwrite, regwrite, wd_src, branchCond, branchX, move
    );
    
    //ALU_op parameters
    parameter   AND = 4'h0,
                EOR = 4'h1,
                LSL = 4'h2,
                LSR = 4'h3,
                ASR = 4'h4,
                ADC = 4'h5,
                SBC = 4'h6,
                ROR = 4'h7,
                TST = 4'h8,
                RSBS = 4'h9,
                CMP = 4'hA, SUB = 4'hA,
                CMN = 4'hB, ADD = 4'hB,
                ORR = 4'hC,
                MUL = 4'hD,
                BIC = 4'hE,
                MVN = 4'hF;
                
                
    
    wire [15:0] Instr16b;
    
    assign Instr16b = half ? Instr[31:16] : Instr[15:0];
    
    always @ (*) begin
        Instr_out = Instr16b;
        ALU_src = 1'b0;
        memread = 1'b0;
        memwrite = 1'b0;
        regwrite = 1'b0;
        wd_src = 1'b0;
        move = 1'b0;
        branchCond = 1'b0;
        branchX = 1'b0;
        ALU_op = 4'd0;
        flags = 1'b0;
        
        casex(Instr16b[15:10])
            6'b11101x: begin Instr_out = Instr; end //32 bit instr
            6'b11110x: begin Instr_out = Instr; end //32 bit instr
            6'b11111x: begin Instr_out = Instr; end //32 bit instr
            6'b00xxxx: begin //Shift add sub etc 
                casex(Instr16b[13:11])
                    3'b000: begin // LSL
                        Rd = Instr16b[2:0];
                        Rn = Instr16b[5:3];
                        Imm = Instr16b[10:6];
                        ALU_src = 1'b1;
                        memread = 1'b0;
                        memwrite = 1'b0;
                        regwrite = 1'b1;
                        wd_src = 1'b0;
                        move = 1'b0;
                        flags = 1'b1;
                        
                        ALU_op = LSL;
                        
                    end
                    3'b001: begin // LSR
                        Rd = Instr16b[2:0];
                        Rn = Instr16b[5:3];
                        Imm = Instr16b[10:6];
                        ALU_src = 1'b1;
                        memread = 1'b0;
                        memwrite = 1'b0;
                        regwrite = 1'b1;
                        wd_src = 1'b0;
                        move = 1'b0;
                        flags = 1'b1;
                        
                        ALU_op = LSR;
                    end
                    3'b010: begin // ASR
                        Rd = Instr16b[2:0];
                        Rn = Instr16b[5:3];
                        Imm = Instr16b[10:6];
                        ALU_src = 1'b1;
                        memread = 1'b0;
                        memwrite = 1'b0;
                        regwrite = 1'b1;
                        wd_src = 1'b0;
                        move = 1'b0;
                        flags = 1'b1;
                        
                        ALU_op = ASR;
                    end
                    3'b011: begin
                        Rm = Instr16b[8:6];
                        Imm = Instr16b[8:6];
                        Rd = Instr16b[2:0];
                        Rn = Instr16b[5:3];
                        memread = 1'b0;
                        memwrite = 1'b0;
                        regwrite = 1'b1;
                        wd_src = 1'b0;
                        move = 1'b0;
                        flags = 1'b1;
                        
                        ALU_src = Instr16b[10];
                        ALU_op = Instr16b[9] ? SUB : ADD;
                        
                        /*
                        case(Instr[10:9])
                            2'b00: begin //ADD (REG)
                                ALU_src = 1'b0;
                                ALU_op = ADD;
                            end
                            2'b01: begin //SUB (REG)
                                ALU_src = 1'b0;
                                ALU_op = SUB;
                            end
                            2'b10: begin //ADD (IMM)
                                ALU_src = 1'b1;
                                ALU_op = ADD;
                            end
                            2'b11: begin //SUB (IMM)
                                ALU_src = 1'b1;
                                ALU_op = SUB;
                            end
                        endcase
                        */
                        
                    end
                    
                    3'b1xx: begin
                        Rd = Instr16b[10:8];
                        Rn = Instr16b[10:8];
                        Imm = Instr16b[7:0];
                        ALU_src = 1'b1;
                        memread = 1'b0;
                        memwrite = 1'b0;
                        regwrite = 1'b1;
                        wd_src = 1'b0;
                        move = 1'b0;
                        flags = 1'b1;
                        
                        case(Instr[12:11])
                            2'b00: begin move = 1'b1; ALU_op = ADD;  end //MOV
                            2'b01: begin  ALU_op = SUB; regwrite = 1'b0; end
                            2'b10: begin ALU_op = ADD; end
                            2'b11: begin ALU_op = SUB; end
                        endcase
                        
                    end
                endcase
            end
            6'b010000: begin //Data Process
                Rm = Instr16b[5:3];
                Rd = Instr16b[2:0];
                Rn = Instr16b[2:0];
                Imm = 32'd0;
                ALU_src = 1'b0;
                memread = 1'b0;
                memwrite = 1'b0;
                regwrite = 1'b1;
                wd_src = 1'b0;
                move = 1'b0;
                flags = 1'b1;
                
                case(Instr16b[9:6])
                    4'h0: begin //AND
                        ALU_op = AND;
                    end
                    4'h1: begin //XOR
                        ALU_op = EOR;
                    end
                    4'h2: begin //LSL
                        ALU_op = LSL;
                    end
                    4'h3: begin //LSR
                        ALU_op = LSR;
                    end
                    4'h4: begin //ASR
                        ALU_op = ASR;
                    end
                    4'h5: begin //ADC
                        ALU_op = ADC;
                    end
                    4'h6: begin //SBC
                        ALU_op = SBC;
                    end
                    4'h7: begin //ROR
                        ALU_op = ROR;
                    end
                    4'h8: begin //TST
                        regwrite = 1'b0;
                        ALU_op = TST;
                    end
                    4'h9: begin //RSB
                        ALU_op = RSBS;
                    end
                    4'ha: begin //CMP
                        regwrite = 1'b0;
                        ALU_op = CMP;
                    end
                    4'hb: begin //CMN
                        regwrite = 1'b0;
                        ALU_op = CMN;
                    end
                    4'hc: begin //ORR
                        ALU_op = ORR;
                    end
                    4'hd: begin //MUL
                        ALU_op = MUL;
                    end
                    4'he: begin //BIC
                        ALU_op = BIC;
                    end
                    4'hf: begin //MVN
                        ALU_op = MVN;
                    end
                endcase
                
            end
            6'b010001: begin //Special Data Instruct
                Rm = Instr16b[6:3];
                Rd = {Instr16b[7],Instr16b[2:0]};
                Rn = {Instr16b[7],Instr16b[2:0]};
                ALU_src = 1'b0;
                memread = 1'b0;
                memwrite = 1'b0;
                regwrite = 1'b1;
                wd_src = 1'b0;
                move = 1'b0;
                flags = 1'b1;
                
                casex(Instr16b[9:6])
                    4'b00xx: begin // ADD REG
                        ALU_op = ADD;
                    end
                    4'b0100: begin // UNPREDICTABLE
                    
                    end
                    4'b0101: begin // CMP REG (T2) R0-R7
                        regwrite = 1'b0;
                        ALU_op = SUB;
                    end
                    4'b011x: begin // CMP REG (T2) not R0-R7 basically don't allow PC
                        regwrite = 1'b0;
                        ALU_op = SUB;
                    end
                    4'b10xx: begin // MOV REG
                        ALU_op = ADD;
                        ALU_src = 1'b1;
                        Imm = 32'd0;
                    end
                    4'b110x: begin // BX
                        regwrite = 1'b0;
                        flags = 1'b0;
                        branchX = 1'b1;
                    end
                    4'b111x: begin // BLX  //// SET Rd = LR; Rn = PC; Imm = 1 instr (Need to impl PC pass)
                        ALU_op = ADD;
                        Rn = 4'hF;
                        Rd = 4'hD;
                        Imm = 1;
                        regwrite = 1'b1;
                        flags = 1'b0;
                        branchX = 1'b1;
                    end
                endcase
                
            
            end
            6'b01001x: begin //LDR(literal)
                Rd = Instr16b[10:8];
                Rn = 4'hF; //PC
                Imm = Instr16b[7:0];
                ALU_src = 1'b1;
                memread = 1'b1;
                memwrite = 1'b0;
                regwrite = 1'b1;
                wd_src = 1'b1;
                ALU_op = ADD;
            end
            6'b0101xx: begin
                Rd = Instr16b[2:0];
                Rn = Instr16b[5:3];
                Rm = Instr16b[8:6];
                ALU_src = 1'b0;
                ALU_op = ADD;
                wd_src = 1'b1;
                move = 1'b0;
                case(Instr16b[11:9])
                    3'd0: begin // STR (REG)
                        memread = 1'b0;
                        memwrite = 1'b1;
                        regwrite = 1'b0;
                    end
                    3'd1: begin // STRH (REG)
                        memread = 1'b0;
                        memwrite = 1'b1;
                        regwrite = 1'b0;
                    end
                    3'd2: begin // STRB (REG)
                        memread = 1'b0;
                        memwrite = 1'b1;
                        regwrite = 1'b0;
                    end
                    3'd3: begin // LDRSB (REG)
                        memread = 1'b1;
                        memwrite = 1'b0;
                        regwrite = 1'b1;
                    end
                    3'd4: begin // LDR (REG)
                        memread = 1'b1;
                        memwrite = 1'b0;
                        regwrite = 1'b1;
                    end
                    3'd5: begin // LDRH (REG)
                        memread = 1'b1;
                        memwrite = 1'b0;
                        regwrite = 1'b1;
                    end
                    3'd6: begin // LDRB (REG)
                        memread = 1'b1;
                        memwrite = 1'b0;
                        regwrite = 1'b1;
                    end
                    3'd7: begin // LDRSH (REG)
                        memread = 1'b1;
                        memwrite = 1'b0;
                        regwrite = 1'b1;
                    end
                endcase
            end
            6'b0110xx: begin
                Rd = Instr16b[2:0];
                Rn = Instr16b[5:3];
                Imm = Instr16b[10:6];
                ALU_src = 1'b1;
                ALU_op = ADD;
                wd_src = 1'b1;
                move = 1'b0;
                if (Instr16b[11]) begin // LDR (IMM)
                    memread = 1'b1;
                    memwrite = 1'b0;
                    regwrite = 1'b1;
                end else begin // STR (IMM)
                    memread = 1'b0;
                    memwrite = 1'b1;
                    regwrite = 1'b0;
                end
            
            end
            6'b0111xx: begin
                Rd = Instr16b[2:0];
                Rn = Instr16b[5:3];
                Imm = Instr16b[10:6];
                ALU_src = 1'b1;
                ALU_op = ADD;
                wd_src = 1'b1;
                move = 1'b0;
                if (Instr16b[11]) begin // LDRB (IMM)
                    memread = 1'b1;
                    memwrite = 1'b0;
                    regwrite = 1'b1;
                end else begin // STRB (IMM)
                    memread = 1'b0;
                    memwrite = 1'b1;
                    regwrite = 1'b0;
                end
            
            end
            6'b1000xx: begin //Load/store
                Rd = Instr16b[2:0];
                Rn = Instr16b[5:3];
                Imm = Instr16b[10:6];
                ALU_src = 1'b1;
                ALU_op = ADD;
                wd_src = 1'b1;
                move = 1'b0;
                if (Instr16b[11]) begin // LDRH (IMM)
                    memread = 1'b1;
                    memwrite = 1'b0;
                    regwrite = 1'b1;
                end else begin // STRH (IMM)
                    memread = 1'b0;
                    memwrite = 1'b1;
                    regwrite = 1'b0;
                end
            end
            6'b1001xx: begin //Load/store
                Rd = Instr16b[10:8];
                Imm = Instr16b[7:0];
                ALU_src = 1'b1;
                ALU_op = ADD;
                wd_src = 1'b1;
                move = 1'b0;
                if (Instr16b[11]) begin // LDR (IMM)
                    memread = 1'b1;
                    memwrite = 1'b0;
                    regwrite = 1'b1;
                end else begin // STR (IMM)
                    memread = 1'b0;
                    memwrite = 1'b1;
                    regwrite = 1'b0;
                end
            end
            6'b1010xx: begin //ADR & ADD(SP +)
                Rd = Instr16b[10:8];
                Imm = Instr16b[7:0];
                move = 1'b0;
                ALU_src = 1'b1;
                wd_src = 1'b0;
                regwrite = 1'b1;
                memread = 1'b0;
                memwrite = 1'b0;
                ALU_op = ADD;
                flags = 1'b0;
                
                if (Instr16b[11]) Rn = 4'hD; //ADD (SP +)
                else Rn = 4'hF; //ADR
                
            end
            6'b1011xx: begin //Misc
            
            end
            6'b11000x: begin //Store mult
            
            end
            6'b11001x: begin //Load Mult
            
            end
            6'b1101xx: begin //Branch
                move = 1'b0;
                if (Instr[11:8] != 3'b111) begin //B
                    Imm = $signed(Instr16b[7:0]);
                    Rn = Instr16b[11:8];
                    branchCond = 1'b1;
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
