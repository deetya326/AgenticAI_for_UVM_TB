# The Mini RV32I CPU, the Verification Environment, and the AI Agent — Explained

This covers three things end to end: what the DUT (the RTL) actually does,
what a UVM+SVA verification environment is and how it maps onto this DUT,
and how the AI agent pipeline generates that environment automatically.

---

# Part 1 — The RTL (the DUT)

## 1.1 The module hierarchy

```
mini_cpu_top                 (top-level: CPU + memory wired together)
├── dual_port_ram             (instruction + data memory, one block, two ports)
└── rv32i_cpu                 (the CPU itself)
    ├── register_file         (32 x 32-bit registers)
    ├── control_unit           (decodes instr -> control signals)
    └── alu                    (arithmetic/logic unit)
```

`tb_mini_cpu.sv` is a hand-written, non-UVM testbench that instantiates
`mini_cpu_top`, loads a tiny hard-coded program directly into RAM, and
checks final register values with `$fatal` on mismatch. It's useful as a
sanity check and as a second data point on expected behavior, but it is
not what the AI agent generates — the agent builds a UVM environment
instead (Part 2).

## 1.2 What kind of CPU this is

A **single-cycle RV32I subset**. "Single-cycle" means each instruction's
entire combinational computation (decode, register read, ALU op, memory
address calc) happens within one clock period, and all state (PC,
registers, memory) commits together on the next rising edge. There's no
pipelining and no multi-cycle fetch/decode/execute — that's a deliberate
simplification for a hackathon DUT, not a hidden feature to look for.

**Implemented per `DUT_README.md`:**
U-type (LUI, AUIPC), J-type (JAL, JALR), branches (BEQ, BNE), loads (LB,
LH, LW, LBU, LHU), stores (opcodes decoded, but per the README, "byte/
halfword write masking is not yet implemented" — the memory datapath is
word-oriented), immediate ALU ops (ADDI/SLTI/SLTIU/XORI/ORI/ANDI/SLLI/
SRLI/SRAI), register-register ALU ops (ADD/SUB/SLL/SLT/SLTU/XOR/SRL/SRA/
OR/AND), and EBREAK repurposed as a HALT signal for the demo.

## 1.3 Walking through each module

### `alu.sv`
Pure combinational. Takes two 32-bit operands (`a`, `b`) and a 4-bit
`alu_op` selecting one of 10 operations (ADD, SUB, AND, OR, XOR, SLT,
SLTU, SLL, SRL, SRA — see the `localparam` list at the top). Outputs the
result `y`, plus `zero` (`y == 0`), `lt_signed`, `lt_unsigned` — though
note `rv32i_cpu.sv` instantiates the ALU with `.lt_signed()` and
`.lt_unsigned()` left **unconnected** (empty parens), so branch/compare
decisions in the CPU currently go through `y`/subtraction, not through
these two outputs. Worth an assertion checking the ALU's own math is
correct in isolation (this is a good self-contained SVA target — no CPU
state needed, just combinational input/output checking).

### `register_file.sv`
32 registers, `regs[0:31]`, each 32 bits. Two combinational read ports
(`rs1_rdata`, `rs2_rdata`) and one synchronous write port (`rd_we` +
`rd_wdata` on `rd`, committed on `posedge clk`). Two invariants are
explicit in the code and are exactly what an SVA suite should check
directly:
- **x0 is hardwired to zero** — reads of `rs1==0` or `rs2==0` always
  return `32'd0` regardless of what's stored (line: `(rs1 == 5'd0) ?
  32'd0 : regs[rs1]`).
- **x0 can never be written** — the write guard is `rd_we && (rd !=
  5'd0)`; a write targeting `rd == 0` is silently dropped.
- On reset (`!rst_n`), every register is zeroed.

### `control_unit.sv`
Pure combinational decoder. Takes the raw `instr` and the CPU's `state`,
and produces every control signal the datapath needs (`reg_write`,
`mem_write`, `alu_op`, `branch`, `jump`, `halt`, etc.) via a big `case`
on `opcode` (and nested cases on `funct3`/`funct7` for the ALU op
variants). Two things worth noting precisely:
- **Nothing is decoded outside `ST_RUN`.** The entire decode logic is
  gated by `if (state == ST_RUN)`; in `ST_RESET` or `ST_HALT` every
  control signal defaults to its safe/off value (all the defaults are
  set at the top of the `always_comb` block before the `case`).
