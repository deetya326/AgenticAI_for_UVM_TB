# EXPLANATION.md — How Chip Verification Actually Works, and What We Built

Written for someone who understands digital logic but has never worked in
a real verification flow. No prior UVM/industry knowledge assumed.

---

# Part 0 — Your mentor's remarks, answered directly

**"Which one is the top?"** — `mini_cpu_top.sv` is the real top-level
module (the whole chip: CPU + memory, only `clk`/`rst_n`/`halted` visible
outside it). `rv32i_cpu.sv` is a submodule inside it that we chose to
verify directly because it has a richer external interface. That's a
legitimate verification strategy (called **block-level verification** —
Part 5.6), but if your mentor means "the DUT" as "the actual chip," the
answer is `mini_cpu_top.sv`. **Ask them which level they want verified**
— block-level (`rv32i_cpu`) or full-chip (`mini_cpu_top`) — this changes
what the driver has to do (Part 5.5).

**"It needs a protocol"** — Correct, and explained fully in Part 3. Short
version: your interface has *timing* (we documented it precisely) but
nothing had *formally declared* that timing in one place the way a real
UVM environment expects. We've now written that formal declaration
(`manual_uvm/cpu_if.sv`).

> **RETRACTED — see correction below.** Everything below this box was
> based on `iverilog` (open-source), which flagged this as a hard
> compile error. Compiling the **original, unmodified** RTL on Questa
> (the real tool, via an actual `vlog`/`vsim` log) produced **0 errors,
> 0 warnings**, and the simulation ran correctly. That claim was wrong
> as a blanket statement — but it doesn't fully collapse either. See the
> follow-up note right after Part 2 for the precise, corrected version:
> it depends on whether you're simulating the full chip or verifying
> `rv32i_cpu` standalone.

**"This is not proper"** — Also correct, for a very concrete reason we
found by actually running the RTL through a compiler (Part 2): the
original RTL **does not compile**. `rv32i_cpu`'s `instr` port is declared
`output` but is only ever read inside the module, never driven — and in
`mini_cpu_top.sv` the same wire is also driven by the RAM. A real
compiler rejects this outright. This alone would make any testbench
"not proper," because you can't build a proper verification environment
on RTL that doesn't elaborate. We found the exact compiler error, fixed
it, and confirmed the fix by re-running — see Part 2.

**"We didn't get a driver/monitor"** — because nothing had generated one
yet: the AI agent had never actually been run (no API key was ever
supplied), so there was no `generated_output/` anywhere. We've now
**hand-written** a real interface, driver, monitor, scoreboard, sequences,
and test classes (`manual_uvm/`) against the *fixed* RTL, described in
Part 5.

**"What test cases"** — a *test case* in verification means one specific
scenario with a specific expected outcome — not the environment itself,
which is reusable across many test cases. We wrote and (partially)
verified six (Part 6).

**"What scores"** — we genuinely don't have enough context to answer
this one. It could mean functional coverage percentage, a hackathon
judging rubric, pass/fail counts, or something else your mentor has in
mind from a conversation we weren't part of. **Ask them what metric they
meant** — we don't want to guess and give you the wrong framing to bring
back.

---

# Part 1 — RTL vs. Verification: two separate jobs, on purpose

**RTL** (Register-Transfer Level code — the `.sv` files describing the
CPU) defines what the chip *should* do. **Verification** is a completely
separate body of code whose only purpose is to *prove*, through stimulus
and checking, that the RTL actually does what it's supposed to —
including in situations nobody thought to hand-test. In real industry
flows these are typically written by different engineers, sometimes
different teams, specifically so the person checking the design isn't
the same person who might have baked their own assumptions into it.

The **DUT** (Design Under Test) is just "the RTL we're currently
verifying" — could be a whole chip, or one block inside it.

---

## Part 2 — CORRECTION: the "instr" claim below was wrong on the real tool

