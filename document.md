# UVM/SVA Generation Agent — Steps & Prompts (Detailed)

This document walks through exactly what happens, in order, from unzipping
the kit to having generated UVM+SVA files in hand — and shows the *actual*
prompt text sent to the model at each step, rendered for the real DUT
(`rv32i_cpu.sv`) we're using.

---

## Step 0 — What's in the zip

```
uvm_sva_agent/
├── rtl_parser.py       # regex-based port/interface extractor
├── retriever.py        # RAG: keyword-overlap search over exemplars/
├── prompts.py          # builds the 2 prompts sent to the model
├── agent.py            # orchestrator — runs the whole pipeline
├── exemplars/          # 4 hand-written UVM/SVA reference patterns
│   ├── mem_bus.sv
│   ├── fsm_assertions.sv
│   ├── handshake.sv
│   └── register_file.sv
├── rv32i_cpu.sv        # target DUT
├── mini_cpu_top.sv, alu.sv, control_unit.sv,
│   dual_port_ram.sv, register_file.sv, tb_mini_cpu.sv   # rest of the CPU
├── DUT_README.md       # spec text for the CPU (use as spec.txt input)
├── README.md           # quickstart
├── TEAM_GUIDE.md        # shorter version of this document
└── ARCHITECTURE.md      # explains multi-agent/RAG/missing-layers questions
```

---

## Step 1 — Install dependencies

```bash
pip install requests --break-system-packages
```
Only dependency is `requests`, since `agent.py` calls OpenRouter's HTTP
API directly rather than using a provider SDK.

---

## Step 2 — Get an OpenRouter API key and export it

```bash
export OPENROUTER_API_KEY=sk-or-...
```
`agent.py` reads this from the environment; it exits with a clear message
if it's unset. Default model is `anthropic/claude-sonnet-4.6`; override
with `-m <slug>` (any model OpenRouter hosts) to compare outputs.

---

## Step 3 — Confirm the DUT and its interface

Target: `rv32i_cpu.sv`. Running `rtl_parser.py` on it directly shows what
the pipeline will see (this is exactly `Step 5`'s internal Step A too):

```bash
python3 rtl_parser.py rv32i_cpu.sv
```
Output:
```
Module: rv32i_cpu
  input   [1] clk
  input   [1] rst_n
  output  [32] pc
  output  [32] instr
  output  [32] data_addr
  output  [1] data_we
  output  [32] data_wdata
  input   [32] data_rdata
  output  [1] halted
```
Note: `instr` is declared an **output** here, but the same net is *also*
driven by `dual_port_ram.a_rdata` (also an output) in `mini_cpu_top.sv` —
a genuine two-driver conflict in the given RTL. Mention this in the demo
as a caught issue, not something to quietly fix.

---

## Step 4 — Prepare the spec text (optional but recommended)

The parser only reads `rv32i_cpu.sv`'s own port declarations — it does
not walk into `alu.sv`, `register_file.sv`, or `control_unit.sv`, so it
has no idea the FSM states are `ST_RESET`/`ST_RUN`/`ST_HALT`, or that x0
is hardwired to zero, or which opcodes exist. Feeding `DUT_README.md` in
as the spec file gives the model that context directly:

```bash
cp DUT_README.md spec.txt
```
(Or hand-write a shorter spec.txt with just the FSM states and the
instructions you most want assertions for — shorter specs mean faster,
cheaper calls.)

---

## Step 5 — Run the agent

```bash
python agent.py rv32i_cpu.sv spec.txt -o generated_output
```

Internally, in order:

**A. Parse.** `rtl_parser.py` extracts the port list shown in Step 3.

**B. Retrieve.** `retriever.py` tokenizes the interface block + spec text,
tokenizes each of the 4 exemplar files' tags + body, scores by shared
tokens, and returns the top 2. For this DUT + spec, that's
`register_file.sv` and `fsm_assertions.sv` (the CPU's spec text mentions
"register", "x0", and the RTL implies an FSM, so those score highest;
`mem_bus.sv` and `handshake.sv` score lower here — see `ARCHITECTURE.md`
for why keyword overlap sometimes under-ranks the most relevant exemplar).

**C. Build & send prompt #1 (UVM skeleton).** See the exact rendered text
in the **Prompts** section below.

**D. Split & write.** The response is split on `===FILE: ...===` /
`===ENDFILE===` markers into `generated_output/uvm_env/*.sv`. If the model
ignores the delimiters, everything lands in a single `RAW_OUTPUT.txt`
instead — that's the signal to re-run or tighten the prompt.

**E. Build & send prompt #2 (SVA).** Same interface + spec + exemplars,
different system prompt, asking for assertions instead of a testbench.

**F. Split & write.** Response written to
`generated_output/rv32i_cpu_assertions.sv`.

Two LLM calls total, run sequentially. Nothing loops, nothing checks the
output against the RTL after the fact — see `ARCHITECTURE.md` §4 for the
list of layers this does *not* have.

---

## Step 6 — Review the output

- Check all 7 expected UVM files exist:
  `rv32i_cpu_item.sv`, `_driver.sv`, `_monitor.sv`, `_sequencer.sv`,
  `_scoreboard.sv`, `_sequence.sv`, `_env.sv`.
- In the assertions file, check every property is tagged `[DERIVED]` or
  `[INFERRED]` — `[INFERRED]` means the model guessed at protocol/FSM
  behavior beyond what the interface/spec stated. Flag these for a human
  to confirm before trusting them.
- If a `RAW_OUTPUT.txt` shows up instead of split files, the model didn't
  follow the delimiter format — re-run, or shorten the spec text (very
  long prompts sometimes cause models to drop formatting instructions).

---

## Step 7 — If time remains

- Pipe the generated `.sv` files through `iverilog -g2012` for a syntax
  check (not currently wired in — see `ARCHITECTURE.md` §4).
- Try a second model with `-m` and diff the two outputs.
- Add a second exemplar-informed pass: feed the generated SVA back in as
  its own "exemplar" for a second DUT, to see if quality compounds.

---

# The Prompts, In Exact Order, As Actually Sent

These are the **real rendered prompts** for `rv32i_cpu.sv` with
`DUT_README.md` as the spec file — not templates, the literal text
`agent.py` sends over the wire for this DUT. If you change the DUT, spec,
or which exemplars retrieve, the interface block and exemplar block below
will change accordingly; the system prompts stay fixed.

## Call 1 of 2 — UVM skeleton generation

### System prompt

```
You are a UVM verification engineer. Given a DUT interface, generate a minimal but syntactically valid UVM testbench skeleton: transaction item, driver, monitor, sequencer, scoreboard, a basic sequence, and an env class that wires them together via a virtual interface. Use SystemVerilog UVM 1.2 style (uvm_component, uvm_sequence_item, `uvm_component_utils, etc). Infer a reasonable protocol (e.g. valid/ready, push/pop, read/write) from port names/widths if not stated. Keep it compact -- correctness and compilability matter more than completeness.

