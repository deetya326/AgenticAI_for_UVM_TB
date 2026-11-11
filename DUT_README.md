# Mini RV32I CPU — Hackathon DUT

This is a deliberately small RV32I-based CPU intended as a verification-agent DUT.

## Important architecture choice

RV32I means:
- 32-bit integer datapath
- 32 general-purpose registers, x0-x31
- x0 is hard-wired to zero
- 32-bit instructions

The core below implements a useful RV32I subset rather than the complete ISA.

## Modules

- `alu.sv` — integer ALU
- `register_file.sv` — 32 x 32-bit register file
- `dual_port_ram.sv` — dual-port 32-bit RAM
- `control_unit.sv` — opcode/control decoder + CPU state controls
- `rv32i_cpu.sv` — CPU datapath and PC/control
- `mini_cpu_top.sv` — integrated CPU + memory
- `tb_mini_cpu.sv` — simple self-checking demonstration

## Implemented instructions

### U-type
- LUI
- AUIPC

### J-type
- JAL
- JALR

### Branch
- BEQ
- BNE

### Loads
- LB
- LH
- LW
- LBU
- LHU

### Stores
- SB/SH/SW encodings are decoded as stores; the current memory datapath is
  word-oriented, so byte/halfword write masking is not yet implemented.

### Immediate ALU
- ADDI
- SLTI
- SLTIU
- XORI
- ORI
- ANDI
- SLLI
- SRLI
- SRAI

### Register ALU
- ADD
- SUB
- SLL
- SLT
- SLTU
- XOR
- SRL
- SRA
- OR
- AND

### Demo control instruction
- EBREAK is treated as HALT for this educational core.

## Memory

Port A:
- instruction fetch
- combinational read

Port B:
- data read
- synchronous write

This allows instruction fetch and data access through separate ports.

## Single-cycle interpretation

The datapath is single-cycle: an instruction's combinational work occurs while
the CPU is in `ST_RUN`, and register/PC state commits on the next rising edge.

The FSM is deliberately small:
- `ST_RESET`
- `ST_RUN`
- `ST_HALT`

It is not a multi-cycle FETCH/DECODE/EXECUTE FSM.

## Demo

The testbench loads a small program directly into the simulated RAM:

1. x1 = 5
2. x2 = 7
3. x3 = x1 + x2
4. MEM[0] = x3
5. x4 = MEM[0]
6. BEQ x3,x4 skips an instruction
7. EBREAK halts

Expected:
- x1 = 5
- x2 = 7
- x3 = 12
- x4 = 12
- x5 = 0
- MEM[0] = 12

## Hackathon note

For the verification-agent project, this DUT is intentionally rich enough to
generate:
- ALU properties
- register-file invariants
- reset properties
- FSM/state properties
- load/store checks
- branch checks
- PC sequencing checks
- x0 immutability checks
- illegal/unsupported instruction behavior

Do not call the whole CPU "verified" just because the demo test passes.
Use the testbench, assertions, mutation cases, and tool output as evidence.