Everything in this section was based on `iverilog`, an open-source
compiler, which reported a hard elaboration error for `rv32i_cpu`'s
`instr` port. **A real Questa compile of the original, unmodified RTL —
confirmed via an actual `vlog` compile log and `vsim` simulation log —
shows 0 errors, 0 warnings, and correct simulation results.** That means
this was an iverilog-specific false positive, not a genuine defect. The
original RTL is fine as given; do not apply the fix described below.
Kept below, marked, rather than deleted, so the reasoning trail is
honest about what was claimed and what corrected it.

# Part 2 — What we actually found by compiling the RTL (evidence, not guesses)

We installed `iverilog` (an open-source SystemVerilog compiler) and
compiled the original files exactly as given:

```
mini_cpu_top.sv:38: error: Unresolved net/uwire instr cannot have multiple drivers.
mini_cpu_top.sv:38: error: Output port expression must support continuous assignment.
mini_cpu_top.sv:38:      : Port 4 (instr) of rv32i_cpu is connected to instr
```

This confirms, with a real tool (not just our reading of the code), that
`rv32i_cpu`'s `instr` port direction is wrong. **The fix:** change
`output logic [31:0] instr` to `input logic [31:0] instr` in
`rv32i_cpu.sv` (it's only ever read inside that module — every other use
matches an input). We applied this fix in `fixed_rtl/rv32i_cpu.sv`, and
**re-ran the original testbench** (`tb_mini_cpu.sv`) against the fixed
RTL:

```
========================================
 MINI RV32I CPU DEMO COMPLETE
 x1 = 5
 x2 = 7
 x3 = 12
 x4 = 12
 x5 = 0
 MEM[0] = 12
========================================
PASS: all demo checks passed.
```

**So: the design is otherwise correct** (at least for this one program) —
this was a single mis-declared port direction, not a deep logic bug. This
is exactly the kind of thing "proper" verification exists to catch before
anyone builds more testbench infrastructure on top of broken RTL. Fix
this in your working copy before doing anything else.

## Follow-up correction — the precise, non-overcorrected version

The paragraph above is itself too broad, based on a later real Questa
run. Two genuinely different contexts, not one universal answer:

- **Full-chip (`mini_cpu_top`, real RAM attached):** the original RTL
  (`instr` declared `output`) compiles and simulates correctly on
  Questa — confirmed by an actual `vlog`/`vsim` log. **No fix needed
  here.** The iverilog error above doesn't reproduce on the tool that
  matters; treat it as a tool-specific false positive for this context.
- **Block-level standalone (`rv32i_cpu` alone, driven by a UVM
  testbench — Part 5 below):** a driver cannot feed a value into a port
  declared `output` through a normal connection, in *any*
  standards-compliant simulator — this isn't a tool-leniency question,
  it's basic port semantics. For this specific use, a build with
  `instr` as `input` genuinely is required — not because the original
  RTL is "buggy," but because standalone driving of an output pin isn't
  meaningful without it. `fixed_rtl/rv32i_cpu.sv` still serves this
  purpose correctly — just understand it as "a verification-only build
  for standalone testing," not "a bug fix to the design."

---

# Part 3 — What "protocol" means here, precisely

A **bus protocol** is the *formal, agreed-upon timing contract* between
two pieces of hardware that talk to each other: which signals exist,
what each one means, and — critically — the exact cycle-by-cycle
sequence in which they're allowed to change. "Protocol" doesn't
necessarily mean a famous named standard; it just means "the rules two
components follow to talk to each other," documented somewhere formal
enough that a testbench can be built against it without guessing.

**Named/standard protocols** you'll hear about in real chip work: AXI,
AXI-Lite, APB (all from Arm, common on-chip), Wishbone (open-source),
I2C, SPI, UART (common off-chip/peripheral), PCIe, USB (complex,
external). Each has a published specification, often hundreds of pages,
defining every signal and timing rule precisely.

**This CPU's interfaces are not any of those.** They're a small, custom,
project-specific protocol. That's completely normal for an internal
CPU-to-memory connection — it doesn't need to be a named standard, it
just needs to be *precisely defined somewhere*. We defined it precisely
in `SYSTEM_EXPLAINED.md` Part 4 and then formalized it as an actual
SystemVerilog `interface` (`manual_uvm/cpu_if.sv`) — see Part 5.2. In one
sentence: **combinational reads (both instruction fetch and data),
one-cycle synchronous writes, synchronous active-low reset, no
valid/ready/ack handshake anywhere.**

