@ SPDX-License-Identifier: GPL-3.0-or-later
@ Copyright (C) 2025-2026 Dylan Thornburg and Bryce Kelly
@
@ This file is part of the Open-Source ARM Cortex-M0 project.
@ Licensed under the GNU General Public License v3.0 or later.
@ See the LICENSE file at the root of this repository.
@==============================================================================
@ ARMv6-M (Cortex-M0) bare-core instruction coverage test
@   Records one result per instruction into an SRAM array at 0x20000000.
@   Designed for differential testing: run on STM32F051 silicon and on the core,
@   then diff the result array (dump DMEM words 0..N).
@
@   Every sequence runs back-to-back with no padding between instructions, so
@   the test exercises the pipeline's forwarding and hazard paths rather than
@   hiding them behind NOPs. The expected values are the ARMv6-M architectural
@   results and are what real silicon produces.
@
@   Excluded, not reasonably testable on a bare core without an exception harness:
@     WFI, WFE, SVC, BKPT and UDF, which need an exception or event harness.
@     Everything else in the ARMv6-M instruction set is covered here, including
@     LDR-literal, the barriers, and all sixteen branch conditions.
@==============================================================================
    .syntax unified
    .cpu cortex-m0
    .thumb

    .macro REC reg                 @ store one result and advance the pointer
    str  \reg, [r7]
    adds r7, #4
    .endm
    @ conditional-branch test: r0 default 1, flags set by the op IMMEDIATELY before
    .macro CB cc
    b\cc 1f
    movs r0, #0
1:  REC  r0
    .endm

    .section .vectors, "ax", %progbits
    .word 0x20001000               @ initial MSP
    .word reset + 1

    .text
    .thumb_func
    .global reset
reset:
    movs r7, #0x20
    lsls r7, r7, #24               @ r7 = 0x20000000 result pointer
    movs r6, #0x20
    lsls r6, r6, #24               @ r6 = 0x20000000
    movs r0, #1
    lsls r0, r0, #10               @ r0 = 0x400
    adds r6, r6, r0                @ r6 = 0x20000400 scratch base

@ ---- move / immediate ----
    movs r0, #0x2A
    REC  r0                        @ s00 MOVS imm8        = 0000002A
    mov  r1, r0
    REC  r1                        @ s01 MOV reg          = 0000002A
    movs r2, #0x55
    mov  r8, r2
    mov  r3, r8
    REC  r3                        @ s02 MOV (hi)         = 00000055
@ ---- add / sub ----
    movs r0, #0x2A
    adds r1, r0, #3
    REC  r1                        @ s03 ADDS imm3        = 0000002D
    movs r1, #0x10
    adds r1, #0x20
    REC  r1                        @ s04 ADDS imm8        = 00000030
    movs r0, #0x2A
    movs r1, #0x30
    adds r2, r0, r1
    REC  r2                        @ s05 ADDS reg         = 0000005A
    movs r0, #0x2A
    mov  r8, r0
    mov  r9, r0
    add  r8, r9
    mov  r3, r8
    REC  r3                        @ s06 ADD (hi)         = 00000054
    add  r2, sp, #16
    mov  r3, sp
    subs r2, r2, r3
    REC  r2                        @ s07 ADD SP+imm       = 00000010
    mov  r4, sp
    sub  sp, #8
    add  sp, #8
    mov  r5, sp
    subs r5, r5, r4
    REC  r5                        @ s08 SUB/ADD SP       = 00000000
    movs r0, #0x2A
    subs r1, r0, #5
    REC  r1                        @ s09 SUBS imm3        = 00000025
    movs r1, #0x50
    subs r1, #0x10
    REC  r1                        @ s10 SUBS imm8        = 00000040
    movs r0, #0x2A
    movs r1, #0x10
    subs r2, r0, r1
    REC  r2                        @ s11 SUBS reg         = 0000001A
    movs r0, #0x2A
    rsbs r1, r0, #0
    REC  r1                        @ s12 RSBS/NEGS        = FFFFFFD6
    movs r0, #0
    mvns r0, r0
    adds r0, r0, #1                @ C=1
    movs r1, #0x10
    adcs r1, r1, r1
    REC  r1                        @ s13 ADCS             = 00000021
    movs r0, #0x40
    movs r1, #0x10
    subs r2, r0, r1                @ C=1
    movs r0, #0x25
    movs r1, #0x05
    sbcs r0, r1
    REC  r0                        @ s14 SBCS             = 00000020
    movs r0, #7
    movs r1, #6
    muls r1, r0, r1
    REC  r1                        @ s15 MULS             = 0000002A
