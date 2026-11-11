# What This Pipeline Actually Does

## 1. The pipeline, honestly

```
RTL file
   │
   ▼
rtl_parser.py  ──►  port list (regex, not a real Verilog parser)
   │
   ▼
retriever.py   ──►  top-k exemplar snippets by keyword overlap with the
   │                 interface + spec text (this is the "RAG" part)
   ▼
prompts.py     ──►  builds one prompt for UVM, one for SVA, each with:
   │                 DUT interface + spec text + retrieved exemplars
   ▼
agent.py       ──►  two sequential LLM calls (via OpenRouter), splits
   │                 each response on a fixed delimiter into files
   ▼
generated_output/uvm_env/*.sv, *_assertions.sv
```

Two LLM calls, run one after the other, no branching, no shared state
between them beyond what's in the prompts. That's the whole system.

## 2. Is this multi-agent? No.

**Multi-agent** means multiple LLM-driven roles that each hold their own
goal/state and interact — e.g. a planner that delegates to a generator,
which hands off to a critic, which sends work back for revision, with the
system deciding what happens next based on what comes back.

This pipeline is a **single-agent, two-step sequential pipeline**: step 1
generates UVM, step 2 generates SVA. Neither call sees the other's output,
neither critiques anything, there's no loop, no decision point, no shared
memory across calls beyond the static prompt text. It's closer to "two
scripted API calls" than "agents."

If someone asks whether this is multi-agent, the honest answer is no —
and don't call it that to judges. If you want to *actually* make it
multi-agent within the time you have, the smallest real version is:

- **Generator** (what exists now) → produces UVM+SVA
- **Critic** → given the generated SV, checks it against the DUT interface
  and flags anything obviously wrong (undriven signals, mismatched port
  names, missing reset handling) in plain text
- **Fixer** → takes generator output + critic notes, produces a revised
  version

That's a real 3-role loop, feasible to add if you have 45+ minutes left —
it's just three more prompt templates and one more `call_llm` round-trip
per stage, reusing everything already built.

## 3. What RAG actually is, and what we built

**Retrieval-Augmented Generation**, properly: given a query, search a
knowledge base for the most relevant documents (usually via embedding the
query and the corpus into vectors, then nearest-neighbor search), and
inject the retrieved text into the prompt so the model grounds its answer
in real reference material instead of only what it already "knows."

**What we built (`retriever.py`):** a corpus of 4 hand-written exemplar
files (`exemplars/*.sv`) — memory-bus driver/monitor, FSM assertion
shapes, valid/ready handshake patterns, register-file invariant patterns.
Retrieval is **keyword overlap**, not embeddings: tokenize the DUT
interface + spec text, tokenize each exemplar's tags + body, count shared
tokens, take the top-k. No embedding model, no vector database, no
network call for retrieval — it's a dict lookup with word-set intersection.

This is RAG in the structural sense (retrieve → inject → generate) but
not in the sense most people mean when they say "RAG" (semantic/vector
search). Say that plainly if asked — "keyword-based retrieval, not
embeddings, because of time" is a true and defensible sentence. Don't
call it semantic search.

**Why do this at all, if it's just keyword matching?** It still grounds
generation in real UVM/SVA idioms instead of the model inventing signal
handling patterns from scratch each time, and it's a legitimate, working
example of the retrieve → augment → generate shape — just implemented
with the cheapest retrieval method that works in the time available.

**Known weakness, worth stating rather than hiding:** keyword overlap
ranks generic words alongside specific ones, so for `rv32i_cpu.sv`
(interface-only query) the memory-bus exemplar — the most relevant one —
doesn't always rank first; it improves once `spec.txt` (with words like
"memory interface", "register file") is included in the query, because
there's more text to match against. If asked why retrieval sometimes
picks a less relevant exemplar, that's the honest reason.

## 4. Layers that exist in a "real" version of this system that we do not have

Say these upfront in the demo rather than waiting for a judge to ask.

- **Semantic retrieval.** Real RAG would embed the corpus once (e.g. via
  an embeddings API) and the query at request time, then do cosine
  similarity in vector space. We do word-set overlap. The corpus is also
  tiny (4 files) — a real system would have dozens to hundreds of vetted
  UVM/SVA examples.
- **Compile/syntax verification.** Nothing checks that the generated
  SystemVerilog actually compiles. A real pipeline would pipe output
  through `iverilog`/`verilator` (or a commercial compiler) and feed
  errors back to the model for a repair pass. We do not have this loop.
- **Simulation-in-the-loop feedback.** No coverage data, no waveform
  inspection, no pass/fail signal ever reaches the model. Everything is
  generated "blind" — the model never learns whether what it wrote is
  correct beyond its own training.
- **Multi-agent critique/repair.** Covered in §2 — no critic role, no
  revision loop, no consensus between multiple model calls.
- **Structural RTL understanding.** The parser reads the DUT's own port
  list only; it doesn't parse submodule instantiations, doesn't build a
  real AST, doesn't resolve parameters, doesn't understand hierarchy. A
  real tool would use a proper Verilog frontend (e.g. Verilator's AST,
  slang, pyverilog) instead of regex.
- **Formal verification / model checking.** SVA here is generated code,
  not formally checked against the RTL. A real DFT/verification pipeline
  would run these assertions through a formal tool to confirm they're
  even satisfiable, not just plausible-looking.
- **Guardrails on generated code.** No check for licensing, no static
  analysis (lint) pass, no check that required files are non-empty or
  that ports referenced in generated code actually exist on the DUT.
- **LangChain/agent frameworks.** Deliberately not used — see the earlier
  discussion. The two-call pipeline doesn't need chain/agent abstractions,
  and adopting one would cost setup time without adding a capability this
  system doesn't already have. If a judge wants LangChain/LangGraph
  specifically, that's a framework swap, not a new capability.

## 5. One-paragraph version, if a judge asks and you have 10 seconds

"It's a single-agent, two-call pipeline: parse the DUT's ports, retrieve
a couple of relevant example patterns from a small hand-built corpus via
keyword overlap, inject those into two prompts, and generate a UVM
skeleton and an SVA set. It's RAG in structure, not in the embeddings
sense, and it's not multi-agent — there's no critic or revision loop yet,
though that's the obvious next step if we had more time."
