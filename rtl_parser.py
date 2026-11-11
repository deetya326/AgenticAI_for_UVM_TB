"""Conservative SystemVerilog module-interface extractor.

Supports ANSI-style module headers and common non-ANSI declarations. This is
an interface extractor, not a complete SystemVerilog parser: unsupported or
unresolved constructs are reported rather than guessed.
"""
from __future__ import annotations

import ast
import re
from dataclasses import dataclass, field


@dataclass
class Port:
    direction: str
    width: str                 # resolved bit count, or symbolic expression
    name: str
    packed_range: str = ""     # original packed range, e.g. [WIDTH-1:0]
    data_type: str = "logic"

    @property
    def width_is_resolved(self) -> bool:
        return self.width.isdigit()


@dataclass
class ModuleInterface:
    name: str
    ports: list[Port] = field(default_factory=list)
    parameters: dict[str, str] = field(default_factory=dict)
    ambiguities: list[str] = field(default_factory=list)

    def as_prompt_block(self) -> str:
        lines = [f"Module: {self.name}"]
        if self.parameters:
            lines.append("Parameters:")
            lines.extend(f"  {k} = {v}" for k, v in self.parameters.items())
        lines.append("Ports (actual declarations):")
        for p in self.ports:
            width = f"{p.width} bits" if p.width_is_resolved else f"unresolved width expression {p.width!r}"
            rng = f" packed_range={p.packed_range}" if p.packed_range else ""
            lines.append(f"  {p.direction:<6} {p.name}: {width}{rng} type={p.data_type}")
        if self.ambiguities:
            lines.append("Interface extraction ambiguities:")
            lines.extend(f"  - {a}" for a in self.ambiguities)
        lines.append("Do not infer protocol or behavior from port names or widths.")
        return "\n".join(lines)