Output ONLY code, split into files using EXACTLY this delimiter format (no prose before/after):

===FILE: <filename>.sv===
<file content>
===ENDFILE===

Required files: rv32i_cpu_item.sv, rv32i_cpu_driver.sv, rv32i_cpu_monitor.sv, rv32i_cpu_sequencer.sv, rv32i_cpu_scoreboard.sv, rv32i_cpu_sequence.sv, rv32i_cpu_env.sv
```

### User prompt

````
DUT interface:
Module: rv32i_cpu
  input   [1] clk
  input   [1] rst_n
  output  [32] pc
  output  [32] instr
  output  [32] data_addr
  output  [1] data_we
  output  [32] data_wdata
  input   [32] data_rdata
  output  [1] halted

Additional spec / behavior notes (may be empty):
<full contents of DUT_README.md / spec.txt inserted here verbatim>

Reference patterns retrieved from a small exemplar library (adapt signal names to the actual DUT above -- do not copy verbatim, these are shape references, not the DUT's real interface):
--- Exemplar: register_file.sv (tags: register file, x0, immutable, write enable, read after write) ---
// Pattern: register-file invariants. Directly applicable if DUT has a
// hardwired-zero register (e.g. RISC-V x0) or any read-only location.

// 1) Hardwired-zero register never changes regardless of writes
property p_x0_immutable;
  @(posedge clk) disable iff (!rst_n)
    (rd_we && rd == 5'd0) |-> ##1 (rs1_rdata_for_x0 == '0);
endproperty
// NOTE: adapt signal names -- this checks that reads of the zero register
// stay zero even after a write is attempted to it. [INFERRED shape].

// 2) Write-then-read same cycle boundary: registered file returns new
// data only after the clock edge that commits the write (no same-cycle
// forwarding assumed unless DUT spec says otherwise).
property p_write_read_ordering;
  @(posedge clk) disable iff (!rst_n)
    (rd_we && rd != 5'd0) |-> ##1 (1'b1); // placeholder: bind to a read of `rd`
endproperty

--- Exemplar: fsm_assertions.sv (tags: fsm, state, reset, halt, invariant, illegal transition) ---
// Pattern: FSM invariant assertions for a small enumerated state register.
// [DERIVED]-style: legality of transitions must come from the actual FSM
// spec/RTL, not assumed -- this is a SHAPE to fill in, not literal states.

// 1) Reset forces known state
property p_reset_state;
  @(posedge clk) !rst_n |-> ##1 (state == ST_RESET);
endproperty
a_reset_state: assert property(p_reset_state);

// 2) No X/Z on state register after reset deasserts
property p_state_known;
  @(posedge clk) disable iff (!rst_n) !$isunknown(state);
endproperty
a_state_known: assert property(p_state_known);

// 3) Only enumerated transitions occur (illustrative -- adapt transition set)
property p_legal_transition;
  @(posedge clk) disable iff (!rst_n)
    (state == ST_HALT) |-> ##1 (state == ST_HALT); // halt is sticky
endproperty
a_legal_transition: assert property(p_legal_transition);

Generate the UVM skeleton now.
````

---

## Call 2 of 2 — SVA generation

### System prompt

```
You are a verification engineer writing SystemVerilog Assertions (SVA). Given a DUT interface, generate a focused assertion set covering: protocol/handshake correctness, FSM invariants (if a state machine is implied), boundary/corner cases (reset behavior, overflow/underflow, illegal state transitions). Each assertion must have a clear comment stating the property it checks and its correctness classification: mark each as [DERIVED] if it follows directly from the given ports/spec, or [INFERRED] if you assumed protocol behavior not explicitly stated. Assume a clock 'clk' and active-low or active-high reset matching the port names given (state your assumption in a comment if ambiguous).

