# Open-Source ARM Cortex-M0 (ARMv6-M) in Verilog

A from-scratch, open-source implementation of an ARMv6-M processor that is
cycle-accurate against real Cortex-M0 silicon. The RTL is plain Verilog-2005
with no vendor primitives in the core itself, so it simulates in any standard
tool and synthesizes on any FPGA.

This repository holds two projects that share the same processor RTL:

| Folder  | Purpose | Top module |
|---------|---------|------------|
| `sim/`   | Simulation. Runs the ARMv6-M instruction coverage test and self-checks the results. | `M0_top` |
| `synth/` | Synthesis. Runs CoreMark on hardware and shows the cycle count on a seven-segment display. | `M0_fpga_top` |

Every file the two projects have in common is byte-identical. The only
differences are the platform wrapper, the memory map (the FPGA build adds a
benchmark I/O peripheral), and the program image in memory.

---

## Quick start: simulation

The simulation project boots a bare-metal ARMv6-M program that exercises the
instruction set, writes one result per instruction into SRAM, then parks in a
spin loop. `M0_top` waits for the program to finish, compares all 75 results
against the architectural ARMv6-M values, and prints a verdict.

### Vivado (xsim)

1. Create a project for any part. The core has no vendor primitives, so the
   part choice does not matter for simulation.
2. Add every `.v` file in `sim/` as a **simulation source**.
3. Add `insn_coverage.hex` and `dmem.hex` to the project. Select each file and
   set **Type** to `Memory Initialization Files` in the Source File Properties
   panel. Without this, Vivado will not place them where `$readmemh` can find
   them and the core will fetch zeros.
4. Set `M0_top` as the simulation top.
5. Run Behavioral Simulation. Because the whole program has to execute, run for
   at least 500 us, or just let it run until it stops on its own. `M0_top` calls
   `$finish` as soon as the program is done.

Expected output in the Tcl console:

```
=== ARMv6-M instruction coverage ===
  PASS  75/75 results match ARMv6-M expectations
====================================
```

### Icarus Verilog

Run from inside `sim/` so the `$readmemh` paths resolve:

```
iverilog -g2005 -s M0_top -o m0_sim.vvp *.v
vvp m0_sim.vvp
```

The `$readmemh` "Not enough words in the file" notice is expected and harmless:
the test image is much smaller than the 64 KB flash array, so the rest stays
zero, exactly like unprogrammed flash.

### What the test covers

Every ARMv6-M instruction that can be exercised on a bare core: all data
processing, shifts, sign and zero extension, byte reversal, every addressing
mode of every load and store, multi-register transfers, PUSH and POP, BL, BLX,
BX, all sixteen branch conditions, the barriers, and the MRS/MSR special
register accesses. Only WFI, WFE, SVC, BKPT and UDF are left out, since they
need an exception or event harness to be meaningful.

The instructions run back to back with no padding between them, so the test
exercises the pipeline's forwarding and hazard logic rather than hiding it
behind NOPs. The expected values are the ARMv6-M architectural results, so the
same image and the same expectations apply to real silicon. They were checked
against an STM32F051R8T6.

---

## Quick start: synthesis

The synthesis project runs CoreMark from flash and reports the cycle count over
a memory-mapped benchmark peripheral, which the top level renders on the
seven-segment display.

### Board assumptions

The bundled `constraints.xdc` and `M0_fpga_top.v` target a **Digilent Nexys
A7-100T** (`xc7a100tcsg324-1`) with a 100 MHz oscillator. If you are on
different hardware, three things need attention. All of them are called out in
comments in the files themselves:

- **Pin assignments** in `constraints.xdc`. Every `PACKAGE_PIN` line is
  board-specific. Replace them with your own board's pins for `clk`, `rst`,
  `led`, `sw`, `seg`, `an` and `dp`. If your board has no seven-segment display,
  you can leave `seg`, `an` and `dp` unconnected and read the result over JTAG
  instead.