- **EBREAK detection is narrow and specific**: `OP_SYSTEM` (opcode
  `1110011`) sets `halt` only when `funct3 == 3'b000 AND instr[31:20] ==
  12'h001` — i.e. it only recognizes the exact EBREAK encoding, not any
  SYSTEM-opcode instruction.
- Any opcode not in the case list falls to `default: /* no side effects
  */` — an illegal/unimplemented instruction is silently a no-op, not an
  error or a trap. That's a good assertion target: "illegal opcode →
  `reg_write`/`mem_write`/`branch`/`jump` all stay low."

### `dual_port_ram.sv`
One memory array (`mem[0:DEPTH-1]`, `DEPTH` defaults to 256 words),
accessed through two independent ports:
- **Port A** (instruction fetch): combinational read only —
  `assign a_rdata = mem[a_index];` — no write capability on this port.
- **Port B** (data access): combinational read (`b_rdata`) *and*
  synchronous write (`if (b_we) mem[b_index] <= b_wdata;` on
  `posedge clk`).

Both ports index into the **same underlying array**, so a data-side store
to an address that overlaps with a currently-fetched instruction address
is a real, checkable interaction (self-modifying-code-style hazard) —
another good assertion/testbench scenario, and one a hand-written test is
unlikely to think to cover but an assertion phrased generically ("if
`b_we` writes to `a_index` on the same cycle as a fetch...") would catch.

### `rv32i_cpu.sv`
The datapath. In order:
1. **Instruction field extraction** — `opcode`, `rd`, `rs1`, `rs2`,
   `funct3`, `funct7` are all `assign`-sliced directly out of `instr`.
2. **Immediate generation** — five separate immediate formats (I/S/B/U/J)
   are computed combinationally every cycle from the raw instruction bits
   (sign-extension patterns match the standard RISC-V immediate encodings).
3. **Register file access** — reads `rs1_data`/`rs2_data` every cycle;
   write path (`reg_write`, `reg_wdata`) comes from the writeback mux.
4. **Control unit** — produces every control signal from `instr` +
   `state`.
5. **ALU** — `alu_a` is `pc` for AUIPC (opcode `7'b0010111`) and
   `rs1_data` otherwise; `alu_b` is `imm_i` when `alu_src_imm` else
   `rs2_data`.
6. **Data memory interface** — `data_addr = alu_y` (i.e. every load/store
   address is just "ALU result"), `data_we = mem_write`, `data_wdata =
   rs2_data` (always the second source register, regardless of store
   width).
7. **Load formatting** — a `case` on `load_funct3` sign/zero-extends the
   raw `data_rdata` for LB/LH/LW/LBU/LHU.
8. **Writeback mux** — decides what goes into `reg_wdata`: load data, PC+4
   (for JAL/JALR), the U-immediate (for LUI), or the raw ALU result.
   **Note:** this mux is written **twice** as two separate `always_comb`
   blocks, both driving `reg_wdata`. The second block is a strict
   superset of the first (it adds the AUIPC case then repeats every other
   condition) — in simulation, the second block's assignment is what
   actually takes effect since it's the last one evaluated for that
   variable, making the first block dead code. This is very likely
   leftover/duplicated code rather than an intentional design choice —
   worth flagging to the team, and worth an assertion that checks the
   *actual* behavior (AUIPC → `reg_wdata == pc + imm_u`) rather than
   assuming the first block's logic ever runs.
9. **Next-PC logic** — default `pc+4`; branch-taken → `pc+imm_b`; JAL →
   `pc+imm_j`; JALR → `(rs1_data + imm_i) & ~1` (the standard RISC-V
   "clear bit 0" rule for JALR targets).
10. **FSM** — three states, `ST_RESET → ST_RUN → ST_HALT`, `ST_HALT` is
    sticky (never leaves once entered). PC only advances while
    `state == ST_RUN && !halt_cmd`.
11. **`halted` output** — simply `(state == ST_HALT)`.

**The most important finding to flag to your team:** `instr` is declared
as an **output** port of `rv32i_cpu` (`output logic [31:0] instr`), but
nowhere inside `rv32i_cpu.sv` is `instr` ever assigned — it's only *read*
(`opcode = instr[6:0]`, etc.). In `mini_cpu_top.sv`, this same `instr` net
is *also* driven by `dual_port_ram`'s `a_rdata` output (the actual
fetched instruction). That means the port direction on `rv32i_cpu.instr`
looks backwards — it reads like it should be declared `input`, since the
CPU is supposed to *receive* the fetched instruction from memory, not
produce it. I flagged this as a "multi-driver conflict" earlier; the more
precise description is: **`rv32i_cpu`'s `instr` output is permanently
undriven inside the module, and that undriven port then contends with
the RAM's driving of the same wire in the parent module.** I'm not
certain how your simulator resolves that contention (behavior can be
tool-dependent), so verify this by actually running `tb_mini_cpu.sv` —
if it passes as-is, the tool is likely tolerant of it or resolving it in
a way I haven't traced; if it doesn't, this port direction is your first
real bug to fix, not a hypothetical one.