---

# Part 4 — Verification IP (VIP): what it is, and why you don't have one here

This is the piece that's genuinely industry-specific and easy to miss if
you've only seen small student projects.

**VIP (Verification IP)** is a pre-built, reusable verification
component — typically a driver + monitor + sequencer + a library of
protocol-correctness assertions — for a **standard, named protocol**.
Companies like Cadence, Synopsys, and Siemens (Mentor) sell AXI VIP,
PCIe VIP, USB VIP, etc. Instead of writing your own AXI driver/monitor
from scratch every time you verify a chip that happens to have an AXI
interface, you license (or use an open-source) AXI VIP, plug it in, and
it already knows every legal AXI timing sequence and already has
assertions checking AXI protocol compliance built in. This is *the* main
reason verification for standard interfaces is fast in industry — nobody
re-derives the AXI handshake rules every project.

**Why we didn't use one:** VIP only exists for protocols worth
standardizing across the industry. This CPU's memory interface is a
one-off, project-specific protocol (Part 3) — no commercial or
open-source VIP exists for it, because no one else has this exact
interface. **This is exactly why we had to hand-write the driver and
monitor** (`manual_uvm/cpu_driver.sv`, `cpu_monitor.sv`) instead of
dropping in an off-the-shelf component. If this CPU's data-memory
interface were instead a standard AXI-Lite port, the right move would be
to grab an AXI-Lite VIP and skip writing a custom driver/monitor
entirely.

**The rule of thumb your mentor is almost certainly getting at:** before
writing a custom driver/monitor, always check whether the interface is
actually a standard protocol in disguise — sometimes a "custom" memory
interface is close enough to Wishbone or a simple SRAM protocol that an
existing VIP (or a well-known open-source model) could be adapted instead
of writing one from scratch. In this case we checked (Part 3) and
confirmed: genuinely custom, no handshake, so a hand-written model is the
correct call, not a shortcut we skipped.

---

# Part 5 — The UVM environment, explained from scratch, and what we actually wrote

## 5.1 Why UVM exists at all

UVM (Universal Verification Methodology) is a SystemVerilog class library
and a set of conventions for structuring a testbench as small, reusable,
swappable pieces instead of one big monolithic test file (like
`tb_mini_cpu.sv`, which works fine for one hard-coded program but doesn't
scale to dozens of test scenarios or randomized stimulus). The entire
point is **reuse**: the same driver/monitor/scoreboard should work for
every test case you'll ever write against this DUT — only the *sequence*
(the specific stimulus) changes per test case.

## 5.2 The interface — the formal protocol contract (Part 3, made real)

`manual_uvm/cpu_if.sv` is a SystemVerilog `interface`: a single named
bundle grouping every signal on the CPU's external boundary, so nothing
in the verification code has to guess at timing — it's declared once,
here, and referenced everywhere else via a **virtual interface** handle.
It also has a `dbg_regs` debug tap: not part of the real DUT, but a
convenience so the scoreboard (5.5) can read final register values
without scattering hierarchical references through the code — bound in
`tb_top.sv` with `assign vif.dbg_regs = u_dut.rf.regs;`.

## 5.3 Every UVM role, and what it does for *this* CPU specifically

- **Transaction / sequence item** (`cpu_program_item.sv`) — a data
  container, nothing more: here, "one unit of stimulus" is a whole
  program (a queue of instruction words) to preload into memory, because
  that's the natural unit of stimulus for a CPU.
- **Sequence** (`cpu_sequences.sv`) — generates transactions. Each
  concrete sequence here *is* one test case's program (Part 6).
- **Sequencer** (`typedef ... cpu_sequencer` in `cpu_env.sv`) — the
  queue/arbiter handing sequence items to the driver in order. With one
  sequence at a time here, it's mostly plumbing, but keeping it separate
  is what lets you later run multiple sequences, randomize, or reuse the
  same driver against a different sequence without touching driver code.