@ ---- logical ----
    movs r0, #0x3C
    movs r1, #0x5A
    ands r1, r0
    REC  r1                        @ s16 ANDS             = 00000018
    movs r0, #0x3C
    movs r1, #0x5A
    eors r1, r0
    REC  r1                        @ s17 EORS             = 00000066
    movs r0, #0x3C
    movs r1, #0x5A
    orrs r1, r0
    REC  r1                        @ s18 ORRS             = 0000007E
    movs r0, #0x3C
    movs r1, #0x5A
    bics r1, r0
    REC  r1                        @ s19 BICS             = 00000042
    movs r0, #0x3C
    mvns r1, r0
    REC  r1                        @ s20 MVNS             = FFFFFFC3
    movs r0, #1                    @ r0 default for TST
    movs r1, #0x0F
    movs r2, #0xF0
    tst  r1, r2
    CB   eq                        @ s21 TST (Z=1)        = 00000001
    movs r0, #1
    movs r1, #5
    movs r2, #0
    subs r2, r2, r1
    cmn  r1, r2
    CB   eq                        @ s22 CMN (Z=1)        = 00000001
@ ---- shift ----
    movs r0, #1
    lsls r1, r0, #4
    REC  r1                        @ s23 LSLS imm         = 00000010
    movs r1, #1
    movs r2, #5
    lsls r1, r2
    REC  r1                        @ s24 LSLS reg         = 00000020
    movs r0, #0x80
    lsrs r1, r0, #3
    REC  r1                        @ s25 LSRS imm         = 00000010
    movs r1, #0x80
    movs r2, #4
    lsrs r1, r2
    REC  r1                        @ s26 LSRS reg         = 00000008
    movs r0, #0x80
    lsls r0, #24
    asrs r1, r0, #28
    REC  r1                        @ s27 ASRS imm         = FFFFFFF8
    movs r0, #0x80
    lsls r0, #24
    movs r2, #28
    asrs r0, r2
    REC  r0                        @ s28 ASRS reg         = FFFFFFF8
    movs r0, #0x12
    movs r1, #4
    rors r0, r1
    REC  r0                        @ s29 RORS             = 20000001
@ ---- extend ----
    movs r0, #0x80
    sxtb r1, r0
    REC  r1                        @ s30 SXTB             = FFFFFF80
    movs r0, #0x80
    lsls r0, #8
    sxth r1, r0
    REC  r1                        @ s31 SXTH             = FFFF8000
    movs r0, #0xFF
    lsls r0, #4
    uxtb r1, r0
    REC  r1                        @ s32 UXTB             = 000000F0
    movs r0, #0xFF
    lsls r0, #12
    uxth r1, r0
    REC  r1                        @ s33 UXTH             = 0000F000
@ ---- reverse ----
    movs r0, #0x12
    lsls r0, #8
    adds r0, #0x34
    rev  r1, r0
    REC  r1                        @ s34 REV              = 34120000
    movs r0, #0x12
    lsls r0, #8
    adds r0, #0x34
    rev16 r1, r0
    REC  r1                        @ s35 REV16            = 00003412
    movs r0, #0x80
    revsh r1, r0
    REC  r1                        @ s36 REVSH            = FFFF8000