## 1.4 The instruction-level story (what actually happens end to end)

1. `pc` addresses RAM port A → `instr` arrives (assuming the direction
   issue above doesn't actually break it — see note above).
2. `control_unit` decodes `instr` (only while `state == ST_RUN`) into
   every control signal.
3. `register_file` supplies `rs1_data`/`rs2_data` combinationally.
4. `alu` computes based on `alu_a`/`alu_b`/`alu_op`.
5. For loads/stores, `alu_y` becomes `data_addr`; RAM port B does the
   actual read or write.
6. The writeback mux picks what goes back into the register file.
7. Next-PC logic decides the next fetch address (sequential, branch, or
   jump).
8. On the next `posedge clk`, `state`, `pc`, the register file, and
   memory (if written) all commit simultaneously.

---

# Part 2 — The Verification Environment (UVM + SVA), Explained From Scratch

## 2.1 Why verification is separate from the RTL

The RTL above defines what the CPU *should* do. Verification is a
completely separate piece of code whose only job is to prove — through
directed stimulus, randomized stimulus, and always-on checks — that the
RTL actually does what it's supposed to, including in corner cases nobody
thought to hand-write a test for. `tb_mini_cpu.sv` is a minimal, one-shot
version of this (one hard-coded program, a handful of `$fatal` checks).
UVM + SVA is the industrial-strength version of the same idea, structured
so it can be reused, extended, and randomized systematically.

## 2.2 The UVM components, one at a time, mapped onto this CPU

UVM (Universal Verification Methodology) is a SystemVerilog class library
and a set of conventions for structuring a testbench as reusable,
composable pieces instead of one big monolithic test file. Each piece has
one job:

- **Transaction / sequence item** — a class describing *one unit of
  stimulus or observed activity*. For this CPU, a natural transaction is
  "one memory-bus event": address, write-enable, write-data (and,
  separately, "one instruction-fetch event": address + fetched
  instruction). It's just a data container — no behavior beyond holding
  fields and maybe a `randomize()` constraint.

- **Sequence** — generates a stream of transactions according to some
  strategy: directed (a specific program, like `tb_mini_cpu.sv`'s
  hand-loaded instructions), randomized (random valid instruction
  encodings), or a mix. A sequence doesn't touch the DUT directly — it
  hands transactions to a sequencer.

- **Sequencer** — a queue/arbiter that takes transactions from one or
  more sequences and hands them to the driver, one at a time, in order.
  For a single-driver environment like this it's mostly plumbing.

- **Driver** — converts a transaction into actual pin wiggling on the
  DUT's interface. For this CPU, since instruction fetch happens through
  the RAM (not through a stimulus signal the driver directly controls),
  the more natural driver job is on the **data-memory side**: driving
  `data_addr`/`data_we`/`data_wdata` scenarios if you're testing the
  memory interface in isolation, or preloading instruction memory content
  before releasing reset if you're testing whole-CPU behavior the way
  `tb_mini_cpu.sv` does manually.

- **Monitor** — the read-only counterpart to the driver: watches DUT
  pins every cycle (without driving anything) and reconstructs
  transactions from what it observes, then broadcasts them over an
  **analysis port** for anything else (scoreboard, coverage collector) to
  consume. For this CPU: a monitor watching `pc`/`instr` reconstructs
  "what instruction executed when"; a monitor watching
  `data_addr`/`data_we`/`data_wdata`/`data_rdata` reconstructs every
  memory access.

- **Scoreboard** — the actual pass/fail brain. Takes what the monitor(s)
  observed and compares it against an independent reference/expected
  result (a software model of the CPU, or — more simply for this small
  core — expected register/memory values computed from the known
  program, the same way `tb_mini_cpu.sv`'s `$fatal` checks do it, just
  generalized to work for *any* generated program instead of one
  hard-coded one).

- **Environment (env)** — the container class that instantiates and
  connects all of the above (sequencer → driver, monitor → scoreboard)
  via TLM analysis ports, plus a virtual interface handle so the driver/
  monitor can actually reach the DUT's pins.

- **Test** — the top-level class that builds the environment, selects
  which sequence(s) to run, and provides overall pass/fail reporting to
  the simulator. Not currently one of the files the AI agent's UVM system
  prompt asks for by name, but it's the natural "run this specific
  scenario" entry point once the env exists — worth writing by hand once
  you have the generated skeleton.

## 2.3 What SVA adds that UVM alone doesn't give you

UVM checks are transaction-level and typically only fire when a sequence
specifically drives a scenario. **SVA (SystemVerilog Assertions)** are
always-on, cycle-by-cycle temporal logic statements checked continuously
throughout simulation, whether or not any test specifically thought to
trigger the condition. Concretely, for this CPU, good SVA targets — and
these map directly onto the "Implemented per DUT_README" list and the RTL
quirks found above — are:

- **x0 immutability** (from `register_file.sv`): "a write with `rd==0`
  never changes `regs[0]`'s effective read value" — this is directly
  checkable from the port-level behavior alone, no internal signal access
  needed.
- **Reset behavior** (from `rv32i_cpu.sv`'s FSM): "`!rst_n` → next state
  is `ST_RESET`", "`pc == 0` immediately after reset deasserts."
- **FSM invariants**: "`ST_HALT` is sticky — once entered, `state` never
  changes again" (directly readable off the RTL's `case` statement).
- **Illegal-opcode no-op** (from `control_unit.sv`'s `default` case):
  "an opcode not in {LUI, AUIPC, JAL, JALR, BRANCH, LOAD, STORE, OPIMM,
  OP, SYSTEM} → `reg_write`/`mem_write`/`branch`/`jump` all deasserted
  that cycle."
- **JALR target alignment**: "whenever `jump && jalr`, the resulting
  `next_pc`'s LSB is always 0" (directly follows from the `& ~1` in the
  RTL — a good "did the RTL actually do what it says" check).
- **Memory port independence / hazard check**: "if port B writes to the
  same index port A is fetching from on the same cycle, the fetched
  value this cycle is *not* required to reflect the just-written data" —
  phrased as a note about what's *not* guaranteed, since the RTL doesn't
  claim same-cycle forwarding.
- **The `instr` direction issue itself** could be turned into an
  assertion ("`instr` should never be driven from within `rv32i_cpu`") if
  you want the assertion suite to actively catch that specific class of
  bug rather than just noting it in review.

Each of these should be tagged, when generated, as **[DERIVED]** (follows
directly from a line of RTL you can point to — everything in this list
does) versus **[INFERRED]** (the model assumed something about intended
behavior beyond what's written). Everything listed above is DERIVED,
because it's read straight off the RTL shown in Part 1, not guessed.

---

# Part 3 — How the AI Agent Generates This Automatically

## 3.1 The pipeline, restated precisely

```
rv32i_cpu.sv ──► rtl_parser.py ──► port list
                                       │
DUT_README.md (spec.txt) ─────────────┼──► retriever.py ──► top-2 exemplars
                                       │         (keyword overlap, see below)
                                       ▼
                             prompts.py builds 2 prompts
                                       │
                    ┌──────────────────┴──────────────────┐
                    ▼                                      ▼
         Call 1: UVM skeleton prompt              Call 2: SVA prompt
         (sent to OpenRouter/LLM)                 (sent to OpenRouter/LLM)
                    │                                      │
                    ▼                                      ▼
       generated_output/uvm_env/*.sv          generated_output/*_assertions.sv
```

Two independent LLM calls, run one after another. See `ARCHITECTURE.md`
for why this is **not** multi-agent (no critic, no revision loop, no
shared state between the two calls beyond what's in the static prompt
text).

## 3.2 What `rtl_parser.py` actually extracts here

Running it on `rv32i_cpu.sv` produces exactly the port list from Part
1.3's "rv32i_cpu.sv" section:
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
It does **not** see inside `alu.sv`, `register_file.sv`, or
`control_unit.sv` — no FSM state names, no opcode table, no knowledge
that x0 is hardwired to zero. All of that context has to come from
`spec.txt` (feeding in `DUT_README.md` is exactly how you give the model
that missing context — see `document.md`'s Step 4).

## 3.3 What gets retrieved, and why

`retriever.py` tokenizes the interface block + spec text and scores each
of the 4 hand-written exemplar files (`exemplars/*.sv`) by shared
keywords. For `rv32i_cpu.sv` + `DUT_README.md`, the top two matches are
`register_file.sv` (tags: register file, x0, immutable...) and
`fsm_assertions.sv` (tags: fsm, state, reset, halt...) — both genuinely
relevant, since this DUT has an x0-immutability invariant and an explicit
3-state FSM. This is real retrieval-augmented generation *structurally*
(retrieve → inject → generate), but the retrieval method is keyword
overlap, not semantic/embedding search — see `ARCHITECTURE.md` §3 for
the honest limitations of that (e.g. it doesn't always rank the single
most relevant exemplar first).

## 3.4 What the two prompts ask for, and why each instruction is there

Full literal prompt text is in `document.md`. In summary:

- The **UVM prompt** names all 7 required output files explicitly
  (item/driver/monitor/sequencer/scoreboard/sequence/env) rather than
  leaving the set open-ended, and demands a strict
  `===FILE:...===`/`===ENDFILE===` delimiter so the response can be
  split into files with one regex — no second LLM call just to reformat.
- The **SVA prompt** requires every assertion to be tagged `[DERIVED]` or
  `[INFERRED]` — directly enabling the review process in Part 2.3 above:
  you can scan the generated file and immediately see which properties
  are safe to trust (they trace to a specific RTL line, like the x0 or
  FSM checks) versus which ones need a second look (anything the model
  assumed about intent that isn't actually written in the RTL or spec).
- Both prompts explicitly instruct "adapt the exemplar's signal names to
  the actual DUT — do not copy verbatim," because without that
  instruction models tend to leave placeholder names like `data`/`valid`/
  `ready` from the exemplar in the output instead of mapping them onto
  this CPU's actual port names (`data_addr`, `data_we`, `pc`, etc.).

## 3.5 What to actually check in the generated output for this CPU specifically

When you run the agent against `rv32i_cpu.sv`, verify by hand:
1. Does the generated scoreboard/monitor reference the real port names
   (`data_addr`, `data_we`, `data_wdata`, `data_rdata`, `pc`, `instr`,
   `halted`) or did it invent generic ones?
2. Do the generated assertions cover the specific things listed in Part
   2.3 (x0 immutability, `ST_HALT` stickiness, illegal-opcode no-op,
   JALR alignment) — those are the ones a judge can verify against the
   RTL in seconds, since they're each one line of RTL away from the
   property that checks them.
3. Are any assertions tagged `[INFERRED]` that assume multi-cycle
   behavior, pipelining, or byte/halfword store masking — since none of
   those exist in this RTL (it's explicitly single-cycle and
   word-oriented stores per `DUT_README.md`), an `[INFERRED]` tag on
   something like that is the model over-assuming, and should be flagged
   or removed before the demo, not presented as a real property.

---

# Part 4 — Protocols and I/O, Precisely

This is the part a UVM driver/monitor actually needs, and it's worth
being exact about it because there is **no standard bus protocol** here
(no AXI, no APB, no Wishbone, no valid/ready handshake anywhere in this
design). It's a small, fixed-timing, point-to-point interface. Modeling
it as if it had handshaking signals it doesn't have is a common mistake
an LLM makes when asked to "infer a reasonable protocol" — worth checking
the generated driver against this section directly.

## 4.1 Every I/O on `rv32i_cpu`, with direction and role

| Signal       | Dir (on rv32i_cpu) | Width | Role |
|---|---|---|---|
| `clk`        | input  | 1  | Single clock domain, everything synchronous to `posedge clk` |
| `rst_n`      | input  | 1  | Active-low reset (see 4.3 — synchronous, not async) |
| `pc`         | output | 32 | Instruction fetch address, driven combinationally from CPU state |
| `instr`      | output* | 32 | Fetched instruction — *see Part 1.3, this direction looks wrong; it's read-only inside the CPU and should logically be an `input` |
| `data_addr`  | output | 32 | Data memory address = `alu_y` (every load/store address is an ALU result) |
| `data_we`    | output | 1  | Write-enable to data memory |
| `data_wdata` | output | 32 | Store data — always `rs2_data`, regardless of store width |
| `data_rdata` | input  | 32 | Load data back from memory |
| `halted`     | output | 1  | Level signal, sticky once asserted |

## 4.2 The two "buses" and their exact timing — no handshake, fixed latency

**Instruction fetch (`pc` → `instr`, via `dual_port_ram` port A):**
Port A is described in `dual_port_ram.sv` as combinational read only —
`assign a_rdata = mem[a_index];`. There is no clock involved in the read
itself: whatever `pc` addresses, `instr` reflects **in the same
simulation cycle**, with zero wait states. No `req`/`ack`, no `valid`,
no stall capability — the memory is assumed to always be ready. A driver
modeling this side of things doesn't drive `pc` (the CPU does); a monitor
just samples `pc` and `instr` together every cycle they're stable, since
there's nothing to synchronize.

**Data memory (`data_addr`/`data_we`/`data_wdata` → `data_rdata`, via
port B):**
- **Read**: also combinational — `assign b_rdata = mem[b_index];` —
  whatever `data_addr` currently points at, `data_rdata` reflects
  immediately, same cycle, regardless of `data_we`.
- **Write**: synchronous — `if (b_we) mem[b_index] <= b_wdata;` inside
  `always_ff @(posedge clk)` — a write asserted with `data_we=1` during a
  cycle commits to memory **at the next rising edge**, using whatever
  `data_addr`/`data_wdata` were present during that cycle.
- There is no acknowledgment signal telling the CPU a write completed —
  none is needed because the write is guaranteed to happen exactly one
  cycle after being asserted, always, with no possibility of the memory
  being "busy."

**In short: this is a single-cycle, fixed-latency, always-ready local
memory interface — not a request/response bus.** A UVM driver for the
data-memory side should look like: "drive `data_addr`/`data_we`/
`data_wdata` for one cycle, they take effect (write) or are visible
(read) immediately or on the next edge as described above" — no
polling, no waiting for a ready signal, because none exists.

## 4.3 Reset protocol — and a detail worth getting right in the driver

`rv32i_cpu.sv`'s only sequential block is:
```systemverilog
always_ff @(posedge clk) begin
    if (!rst_n) begin
        state <= ST_RESET;
        pc    <= 32'd0;
    end
    ...
```
The sensitivity list is `@(posedge clk)` only — **not**
`@(posedge clk or negedge rst_n)`. That makes this a **synchronous**
active-low reset: `rst_n` is only sampled *at* a clock edge, not
immediately when it drops. Practically, for any driver/sequence that
resets the DUT: **`rst_n` must be held low across at least one
`posedge clk`** for reset to actually take effect — dropping it and
raising it between clock edges would do nothing. `tb_mini_cpu.sv` gets
this right already (`repeat (2) @(posedge clk); rst_n = 1'b1;` — holds
it low across two clock edges before releasing), and any generated UVM
reset sequence should follow the same shape, not assume async reset
takes effect instantly.

Also note register-file reset (`register_file.sv`) uses the exact same
synchronous pattern — both reset together on the same edge, so there's
no reset-ordering hazard between the two to worry about.

## 4.4 `halted` — a level output, not a pulse or a handshake ack

`assign halted = (state == ST_HALT);` and `ST_HALT` is sticky
(`ST_HALT: next_state = ST_HALT;` unconditionally). So `halted` is a
plain combinational level signal that goes high once and stays high
until the next reset — not a one-cycle pulse, and not something that
needs to be "acknowledged" by anything. A monitor just needs to detect
the `0→1` edge once; polling `wait(halted)` (exactly what
`tb_mini_cpu.sv` does) is the correct and simplest way to detect it.

## 4.5 What this means for the UVM driver/monitor the agent generates

- **No `ready`/`valid`/`ack` fields belong in the transaction item for
  either interface** — if the generated `_item.sv` includes them, that's
  the model over-generalizing from a generic "memory bus" exemplar rather
  than reflecting this DUT's actual (handshake-free) timing. Worth
  checking against the exemplar note in Part 3.4 — the retrieved
  `mem_bus.sv` exemplar (Part 3.3) is a *generic* memory-bus pattern and
  doesn't itself assume handshaking either, but it's still worth
  double-checking the generated code didn't drift.
- **The driver's only real timing responsibility** is: assert signals
  for exactly one cycle per transaction, know that writes commit next
  edge and reads are visible same-edge, and hold `rst_n` low across at
  least one clock edge for any reset sequence.
- **The monitor's job is almost entirely passive sampling** — no
  decoding of a multi-cycle protocol state machine needed, since nothing
  on these two interfaces spans more than one or two cycles.
