// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2025-2026 Dylan Thornburg and Bryce Kelly
//
// This file is part of the Open-Source ARM Cortex-M0 project.
// Licensed under the GNU General Public License v3.0 or later.
// See the LICENSE file at the root of this repository.
module arthALU (
    input  wire clk,
    input  wire [3:0] operation,// 0..F per decoder
    input  wire [31:0] d0, //data from rdn
    input  wire [31:0] d1, //data from rm
    input  wire update_flags, // for adds and subs type ops
    input  wire move,
    output reg [31:0] result,
    output reg N,
    output reg Z,
    output reg C,
    output reg V,
    output wire [3:0] flags_next
);

    wire [7:0] shamt;         // register shift amount is R[m]<7:0> (0..255)
    assign shamt = d1[7:0];

    reg [31:0] ALUResult;

    reg N_next, Z_next, C_next, V_next;

    assign flags_next = {N_next, Z_next, C_next, V_next};

    always @(posedge clk) begin
        ALUResult = 32'h0000;
        result <= ALUResult;
        N_next = 0;
        Z_next = 0;
        C_next = C;
        V_next = V;
        case (operation)

            4'h0: begin // AND
                ALUResult = d0 & d1;
                result <= ALUResult;
                N_next = ALUResult[31];
                Z_next = (ALUResult==32'b0);
            end

            4'h1: begin // EOR
                ALUResult = d0 ^ d1;
                result <= ALUResult;
                N_next = ALUResult[31];
                Z_next = (ALUResult==32'b0);
            end

            /* for all shifts, implement some change that allows for shifting without constant later IE LSL r4, r3 (r4 = r4 << r3) */
            4'h2: begin // LSL
                if (shamt == 0)       ALUResult = d0;                          // carry unchanged
                else if (shamt < 32)  begin ALUResult = d0 << shamt; C_next = d0[32 - shamt]; end
                else if (shamt == 32) begin ALUResult = 32'b0;       C_next = d0[0]; end
                else                  begin ALUResult = 32'b0;       C_next = 1'b0; end
                result <= ALUResult;
                N_next = ALUResult[31];
                Z_next = (ALUResult==32'b0);
            end


            4'h3: begin // LSR
                if (shamt == 0)       ALUResult = d0;                          // carry unchanged
                else if (shamt < 32)  begin ALUResult = d0 >> shamt; C_next = d0[shamt - 1]; end
                else if (shamt == 32) begin ALUResult = 32'b0;       C_next = d0[31]; end
                else                  begin ALUResult = 32'b0;       C_next = 1'b0; end
                result <= ALUResult;
                N_next = ALUResult[31];
                Z_next = (ALUResult==32'b0);
            end

            4'h4: begin // ASR
                if (shamt == 0)       ALUResult = d0;                          // carry unchanged
                else if (shamt < 32)  begin ALUResult = $signed(d0) >>> shamt; C_next = d0[shamt - 1]; end
                else                  begin ALUResult = {32{d0[31]}};          C_next = d0[31]; end
                result <= ALUResult;
                N_next = ALUResult[31];
                Z_next = (ALUResult==32'b0);
            end

            //start here tomorrow
            4'h5: begin // ADC
                {C_next, ALUResult} = {1'b0,d0} + {1'b0,d1} + {32'b0,C};
                result <= ALUResult;
                N_next = ALUResult[31];
                Z_next = (ALUResult==32'b0);
                V_next = ~(d0[31]^d1[31]) & (ALUResult[31]^d0[31]);
            end

            4'h6: begin // SBC  (d0 - d1 - ~C)
                {C_next, ALUResult} = {1'b0,d0} + {1'b0,~d1} + {32'b0,C};
                result <= ALUResult;
                N_next = ALUResult[31];
                Z_next = (ALUResult == 32'b0);
                V_next = (d0[31]^d1[31]) & (ALUResult[31]^d0[31]);
            end

            4'h7: begin // ROR  (rotate amount is modulo 32)
                if (shamt == 0)         ALUResult = d0;                        // carry unchanged
                else if (shamt[4:0]==0) begin ALUResult = d0;                                          C_next = d0[31]; end
                else begin
                    ALUResult = (d0 >> shamt[4:0]) | (d0 << (32 - shamt[4:0]));
                    C_next = ALUResult[31];
                end
                result <= ALUResult;
                N_next = ALUResult[31];
                Z_next = (ALUResult==32'b0);
            end

            4'h8: begin // TST output not saved. dont wb
                ALUResult = d0 & d1;
                result <= ALUResult;
                N_next = ALUResult[31];
                Z_next = (ALUResult==32'b0);
            end

            4'h9: begin // RSBS  normally rd = d1-d0 but thumb only negates d0 I guess
                {C_next, ALUResult} = {1'b0, ~d1} + 33'b1; //1 no borrow, 0 borrow
                result <= ALUResult;
                N_next = ALUResult[31];
                Z_next = (ALUResult==32'b0);
                V_next = (d1[31]) & ALUResult[31];
            end

            4'hA: begin // CMP  (d0 - d1)
                {C_next, ALUResult} = {1'b0,d0} + {1'b0,~d1} + 33'b1;
                result <= ALUResult;
                N_next = ALUResult[31];
                Z_next = (ALUResult == 32'b0) ? 1'b1 : 1'b0;
                V_next = (d0[31]^d1[31]) & (ALUResult[31]^d0[31]);
            end

            4'hB: begin // CMN  (d0 + d1)
                {C_next, ALUResult} = {1'b0,d0} + {1'b0,d1};
                C_next = move ? C : C_next;
                result <= ALUResult;
                N_next = ALUResult[31];
                Z_next = (ALUResult==32'b0);
                // MOVS: DDI0419E MOV(immediate)/MOV(register) -> APSR.V unchanged
                V_next = move ? V : (~(d0[31]^d1[31]) & (ALUResult[31]^d0[31]));
            end

            4'hC: begin // ORR
                ALUResult = d0 | d1;
                result <= ALUResult;
                N_next = ALUResult[31];
                Z_next = (ALUResult==32'b0);
            end

            4'hD: begin // MUL
                ALUResult = d0 * d1;
                result <= ALUResult;
                N_next = ALUResult[31];
                Z_next = (ALUResult==32'b0);
            end

            4'hE: begin // BIC
                ALUResult = d0 & (~d1);
                result <= ALUResult;
                N_next = ALUResult[31];
                Z_next = (ALUResult==32'b0);
            end

            4'hF: begin // MVN
                ALUResult = ~d1;
                result <= ALUResult;
                N_next = ALUResult[31];
                Z_next = (ALUResult==32'b0);
            end

            default: begin
                N_next = N;
                Z_next = Z;
                C_next = C;
                V_next = V;
            end
        endcase
    end

    always @(negedge clk) begin
        if (update_flags) begin
            N <= N_next;
            Z <= Z_next;
            C <= C_next;
            V <= V_next;
        end
    end

    // APSROut removed: arthALU exposes flags via N/Z/C/V outputs (no packed APSR port)

endmodule