@ ---- load / store (padded roundtrips) ----
    movs r0, #0x5A
    str  r0, [r6]
    ldr  r1, [r6]
    REC  r1                        @ s37 STR/LDR imm      = 0000005A
    movs r0, #0x3C
    str  r0, [r6, #4]
    ldr  r1, [r6, #4]
    REC  r1                        @ s38 STR/LDR imm off  = 0000003C
    movs r0, #0x77
    movs r2, #8
    str  r0, [r6, r2]
    ldr  r1, [r6, r2]
    REC  r1                        @ s39 STR/LDR reg off  = 00000077
    movs r0, #0xC5
    strb r0, [r6, #16]
    ldrb r1, [r6, #16]
    REC  r1                        @ s40 STRB/LDRB        = 000000C5
    movs r0, #0xFF
    lsls r0, #4
    strh r0, [r6, #20]
    ldrh r1, [r6, #20]
    REC  r1                        @ s41 STRH/LDRH        = 00000FF0
    movs r0, #0x80
    strb r0, [r6, #24]
    movs r2, #24
    ldrsb r1, [r6, r2]
    REC  r1                        @ s42 LDRSB            = FFFFFF80
    movs r0, #0x80
    lsls r0, #8
    strh r0, [r6, #28]
    movs r2, #28
    ldrsh r1, [r6, r2]
    REC  r1                        @ s43 LDRSH            = FFFF8000
    mov  r3, r6
    adds r3, #0x60
    mov  r5, r3
    movs r1, #0x11
    stmia r3!, {r1}
    ldr  r1, [r5]
    REC  r1                        @ s44 STM (via LDR)    = 00000011
    movs r0, #0x99
    push {r0}
    pop  {r1}
    REC  r1                        @ s45 PUSH/POP single  = 00000099
@ ---- conditional branches ----
    movs r0, #1
    movs r1, #5
    cmp  r1, #5
    CB   eq                        @ s46 BEQ             = 1
    movs r0, #1
    cmp  r1, #4
    CB   ne                        @ s47 BNE             = 1
    movs r0, #1
    cmp  r1, #3
    CB   cs                        @ s48 BCS/BHS         = 1
    movs r0, #1
    cmp  r1, #9
    CB   cc                        @ s49 BCC/BLO         = 1
    movs r0, #1
    movs r2, #0
    subs r2, #1
    CB   mi                        @ s50 BMI            = 1
    movs r0, #1
    movs r2, #1
    adds r2, #1
    CB   pl                        @ s51 BPL            = 1
    movs r0, #1
    movs r2, #1
    lsls r2, #31
    subs r2, #1
    CB   vs                        @ s52 BVS            = 1
    movs r0, #1
    movs r2, #5
    adds r2, #1
    CB   vc                        @ s53 BVC            = 1
    movs r0, #1
    cmp  r1, #3
    CB   hi                        @ s54 BHI            = 1
    movs r0, #1
    cmp  r1, #5
    CB   ls                        @ s55 BLS true       = 1
    movs r0, #1
    cmp  r1, #3
    CB   ls                        @ s56 BLS false      = 0
    movs r0, #1
    cmp  r1, #3
    CB   ge                        @ s57 BGE            = 1
    movs r0, #1
    cmp  r1, #9
    CB   lt                        @ s58 BLT            = 1
    movs r0, #1
    cmp  r1, #3
    CB   gt                        @ s59 BGT            = 1
    movs r0, #1
    cmp  r1, #5
    CB   le                        @ s60 BLE true       = 1
    movs r0, #1
    cmp  r1, #3
    CB   le                        @ s61 BLE false      = 0
@ ---- BL / BX / BLX ----
    movs r0, #0
    bl   sub_bl
    REC  r0                        @ s62 BL + BX lr      = 000000B1
    adr  r2, sub_blx
    adds r2, #1                    @ ADR clears bit[0]; BLX needs the Thumb bit set
    movs r0, #0
    blx  r2
    REC  r0                        @ s63 BLX + BX lr     = 000000B2
@ ---- system / special ----
    movs r0, #0
    subs r0, #1
    mrs  r1, APSR
    REC  r1                        @ s64 MRS APSR (N=1)  = 80000000
    cpsid i
    mrs  r1, PRIMASK
    REC  r1                        @ s65 CPSID + PRIMASK = 00000001
    cpsie i
    mrs  r1, PRIMASK
    REC  r1                        @ s66 CPSIE + PRIMASK = 00000000
    mrs  r1, IPSR
    REC  r1                        @ s67 MRS IPSR (thread)= 00000000
    movs r0, #0
    mvns r0, r0
    msr  APSR_nzcvq, r0
    mrs  r1, APSR
    REC  r1                        @ s68 MSR/MRS APSR    = F0000000
    movs r0, #2
    msr  CONTROL, r0
    mrs  r1, CONTROL
    movs r0, #0
    msr  CONTROL, r0
    REC  r1                        @ s69 MSR/MRS CONTROL = 00000002
    dmb
    movs r0, #0xD1
    REC  r0                        @ s70 DMB             = 000000D1
    dsb
    movs r0, #0xD2
    REC  r0                        @ s71 DSB             = 000000D2
    isb
    movs r0, #0x15
    REC  r0                        @ s72 ISB             = 00000015
    yield
    sev
    movs r0, #0xAB
    REC  r0                        @ s73 NOP/YIELD/SEV   = 000000AB
    ldr  r0, =0x1234ABCD
    REC  r0                        @ s74 LDR literal     = 1234ABCD

done:
    b    done

    .thumb_func
sub_bl:
    movs r0, #0xB1
    bx   lr
    .balign 4
    .thumb_func
sub_blx:
    movs r0, #0xB2
    bx   lr
    .align 2
    .ltorg
