# RAG removed

Per your mentor's direction, the retrieval-augmented-generation layer
(`retriever.py`, `exemplars/`) has been removed from `agent.py`/`prompts.py`.
The pipeline is back to: parse RTL -> build prompt -> call model, twice
(UVM skeleton, then SVA) -- no retrieval step.

`ARCHITECTURE.md`, `EXPLANATION.md`, `document.md`, and
`SYSTEM_EXPLAINED.md` still describe the RAG layer in detail as design
history (what was tried, why, and how it worked) -- that content is now
stale relative to the actual code and kept for the record, not as a
description of the current pipeline. Treat this file as the current
source of truth on what's actually wired in.