def _strip_comments(text: str) -> str:
    # Keep line positions broadly stable; comments are not part of declarations.
    text = re.sub(r"/\*.*?\*/", lambda m: " " * len(m.group(0)), text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def _matching(text: str, start: int, opening: str = "(", closing: str = ")") -> int:
    depth = 0
    for i in range(start, len(text)):
        if text[i] == opening:
            depth += 1
        elif text[i] == closing:
            depth -= 1
            if depth == 0:
                return i
    raise ValueError(f"Unclosed {opening!r} in module declaration")


def _split_top_level(text: str, delimiter: str = ",") -> list[str]:
    out, start = [], 0
    paren = bracket = brace = 0
    for i, ch in enumerate(text):
        if ch == "(": paren += 1
        elif ch == ")": paren -= 1
        elif ch == "[": bracket += 1
        elif ch == "]": bracket -= 1
        elif ch == "{": brace += 1
        elif ch == "}": brace -= 1
        elif ch == delimiter and paren == bracket == brace == 0:
            out.append(text[start:i].strip()); start = i + 1
    out.append(text[start:].strip())
    return [x for x in out if x]


def _safe_int_expr(expr: str, env: dict[str, int]) -> int | None:
    """Evaluate a small, safe subset of integer parameter expressions."""
    expr = expr.strip().replace("'d", "")
    try:
        node = ast.parse(expr, mode="eval").body
    except SyntaxError:
        return None
    ops = {ast.Add: lambda a,b:a+b, ast.Sub:lambda a,b:a-b,
           ast.Mult:lambda a,b:a*b, ast.FloorDiv:lambda a,b:a//b,
           ast.Div:lambda a,b:a//b, ast.LShift:lambda a,b:a<<b,
           ast.RShift:lambda a,b:a>>b}
    def ev(n):
        if isinstance(n, ast.Constant) and isinstance(n.value, int): return n.value
        if isinstance(n, ast.Name): return env.get(n.id)
        if isinstance(n, ast.UnaryOp) and isinstance(n.op, (ast.USub, ast.UAdd)):
            v=ev(n.operand); return None if v is None else (-v if isinstance(n.op,ast.USub) else v)
        if isinstance(n, ast.BinOp) and type(n.op) in ops:
            a,b=ev(n.left),ev(n.right)
            if a is None or b is None or (isinstance(n.op,(ast.Div,ast.FloorDiv)) and b==0): return None
            try: return ops[type(n.op)](a,b)
            except (ArithmeticError, ValueError): return None
        return None
    return ev(node)


def _parameter_env(param_text: str) -> tuple[dict[str, str], dict[str, int]]:
    display, values = {}, {}
    for item in _split_top_level(param_text):
        m = re.search(r"(?:parameter|localparam)?\s*(?:integer|int|logic|bit|\[[^]]+\])?\s*([A-Za-z_]\w*)\s*=\s*(.+)$", item)
        if not m: continue
        name, expr = m.group(1), m.group(2).strip()
        display[name] = expr
        val = _safe_int_expr(expr, values)
        if val is not None: values[name] = val
    # Resolve simple forward references iteratively.
    for _ in range(len(display)):
        changed=False
        for k,v in display.items():
            val=_safe_int_expr(v,values)
            if val is not None and values.get(k)!=val: values[k]=val; changed=True
        if not changed: break
    return display, values


def _range_width(range_text: str, env: dict[str, int]) -> str:
    if not range_text: return "1"
    m = re.fullmatch(r"\[\s*(.*?)\s*:\s*(.*?)\s*\]", range_text.strip())
    if not m: return range_text.strip()
    hi = _safe_int_expr(m.group(1), env); lo = _safe_int_expr(m.group(2), env)
    if hi is not None and lo is not None: return str(abs(hi-lo)+1)
    return range_text.strip()


def parse_rtl(rtl_text: str, top: str | None = None) -> ModuleInterface:
    text = _strip_comments(rtl_text)
    mods = list(re.finditer(r"\bmodule\s+(?:automatic\s+|static\s+)?([A-Za-z_]\w*)\b", text))
    if not mods:
        return ModuleInterface(name=top or "unknown_dut", ambiguities=["No module declaration found."])
    selected = next((m for m in mods if m.group(1)==top), None) if top else mods[0]
    if selected is None:
        return ModuleInterface(name=top or "unknown_dut", ambiguities=[f"Requested top module {top!r} was not found."])
    name=selected.group(1); pos=selected.end(); params={}; env={}
    while pos<len(text) and text[pos].isspace(): pos+=1
    if pos<len(text) and text[pos]=='#':
        pos+=1
        while pos<len(text) and text[pos].isspace(): pos+=1
        if pos>=len(text) or text[pos]!='(':
            return ModuleInterface(name, ambiguities=["Could not parse parameter port list."])
        end=_matching(text,pos); params,env=_parameter_env(text[pos+1:end]); pos=end+1
    while pos<len(text) and text[pos].isspace(): pos+=1
    if pos>=len(text) or text[pos]!='(':
        return ModuleInterface(name, parameters=params, ambiguities=["Module header has no recognizable port list."])
    end=_matching(text,pos); header=text[pos+1:end]; body_start=end+1
    # Locate this module's end so non-ANSI declarations don't leak across modules.
    next_end=re.search(r"\bendmodule\b",text[body_start:])
    body=text[body_start:body_start+next_end.start()] if next_end else text[body_start:]
    items=_split_top_level(header)
    ports=[]; ambiguities=[]
    ansi=any(re.search(r"\b(input|output|inout)\b",x) for x in items)
    if ansi:
        direction=None; packed=""; dtype="logic"; signed=""
        for item in items:
            dm=re.search(r"\b(input|output|inout)\b",item)
            if dm:
                direction=dm.group(1)
                rest=item[dm.end():].strip()
                tm=re.match(r"(wire|reg|logic|bit|byte|shortint|int|integer|time)\b",rest)
                dtype=tm.group(1) if tm else "logic"
                if tm: rest=rest[tm.end():].strip()
                sm=re.match(r"(signed|unsigned)\b",rest)
                signed=sm.group(1) if sm else ""
                if sm: rest=rest[sm.end():].strip()
                rm=re.match(r"(\[[^]]+\])",rest)
                packed=rm.group(1) if rm else ""
                rest=rest[rm.end():].strip() if rm else rest
                nm=re.match(r"([A-Za-z_]\w*)",rest)
                if not nm:
                    ambiguities.append(f"Could not identify port name in declaration: {item}"); continue
                pname=nm.group(1)
            else:
                # ANSI shorthand: direction/range/type carry across commas.
                if direction is None:
                    ambiguities.append(f"Unrecognized ANSI port item: {item}"); continue
                rest=item.strip()
                rm=re.match(r"(\[[^]]+\])",rest)
                if rm: packed=rm.group(1); rest=rest[rm.end():].strip()
                nm=re.match(r"([A-Za-z_]\w*)",rest)
                if not nm:
                    ambiguities.append(f"Could not identify shorthand port name: {item}"); continue
                pname=nm.group(1)
            ports.append(Port(direction,_range_width(packed,env),pname,packed,dtype))
    else:
        names=[]
        for item in items:
            nm=re.match(r"\s*([A-Za-z_]\w*)",item)
            if nm: names.append(nm.group(1))
        decls={}
        for dm in re.finditer(r"\b(input|output|inout)\b\s*(?:(wire|reg|logic|bit|integer|int)\b\s*)?(?:\b(signed|unsigned)\b\s*)?(\[[^]]+\])?\s*([^;]+);",body):
            d,dt,sg,rng,namestr=dm.groups(); dt=dt or "logic"
            for nm in _split_top_level(namestr):
                match=re.match(r"\s*([A-Za-z_]\w*)",nm)
                if match: decls[match.group(1)]=(d,dt,rng or "")
        for pname in names:
            if pname not in decls:
                ambiguities.append(f"Non-ANSI port {pname!r} has no recognized direction declaration."); continue
            d,dt,rng=decls[pname]; ports.append(Port(d,_range_width(rng,env),pname,rng,dt))
    if not ports: ambiguities.append("No ports were extracted; verify the module header syntax.")
    unresolved=[p for p in ports if not p.width_is_resolved]
    if unresolved:
        ambiguities.append("Unresolved port widths: "+", ".join(f"{p.name}={p.packed_range}" for p in unresolved))
    return ModuleInterface(name,ports,params,ambiguities)


if __name__ == "__main__":
    import argparse
    from pathlib import Path
    ap=argparse.ArgumentParser(); ap.add_argument("rtl_file"); ap.add_argument("--top")
    args=ap.parse_args(); print(parse_rtl(Path(args.rtl_file).read_text(),args.top).as_prompt_block())
