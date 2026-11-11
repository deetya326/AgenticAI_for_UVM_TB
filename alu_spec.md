# ALU verification rules (reviewed against `fixed_rtl/alu.sv`)

Target: combinational module `alu`.

## Interface
- Inputs: `a[31:0]`, `b[31:0]`, `alu_op[3:0]`.
- Outputs: `y[31:0]`, `zero`, `lt_signed`, `lt_unsigned`.
- The RTL is combinational (`always_comb` and continuous assignments); no clock or reset ports exist.

## Operation encoding observed in RTL
- 0 ADD: `y = a + b` (32-bit result).
- 1 SUB: `y = a - b` (32-bit result).
- 2 AND, 3 OR, 4 XOR.
- 5 SLT: signed comparison result encoded as 32'd1 or 32'd0.
- 6 SLTU: unsigned comparison result encoded as 32'd1 or 32'd0.
- 7 SLL, 8 SRL, 9 SRA; shift amount is `b[4:0]`.
- 10–15/default: `y = 32'd0`.
- `zero = (y == 32'd0)`.
- `lt_signed = ($signed(a) < $signed(b))`.
- `lt_unsigned = (a < b)`.

These rules are an implementation-derived reference for this demonstration, not a claim that the full CPU/ISA is verified. A reviewer should confirm that using the RTL behavior as the reference is acceptable for the demo.
