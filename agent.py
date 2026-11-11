"""
End-to-end orchestrator.

Usage:
    export OPENROUTER_API_KEY=sk-or-...
    python agent.py path/to/dut.v [path/to/spec.txt] [-o out_dir] [-m model]

Requires: pip install requests --break-system-packages
"""
import argparse
import os
import re
import sys

import requests

from rtl_parser import parse_rtl
from prompts import build_uvm_prompt, build_sva_prompt

FILE_RE = re.compile(r"===FILE:\s*(.+?)\s*===\n(.*?)\n===ENDFILE===", re.DOTALL)

OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"
DEFAULT_MODEL = "anthropic/claude-sonnet-4.6"


def call_llm(system: str, user: str, model: str = DEFAULT_MODEL) -> str:
    api_key = os.environ.get("OPENROUTER_API_KEY")
    if not api_key:
        sys.exit("Set OPENROUTER_API_KEY in your environment.")
    resp = requests.post(
        OPENROUTER_URL,
        headers={"Authorization": f"Bearer {api_key}"},
        json={
            "model": model,
            "max_tokens": 4000,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
        },
        timeout=120,
    )
    resp.raise_for_status()
    return resp.json()["choices"][0]["message"]["content"]


def split_files(response_text: str) -> dict:
    files = {}
    for fname, content in FILE_RE.findall(response_text):
        files[fname.strip()] = content.strip() + "\n"
    if not files:
        # Fallback: model ignored delimiters -- dump raw so nothing is lost
        files["RAW_OUTPUT.txt"] = response_text
    return files


def write_files(files: dict, out_dir: str):
    os.makedirs(out_dir, exist_ok=True)
    for fname, content in files.items():
        # Model output cannot choose arbitrary filesystem paths.
        fname = os.path.basename(fname.strip())
        if not fname or fname in {".", ".."}:
            print("  skipped invalid output filename")
            continue
        path = os.path.join(out_dir, fname)
        with open(path, "w") as f:
            f.write(content)
        print(f"  wrote {path}")


def build_ambiguity_report(iface, spec_text: str) -> str:
    """Create a human-reviewable gate before behavior-dependent generation."""
    lines = [
        f"# DUT review and ambiguity report: {iface.name}",
        "",
        "## Extracted interface facts",
        "",
        "```text",
        iface.as_prompt_block(),
        "```",
        "",
        "## Items requiring human review",
        "",
        "- Confirm this is the intended top-level DUT and these are the exact ports and widths.",
        "- Confirm the supplied specification (if any) is authoritative for intended behavior.",
        "- Protocol/transaction acceptance rules are not inferred from port names or widths.",
        "- Confirm clock edge and reset polarity/timing from the specification before using reset-dependent properties.",
        "- Confirm latency, legal operations, and expected outputs are specified before generating behavioral checks.",
    ]
    if iface.ambiguities:
        lines += ["", "## Parser ambiguities", ""]
        lines += [f"- {a}" for a in iface.ambiguities]
    if not spec_text.strip():
        lines += ["", "## Specification status", "", "No specification was supplied. Generate structural scaffolding only; omit behavior-dependent stimulus, scoreboard predictions, and executable assertions unless the human provides confirmed rules."]
    else:
        lines += ["", "## Specification status", "", "A specification was supplied. The generator must cite its stated requirements and must not fill gaps with guessed behavior."]
    lines += ["", "## Human confirmation", "", "Review the items above. Type CONFIRM in the CLI only if the interface is correct and you approve generation using explicitly specified behavior only. Otherwise stop, correct the RTL/specification, and rerun."]
    return "\n".join(lines) + "\n"


def run(rtl_path: str, spec_path: str | None, out_dir: str, model: str = DEFAULT_MODEL, top: str | None = None):
    with open(rtl_path) as f:
        rtl_text = f.read()
    iface = parse_rtl(rtl_text, top=top)
    iface_block = iface.as_prompt_block()
    # Fail closed when the selected module/interface could not be reliably extracted.
    if not iface.ports or iface.ambiguities:
        print("Parser reported unresolved interface issues; generation stopped. Fix RTL/top selection first.")
        print("\n".join(f"- {a}" for a in iface.ambiguities))
        return
    print(f"Parsed interface:\n{iface_block}\n")

    spec_text = ""
    if spec_path:
        if not os.path.isfile(spec_path):
            print(f"Specification file not found: {spec_path}")
            return
        with open(spec_path, encoding="utf-8") as f:
            spec_text = f.read()

    os.makedirs(out_dir, exist_ok=True)
    report = build_ambiguity_report(iface, spec_text)
    report_path = os.path.join(out_dir, "ambiguity_report.md")
    with open(report_path, "w", encoding="utf-8") as f:
        f.write(report)
    print(f"\nHuman review required. Report written to: {report_path}\n")
    print(report)
    try:
        confirmation = input("Type CONFIRM to generate using only supported behavior: ").strip()
    except EOFError:
        confirmation = ""
    if confirmation != "CONFIRM":
        print("Stopped before model calls. Review the report/specification and rerun.")
        return

    print("The RTL and specification will be sent to the configured external LLM provider.")
    try:
        privacy_confirmation = input('Type SEND to approve external transmission: ').strip()
    except EOFError:
        privacy_confirmation = ""
    if privacy_confirmation != "SEND":
        print("Stopped. No source was sent to the external provider.")
        return

    print("Generating UVM skeleton...")
    uvm_sys, uvm_user = build_uvm_prompt(iface.name, iface_block, spec_text, rtl_text)
    uvm_response = call_llm(uvm_sys, uvm_user, model)
    uvm_files = split_files(uvm_response)
    write_files(uvm_files, os.path.join(out_dir, "uvm_env"))

    print("Generating SVA...")
    sva_sys, sva_user = build_sva_prompt(iface.name, iface_block, spec_text, rtl_text)
    sva_response = call_llm(sva_sys, sva_user, model)
    sva_files = split_files(sva_response)
    write_files(sva_files, out_dir)

    print(f"\nDone. Output in: {out_dir}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("rtl_file")
    ap.add_argument("spec_file", nargs="?", default=None)
    ap.add_argument("-o", "--out", default="generated_output")
    ap.add_argument("-m", "--model", default=DEFAULT_MODEL,
                     help="OpenRouter model slug, e.g. openai/gpt-4o, anthropic/claude-sonnet-4.6")
    ap.add_argument("--top", default=None, help="Top module name (defaults to first module)")
    args = ap.parse_args()
    run(args.rtl_file, args.spec_file, args.out, args.model, args.top)
