`timescale 1ns / 1ps
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2025-2026 Dylan Thornburg and Bryce Kelly
//
// This file is part of the Open-Source ARM Cortex-M0 project.
// Licensed under the GNU General Public License v3.0 or later.
// See the LICENSE file at the root of this repository.
//////////////////////////////////////////////////////////////////////////////////
// Create Date: 10/26/2025 04:46:56 PM
// Module Name: Instr_decode
//////////////////////////////////////////////////////////////////////////////////


module Instr_decode(
    input half,
    input [31:0] Instr,
    output reg [31:0] Instr_out,
    output reg [31:0] Imm,
    output reg [3:0] Rd, Rn, Rm, cond,
    output reg [3:0] ALU_op,
    output reg [1:0] size, type, barrier,
    output reg ALU_src, flags, memread, memwrite, regwrite, wd_src, branchC, move, sign, extend, reverse, sr,
    output reg cps,
    output reg svc,
    output reg bkpt,
    output reg [1:0] awpc,   // ALU-write-PC: 01=MOV PC,Rm  10=ADD PC,PC,Rm
    output reg udf
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
    wire [31:0] Instr32b;

    assign Instr16b = half ? Instr[31:16] : Instr[15:0];
    assign Instr32b = {Instr[15:0], Instr[31:16]};

    always @ (*) begin
        Instr_out = Instr16b;
        ALU_src = 1'b0;
        memread = 1'b0;
        memwrite = 1'b0;
        regwrite = 1'b0;
        wd_src = 1'b0;
        move = 1'b0;
        sign = 1'b0;
        extend = 1'b0;
        reverse = 1'b0;
        branchC = 1'b0;
        awpc = 2'b00;
        sr = 1'b0;
        ALU_op = 4'd0;
        flags = 1'b0;
        size = 2'b00;
        type = 2'b00;
        barrier = 2'b00;
        Rd = 0;
        Rn = 0;
        Rm = 0;
        cps = 0;
        svc = 0;
        bkpt = 0;
        udf = 0;
        Imm = 0;
        cond = 0;



        casex(Instr16b[15:10])
            6'b11101x: begin Instr_out = Instr32b; udf = 1'b1; end //32-bit: undefined in ARMv6-M
            6'b11110x: begin Instr_out = Instr32b;
                udf = 1'b1;                       // undefined unless a valid 32-bit encoding below
                casex(Instr32b[14:12])
                    3'b1x1: begin
                        udf = 1'b0;               // BL
                        branchC = 1'b1;
                        cond = 4'hE;
                        Imm = {{8{Instr32b[26]}}, ~(Instr32b[26]^Instr32b[13]), ~(Instr32b[26]^Instr32b[11]), Instr32b[25:16], Instr32b[10:0], 1'b0};
                        Rn = 4'hF;
                        Rd = 4'hE;
                        regwrite = 1'b1;
                    end
                    3'b0x0: begin
                        case(Instr32b[26:21])
                            6'b011101: begin
                                barrier = Instr32b[5:4];
                                udf = 1'b0;
                            end
                            6'b011100: begin //MSR
                                Rn = Instr32b[19:16];
                                sr = 1'b1;
                                Imm = Instr32b[7:0];
                                udf = 1'b0;
                            end
                            6'b011111:begin //MRS
                                Rd = Instr32b[11:8];
                                regwrite = 1'b1;
                                sr = 1'b1;
                                Imm = Instr32b[7:0];
                                udf = 1'b0;
                            end
                            default: ;            // udf stays 1
                        endcase
                    end
                endcase
            end //32 bit instr
            6'b11111x: begin Instr_out = Instr; udf = 1'b1; end //32-bit: undefined in ARMv6-M
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
                        Imm = Instr16b[10:6] == 5'b0 ? 6'd32 : Instr16b[10:6];
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
                        Imm = Instr16b[10:6] == 5'b0 ? 6'd32 : Instr16b[10:6];
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

                        case(Instr16b[12:11])
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
                        if (Rd == 4'hF) begin      // ADD PC,PC,Rm -> ALUWritePC (plain branch to PC+Rm)
                            awpc = 2'b10;
                            branchC = 1'b1;
                            regwrite = 1'b0;
                            flags = 1'b0;
                        end
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
                        ALU_src = 1'b0;
                        Imm = 32'd0;
                        move = 1'b1;
                        flags = 1'b0;
                        if (Rd == 4'hF) begin      // MOV PC,Rm -> ALUWritePC (plain branch to Rm)
                            awpc = 2'b01;
                            branchC = 1'b1;
                            regwrite = 1'b0;
                        end
                    end
                    4'b110x: begin // BX
                        regwrite = 1'b0;
                        flags = 1'b0;
                        branchC = 1'b1;
                        cond = 4'b1111;
                    end
                    4'b111x: begin // BLX  //// SET Rd = LR; Rn = PC; Imm = 1
                        ALU_op = SUB;
                        Rn = 4'hF;
                        Rd = 4'hE;
                        Imm = 1;
                        regwrite = 1'b1;
                        flags = 1'b0;
                        branchC = 1'b1;
                        cond = 4'b1111;
                    end
                endcase


            end
            6'b01001x: begin //LDR(literal)
                Rd = Instr16b[10:8];
                Rn = 4'hF; //PC
                Imm = {Instr16b[7:0], 2'b00};
                ALU_src = 1'b1;
                memread = 1'b1;
                memwrite = 1'b0;
                regwrite = 1'b1;
                wd_src = 1'b1;
                ALU_op = ADD;
                size = 2'b10; // LDR (literal) loads a word (was 2'b00 byte)
            end
            6'b0101xx: begin
                Rd = Instr16b[2:0];
                Rn = Instr16b[5:3];
                Rm = Instr16b[8:6];
                ALU_src = 1'b0;
                ALU_op = ADD;
                wd_src = 1'b1;
                move = 1'b0;
                size = 2'b00;
                sign = 1'b0;
                case(Instr16b[11:9])
                    3'd0: begin // STR (REG)
                        memread = 1'b0;
                        memwrite = 1'b1;
                        regwrite = 1'b0;
                        size = 2'b10;
                    end
                    3'd1: begin // STRH (REG)
                        memread = 1'b0;
                        memwrite = 1'b1;
                        regwrite = 1'b0;
                        size = 2'b01;
                    end
                    3'd2: begin // STRB (REG)
                        memread = 1'b0;
                        memwrite = 1'b1;
                        regwrite = 1'b0;
                        size = 2'b00;
                    end
                    3'd3: begin // LDRSB (REG)
                        memread = 1'b1;
                        memwrite = 1'b0;
                        regwrite = 1'b1;
                        size = 2'b00;
                        sign = 1'b1;
                    end
                    3'd4: begin // LDR (REG)
                        memread = 1'b1;
                        memwrite = 1'b0;
                        regwrite = 1'b1;
                        size = 2'b10;
                    end
                    3'd5: begin // LDRH (REG)
                        memread = 1'b1;
                        memwrite = 1'b0;
                        regwrite = 1'b1;
                        size = 2'b01;
                    end
                    3'd6: begin // LDRB (REG)
                        memread = 1'b1;
                        memwrite = 1'b0;
                        regwrite = 1'b1;
                        size = 2'b00;
                    end
                    3'd7: begin // LDRSH (REG)
                        memread = 1'b1;
                        memwrite = 1'b0;
                        regwrite = 1'b1;
                        size = 2'b01;
                        sign = 1'b1;
                    end
                endcase
            end
            6'b0110xx: begin
                Rd = Instr16b[2:0];
                Rn = Instr16b[5:3];
                Imm = {Instr16b[10:6], 2'b00};
                ALU_src = 1'b1;
                ALU_op = ADD;
                wd_src = 1'b1;
                move = 1'b0;
                size = 2'b00;
                if (Instr16b[11]) begin // LDR (IMM)
                    memread = 1'b1;
                    memwrite = 1'b0;
                    regwrite = 1'b1;
                    size = 2'b10;
                end else begin // STR (IMM)
                    memread = 1'b0;
                    memwrite = 1'b1;
                    regwrite = 1'b0;
                    size = 2'b10;
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
                size = 2'b00;
                if (Instr16b[11]) begin // LDRB (IMM)
                    memread = 1'b1;
                    memwrite = 1'b0;
                    regwrite = 1'b1;
                    size = 2'b00;
                end else begin // STRB (IMM)
                    memread = 1'b0;
                    memwrite = 1'b1;
                    regwrite = 1'b0;
                    size = 2'b00;
                end

            end
            6'b1000xx: begin //Load/store
                Rd = Instr16b[2:0];
                Rn = Instr16b[5:3];
                Imm = {Instr16b[10:6], 1'b0};
                ALU_src = 1'b1;
                ALU_op = ADD;
                wd_src = 1'b1;
                move = 1'b0;
                if (Instr16b[11]) begin // LDRH (IMM)
                    memread = 1'b1;
                    memwrite = 1'b0;
                    regwrite = 1'b1;
                    size = 2'b01;
                end else begin // STRH (IMM)
                    memread = 1'b0;
                    memwrite = 1'b1;
                    regwrite = 1'b0;
                    size = 2'b01;
                end
            end
            6'b1001xx: begin //Load/store (SP-relative)
                Rd = Instr16b[10:8];
                Rn = 4'hD;                     // base is SP (r13) - was missing (SP-relative STR/LDR bug)
                Imm = {Instr16b[7:0], 2'b00};
                ALU_src = 1'b1;
                ALU_op = ADD;
                wd_src = 1'b1;
                move = 1'b0;
                if (Instr16b[11]) begin // LDR (IMM)
                    memread = 1'b1;
                    memwrite = 1'b0;
                    regwrite = 1'b1;
                    size = 2'b10;
                end else begin // STR (IMM)
                    memread = 1'b0;
                    memwrite = 1'b1;
                    regwrite = 1'b0;
                    size = 2'b10;
                end
            end
            6'b1010xx: begin //ADR & ADD(SP +)
                Rd = Instr16b[10:8];
                Imm = {Instr16b[7:0], 2'b00};
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
                case(Instr16b[11:9])
                    3'b000: begin //ADD/SUB (SP plus IMM)
                        Rd = 4'hD;
                        Rn = 4'hD;
                        Imm = {Instr16b[6:0], 2'b00};
                        regwrite = 1'b1;
                        ALU_src = 1'b1;
                        ALU_op = Instr16b[7] ? SUB : ADD;
                    end
                    3'b001: begin //EXT
                        Rd = Instr16b[2:0];
                        Rm = Instr16b[5:3];
                        regwrite = 1'b1;
                        sign = ~Instr16b[7];
                        size[0] = ~Instr16b[6];
                        extend = 1'b1;
                    end
                    3'b010: begin //PUSH
                        Rn = 4'hD;
                        Rd = 4'hD;            // base = SP -> carried to EX for writeback
                        Imm = Instr16b[8:0];
                        memwrite = 1'b1;
                        size = 2'b10;
                        type = 2'b10;
                     end
                    3'b101: begin //REV
                        Rd = Instr16b[2:0];
                        Rm = Instr16b[5:3];
                        regwrite = 1'b1;
                        size[1] = ~Instr16b[6];
                        sign = Instr16b[7];
                        reverse = 1'b1;
                    end
                    3'b110: begin //POP
                        Rn = 4'hD;
                        Rd = 4'hD;            // base = SP -> carried to EX for writeback
                        Imm = Instr16b[8:0];
                        regwrite = 1'b1;
                        memread = 1'b1;
                        size = 2'b10;
                        type = 2'b10;
                    end
                    3'b011: begin //CPS (CPSIE/CPSID) - ARMv6-M writes PRIMASK from im
                        if (Instr16b[8:5] == 4'b0011 && Instr16b[3:0] == 4'b0010) begin
                            cps      = 1'b1;
                            sr       = 1'b1;                        // route through SR write
                            regwrite = 1'b0;                        // MSR-style write (mrs=0)
                            Imm      = {23'b0, Instr16b[4], 8'h10};  // im@[8], PRIMASK SYSm@[7:0]
                        end
                    end
                    3'b111: begin //BKPT (0xBE) / hints (0xBF)
                        if (Instr16b[8] == 1'b0) bkpt = 1'b1;      // BKPT -> HardFault; 0xBF hints are NOPs
                    end

                    default: begin
                        Imm = 0;
                    end
                endcase

            end
            6'b11000x: begin //Store mult
                Rn = {1'b0,Instr16b[10:8]};
                Rd = {1'b0,Instr16b[10:8]};   // base reg -> carried to EX for writeback
                Imm = Instr16b[7:0];
                memwrite = 1'b1;
                size = 2'b10;
                type = 2'b01;
            end
            6'b11001x: begin //Load Mult
                Rn = {1'b0,Instr16b[10:8]};
                Rd = {1'b0,Instr16b[10:8]};   // base reg -> carried to EX for writeback
                Imm = Instr16b[7:0];
                memread = 1'b1;
                regwrite = 1'b1;
                size = 2'b10;
                type = 2'b01;
            end
            6'b1101xx: begin //Branch
                move = 1'b0;
                if (Instr16b[11:9] != 3'b111) begin //B
                    Imm = {{23{Instr16b[7]}},Instr16b[7:0],1'b0};
                    cond = Instr16b[11:8];
                    branchC = 1'b1;
                end else begin //UDF and SVC
                    Imm = Instr16b[7:0];
                    if (Instr16b[8]) svc = 1'b1;   // SVC (0xDF)
                    else             udf = 1'b1;   // UDF (0xDE) -> undefined instruction -> HardFault
                end

            end
            6'b11100x: begin //Uncond branch
                Imm = {{20{Instr16b[10]}}, Instr16b[10:0],1'b0};
                cond = 4'he;
                branchC = 1'b1;
            end
            default: Instr_out = Instr16b;
        endcase
    end


endmodule
