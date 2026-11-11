# DUT review and ambiguity report: alu

## Extracted interface facts

```text
Module: alu
Ports (actual declarations):
  input  a: 32 bits packed_range=[31:0] type=logic
  input  b: 32 bits packed_range=[31:0] type=logic
  input  alu_op: 4 bits packed_range=[3:0] type=logic
  output y: 32 bits packed_range=[31:0] type=logic
  output zero: 1 bits type=logic
  output lt_signed: 1 bits type=logic
  output lt_unsigned: 1 bits type=logic
Do not infer protocol or behavior from port names or widths.
```

## Items requiring human review

- Confirm this is the intended top-level DUT and these are the exact ports and widths.
- Confirm the supplied specification (if any) is authoritative for intended behavior.
- Protocol/transaction acceptance rules are not inferred from port names or widths.
- Confirm clock edge and reset polarity/timing from the specification before using reset-dependent properties.
- Confirm latency, legal operations, and expected outputs are specified before generating behavioral checks.

## Specification status

A specification was supplied. The generator must cite its stated requirements and must not fill gaps with guessed behavior.

## Human confirmation

Review the items above. Type CONFIRM in the CLI only if the interface is correct and you approve generation using explicitly specified behavior only. Otherwise stop, correct the RTL/specification, and rerun.