Output ONLY code, in EXACTLY this format (no prose before/after):

===FILE: rv32i_cpu_assertions.sv===
<file content, wrapped in a bind-able module `rv32i_cpu_assertions` or a checker block>
===ENDFILE===
```

### User prompt

````
DUT interface:
Module: rv32i_cpu
  input   [1] clk
  input   [1] rst_n
  output  [32] pc
  output  [32] instr
  output  [32] data_addr
  output  [1] data_we
  output  [32] data_wdata
  input   [32] data_rdata
  output  [1] halted

Additional spec / behavior notes (may be empty):
<full contents of DUT_README.md / spec.txt inserted here verbatim>

Reference assertion/pattern shapes retrieved from a small exemplar library (adapt signal names to the actual DUT above -- do not copy verbatim):
--- Exemplar: register_file.sv (tags: register file, x0, immutable, write enable, read after write) ---
// Pattern: register-file invariants. Directly applicable if DUT has a
// hardwired-zero register (e.g. RISC-V x0) or any read-only location.

// 1) Hardwired-zero register never changes regardless of writes
property p_x0_immutable;
  @(posedge clk) disable iff (!rst_n)
    (rd_we && rd == 5'd0) |-> ##1 (rs1_rdata_for_x0 == '0);
endproperty
// NOTE: adapt signal names -- this checks that reads of the zero register
// stay zero even after a write is attempted to it. [INFERRED shape].

// 2) Write-then-read same cycle boundary: registered file returns new
// data only after the clock edge that commits the write (no same-cycle
// forwarding assumed unless DUT spec says otherwise).
property p_write_read_ordering;
  @(posedge clk) disable iff (!rst_n)
    (rd_we && rd != 5'd0) |-> ##1 (1'b1); // placeholder: bind to a read of `rd`
endproperty

--- Exemplar: fsm_assertions.sv (tags: fsm, state, reset, halt, invariant, illegal transition) ---
// Pattern: FSM invariant assertions for a small enumerated state register.
// [DERIVED]-style: legality of transitions must come from the actual FSM
// spec/RTL, not assumed -- this is a SHAPE to fill in, not literal states.

// 1) Reset forces known state
property p_reset_state;
  @(posedge clk) !rst_n |-> ##1 (state == ST_RESET);
endproperty
a_reset_state: assert property(p_reset_state);

// 2) No X/Z on state register after reset deasserts
property p_state_known;
  @(posedge clk) disable iff (!rst_n) !$isunknown(state);
endproperty
a_state_known: assert property(p_state_known);

// 3) Only enumerated transitions occur (illustrative -- adapt transition set)
property p_legal_transition;
  @(posedge clk) disable iff (!rst_n)
    (state == ST_HALT) |-> ##1 (state == ST_HALT); // halt is sticky
endproperty
a_legal_transition: assert property(p_legal_transition);

Generate the assertion set now.
````

---

## Why this exact structure

- **Delimiter format is strict** (`===FILE: x.sv===` / `===ENDFILE===`) so
  `agent.py` can split a single response into multiple files with one
  regex, no second LLM call needed just to reformat.
- **Required file list is spelled out explicitly** in the UVM system
  prompt (naming all 7 files by name) rather than left open-ended —
  models are much more reliable at producing a complete set when told
  exactly what's expected than when asked to "generate the usual UVM
  components."
- **Exemplars are explicitly marked "adapt, don't copy verbatim"** in
  both user prompts — without that instruction models tend to lift
  placeholder signal names (`data`, `valid`, `ready`) straight from the
  exemplar instead of mapping them onto the real DUT's actual port names.
- **The `[DERIVED]`/`[INFERRED]` tagging requirement** in the SVA system
  prompt exists so a human reviewer (or a judge) can immediately see
  which assertions are safe to trust versus which ones need a second
  look — this maps directly onto the project's stated success criterion
  of "reviewable and editable by a human engineer."