- **The oscillator frequency and the PLL ratios.** `create_clock` in the XDC
  describes your board's oscillator. The PLL parameters at the top of
  `M0_fpga_top.v` divide it down to the core clock. They default to
  100 MHz / 5 * 48 / 48 = 20 MHz. Keep the PLL's phase detector and VCO inside
  the legal range for your device and speed grade.
- **Reset polarity.** `rst` is treated as active-high, which suits the Nexys A7
  push button. Many boards have an active-low CPU reset instead. Invert it at
  the pin or flip the synchronizer polarity in `M0_fpga_top.v`.

The core clock is a free choice. Cycle counts do not depend on it, so lowering
it to close timing on a smaller or slower part costs nothing but wall-clock
speed.

### Vivado flow

1. Create an RTL project for your part.
2. Add every `.v` file in `synth/` as a **design source**, and `constraints.xdc`
   as a **constraint**.
3. Add `coremark_fpga_200_iterations.hex` and `dmem_blank.hex` to the project,
   and set **Type** to `Memory Initialization Files` for both. The first is the
   CoreMark image that ends up in the flash BRAM; the second is a blank SRAM
   image, present so data memory starts at a defined value.
4. Set `M0_fpga_top` as the top module.
5. Edit `constraints.xdc` for your board as described above.
6. Run Synthesis, then Implementation, then Generate Bitstream.

The design closes timing at 20 MHz on the Nexys A7-100T with Vivado's default
strategies. The reference build used **Synthesis: Flow_PerfOptimized_high** and
**Implementation: Performance_ExtraTimingOpt**, which leaves more margin.

### Reading the result

`sw[1:0]` selects what the display shows:

| `sw[1:0]` | Display |
|-----------|---------|
| `00` | Total cycles reported by CoreMark. This is the number to compare against silicon. |
| `01` | `crclist : crcmatrix`, expect `E714 : 1FD7` |
| `10` | `crcstate : crcfinal`, expect `8E3A : E714` |
| `11` | Live free-running cycle counter, which proves the core is executing |

The CRCs are CoreMark's own self-validation. If they match, the benchmark ran
correctly and the cycle count is meaningful.

At 20 MHz, 200 iterations take a little over 23 seconds. The LEDs follow the
instruction fetch address, so you can watch the core work.

---

## Rebuilding the test program

`sim/insn_coverage.s` and `sim/link.ld` build the coverage image with the GNU
Arm toolchain:

```
arm-none-eabi-as -mcpu=cortex-m0 -mthumb insn_coverage.s -o insn_coverage.o
arm-none-eabi-ld -T link.ld insn_coverage.o -o insn_coverage.elf
arm-none-eabi-objcopy -O binary insn_coverage.elf insn_coverage.bin
```

Then convert the binary to one 32-bit little-endian word per line, which is the
format `$readmemh` expects:

```
python3 -c "
import struct,sys
b=open('insn_coverage.bin','rb').read()
b+=b'\x00'*(-len(b)%4)
open('insn_coverage.hex','w').write(''.join('%08x\n'%w for (w,) in struct.iter_unpack('<I',b)))
"
```

If you add or remove tests, update `N_RESULTS` and the `expected` array in
`M0_top.v` to match.

---

## Memory map

Both projects place flash at address 0 and SRAM at `0x20000000`, matching an
STM32F051R8T6. The FPGA build adds one peripheral.

| Region | Size | Contents |
|--------|------|----------|
| `0x00000000` | 64 KB | Flash. Initialized from the program `.hex`. |
| `0x20000000` | 8 KB  | SRAM. |
| `0x40000000` | -     | Benchmark I/O. FPGA build only. |
| `0xE000E000` | -     | Private peripheral bus: SysTick, NVIC, SCB. |

---

## License

Copyright (C) 2025-2026 Dylan Thornburg and Bryce Kelly.

This project is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version.

This project is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this project. If not, see <https://www.gnu.org/licenses/>.

The full license text is in the `LICENSE` file at the root of this repository,
and every source file carries an SPDX identifier.

## Trademarks and independence

Arm and Cortex are trademarks of Arm Limited. This project is an independent
implementation of the publicly published ARMv6-M architecture. It contains no
Arm-licensed IP, and it is neither affiliated with nor endorsed by Arm Limited.