- **Driver** (`cpu_driver.sv`) — the part that surprised us most while
  writing it. Because the CPU is the *bus master* (it addresses memory,
  memory responds), there's no "input pin" on the CPU for a driver to
  wiggle directly the way you'd drive, say, a UART line. The driver's
  real job here is **playing the part of the external memory**: preload
  a program once per test case, then run a background process every
  cycle that reads whatever address the CPU is asking for and supplies
  the response, plus commits writes on the clock edge — exactly the
  timing from Part 3.
- **Monitor** (`cpu_monitor.sv`) — passive, read-only. Watches
  `pc`/`instr`/`data_*`/`halted` every cycle and broadcasts an "observed"
  transaction over an analysis port. Never drives anything.
- **Scoreboard** (`cpu_scoreboard.sv`) — the actual pass/fail brain. Each
  test case tells it, in advance, which registers should hold which
  values (`expected_regs`); once the monitor reports `halted`, it reads
  the debug tap and compares. This generalizes what `tb_mini_cpu.sv`'s
  hard-coded `$fatal` checks did, so the same scoreboard works for every
  test case without being rewritten.
- **Environment / env** (`cpu_env.sv`) — the container that instantiates
  and wires all of the above together.
- **Test** (`cpu_tests.sv`) — the top-level class per test case: builds
  the env, tells the scoreboard what to expect, starts the right
  sequence. This is the piece the original agent-generation prompt
  didn't ask for by name — it's the "which scenario runs" glue, and we
  wrote six of them (one per test case, Part 6).
- **Top-level module** (`tb_top.sv`) — outside UVM entirely: generates
  the clock, releases reset (held low across 2 clock edges — Part 3's
  synchronous-reset requirement), instantiates the fixed DUT, binds the
  interface, and calls `run_test()`.

## 5.4 Important honesty note on this code's status

We do **not** have a UVM class library available in this environment to
actually compile `manual_uvm/`'s code (that needs a real EDA tool —
Questa, VCS, Xcelium, or a separately-built open-source UVM core; none
were available here). **This is syntactically correct, standard UVM 1.2,
written carefully against the RTL and timing we verified — but it has
not been compiled or run.** That's different from the RTL-level claims
in Part 2, which we *did* compile and run with real evidence. Run it
first thing on whatever tool your lab/hackathon actually provides, and
expect to fix small mistakes — that's completely normal for hand-written
UVM code that hasn't touched a real simulator yet.

## 5.5 Depends on your mentor's answer to Part 0's first question

If you verify `rv32i_cpu` standalone (what we built): the driver must
*be* the memory, as described above. If instead your mentor wants
`mini_cpu_top` verified (the real top, with the RAM inside it): you don't
need a memory-model driver at all — the real RAM is already there. The
driver's job shrinks to "preload the program into the real RAM" (much
closer to what `tb_mini_cpu.sv` already does with
`dut.mem.mem[0] = ...`), and the monitor would need hierarchical signal
access to see the internal bus (since `mini_cpu_top` only exposes
`clk`/`rst_n`/`halted` externally) — which is a real, common trade-off in
top-level verification: less bug-surface exposed for a driver to control,
but a "less pure" monitor that has to reach inside the DUT to see
anything.

## 5.6 Block-level vs. top-level verification (the term for what Part 0 is asking)

**Block-level** verification targets one internal module (`rv32i_cpu`)
with its own dedicated testbench — faster to build, easier to hit corner
cases directly, but doesn't prove the *integration* is correct (e.g. it
wouldn't have caught the `instr` port bug, since that bug only appears
when `rv32i_cpu` is wired into `mini_cpu_top`!). **Top-level**
verification targets the full chip (`mini_cpu_top`) — proves integration
is correct, but is harder to hit specific internal corner cases through
only `clk`/`rst_n`/`halted`. Real projects usually do **both**: block-level
for thorough per-module coverage, top-level for integration confidence.
Worth explicitly telling your mentor you understand this distinction —
it's likely close to what "which is the top" was probing for.

---

