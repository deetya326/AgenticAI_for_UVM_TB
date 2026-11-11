# ALU example validation record

## Interface cross-check
Target RTL: `fixed_rtl/alu.sv`, module `alu`.

Expected extracted interface:
- input `a[31:0]`, input `b[31:0]`, input `alu_op[3:0]`
- output `y[31:0]`, output `zero`, output `lt_signed`, output `lt_unsigned`

Automated Python tests compare the parser's extracted port tuples against these exact declarations. This checks parser/interface consistency, not SV compilation.

## Behavioral relevance
- `alu_assertions.sv` maps each operation assertion to `alu_spec.md` operation encodings and the RTL behavior.
- The UVM scoreboard uses a reference function implementing the same operation table; this is an implementation-derived demo model and should be independently reviewed before making correctness claims.
- The monitor's covergroup samples operation class and zero/nonzero result, with a cross for basic scenario visibility.

## Tool limitation
This environment did not provide `vsim`, `iverilog`, or `verilator` on PATH during preparation. Therefore these SystemVerilog/UVM files are **not claimed to be compiled or simulated here**. Run them with your team's Questa/UVM installation and attach the real compile/simulation transcript. A plain iverilog install without UVM support is not sufficient to compile the UVM package.