# Part 6 — The six test cases, and what actually happened when we ran them

We hand-assembled real RV32I machine code (Python encoder, not guessed
by hand) for six scenarios and ran each one through the **fixed RTL**
using the plain testbench approach (not the UVM one — Part 5.4) to get
ground-truth expected values before trusting them in the scoreboard.

| Test case | What it checks | Result |
|---|---|---|
| `alu_reg_test` | ADDI/ADD/SUB/LUI/AUIPC | **PASS** — x1=5 x2=7 x3=12 x4=2 x5=268435456 x6=20 |
| `load_store_test` | SW then LW roundtrip | **PASS** — x1=5 x2=7 x3=12 x4=12, MEM[0]=12 |
| `branch_test` | BEQ taken + BNE taken | **PASS** — x1=5 x2=5 x3=0(skipped) x4=1 x5=3 x6=4 x7=0(skipped) x8=1 |
| `illegal_opcode_test` | Illegal opcode is a no-op | **PASS** — x1=42 unchanged, no crash |
| `x0_immutable_test` | x0 can't be written | **PASS** — x0=0 despite an ADDI targeting it |
| `jalr_test` | JALR target alignment | **DID NOT FINISH — timed out**, never reached EBREAK |

**The JALR result is an open finding, not a hidden failure we're
smoothing over.** Either our hand-assembled JALR encoding/offset is
wrong, or there's a real bug in the CPU's JALR handling — we ran out of
time to root-cause which. This is genuinely a good thing to bring to
your mentor as-is: it's a live example of verification doing its job
(catching something that doesn't work), and root-causing it — is it the
test or the RTL? — is a great next step to show ownership of, rather than
something to hide or paper over with a made-up "expected" value.

---

# Part 7 — Where the AI agent fits into all of this

Restating this precisely now that Parts 1–6 give it context: the AI
agent (`agent.py`, `rtl_parser.py`, `retriever.py`, `prompts.py`) is a
tool that, given a DUT's port list, generates a **first-draft** UVM
skeleton and SVA set via two LLM calls. It is not a substitute for
understanding any of the above — it's a starting point that still needs
everything Parts 2–6 describe: confirming the RTL actually compiles,
correctly identifying the protocol, checking whether real VIP applies,
verifying generated driver/monitor logic matches the real timing, and
running actual test cases with ground-truth-checked expected values.
`ARCHITECTURE.md` covers precisely which parts of a "real" pipeline it
is and isn't (it's not multi-agent, its retrieval is keyword-based not
semantic) — everything in this document is the human-verification layer
that has to sit around it regardless of how good the generated first
draft is.

---

# Glossary — quick reference

- **RTL**: Register-Transfer Level — the actual hardware description code.
- **DUT**: Design Under Test — whatever RTL block you're currently verifying.
- **Protocol**: the formal timing rules two components use to talk to each other (named/standard, like AXI, or custom, like this CPU's).
- **VIP**: Verification IP — a pre-built driver/monitor/checker set for a *standard* protocol, so you don't write one from scratch (Part 4).
- **Interface (SV `interface`)**: a SystemVerilog construct bundling a protocol's signals into one named, connectable unit.
- **UVM**: Universal Verification Methodology — the class library/conventions for structuring reusable testbenches (Part 5).
- **Driver**: converts a transaction into real signal activity on the DUT's pins.
- **Monitor**: passively watches DUT pins, reconstructs what happened, broadcasts it.
- **Sequencer**: hands transactions from a sequence to a driver in order.
- **Sequence**: generates a specific stream of transactions — this is where "test case" content actually lives.
- **Scoreboard**: compares observed behavior against expected/reference behavior; the pass/fail decision-maker.
- **Test** (UVM class): builds the environment and picks which sequence(s) run — one test class per test case.
- **Test case**: a specific scenario + its specific expected outcome (Part 6's six rows).
- **SVA**: SystemVerilog Assertions — always-on, cycle-by-cycle checks, independent of whether any test specifically triggers the condition.
- **Block-level vs. top-level verification**: verifying one internal module directly vs. verifying the whole integrated chip (Part 5.6).
