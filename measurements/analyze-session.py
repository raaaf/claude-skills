#!/usr/bin/env python3
"""Analyze a Claude Code session JSONL and report audit-relevant metrics.

Usage:
  python3 analyze-session.py <path-to-session.jsonl>
  python3 analyze-session.py <path-to-session.jsonl> --baseline <path-to-baseline.jsonl>

Reports:
  - Tool-call breakdown (Edit, Agent, Bash, Read, Grep, ...)
  - Agent-dispatch count with target subagent types
  - Orchestrator Edit count (key metric for fix-agent-enforcement)
  - Round count (parses "Audit-Runde X/N" markers)
  - Token stats (fresh input, cache read, cache create, output)
  - Cost estimate (Opus 4.7 pricing)

Exit code 0 always. For use in terminal, not in automation pipelines.
"""

import json
import sys
import re
from collections import Counter
from pathlib import Path

# Opus 4.7 pricing per million tokens
PRICE_INPUT = 5.00
PRICE_CACHE_READ = 0.50
PRICE_CACHE_CREATE = 6.25
PRICE_OUTPUT = 25.00


def analyze(path: Path) -> dict:
    tool_calls = []
    agent_dispatches = []
    first_user = None
    last_text = None
    round_markers = []
    total_input = total_output = total_cache_read = total_cache_create = 0

    with path.open() as f:
        for line in f:
            line = line.strip()
            if not line or not line.startswith("{"):
                continue
            try:
                e = json.loads(line)
            except json.JSONDecodeError:
                continue

            t = e.get("type", "")
            msg = e.get("message", {})

            if t == "user" and first_user is None:
                c = msg.get("content", "")
                if isinstance(c, str):
                    first_user = c[:300]

            if t == "assistant":
                usage = msg.get("usage", {})
                total_input += usage.get("input_tokens", 0)
                total_output += usage.get("output_tokens", 0)
                total_cache_read += usage.get("cache_read_input_tokens", 0)
                total_cache_create += usage.get("cache_creation_input_tokens", 0)

                content = msg.get("content", [])
                if isinstance(content, list):
                    for c in content:
                        ctype = c.get("type", "")
                        if ctype == "tool_use":
                            name = c.get("name", "")
                            tool_calls.append(name)
                            if name == "Agent":
                                inp = c.get("input", {})
                                agent_dispatches.append(
                                    {
                                        "desc": inp.get("description", "")[:80],
                                        "subagent": inp.get("subagent_type", ""),
                                        "model": inp.get("model", "(inherit)"),
                                    }
                                )
                        elif ctype == "text":
                            txt = c.get("text", "")
                            if re.search(r"[Aa]udit[- ][Rr]unde\s+\d+|RUNDE \d+/\d", txt[:100]):
                                round_markers.append(txt[:120])
                            last_text = txt[:400]

    counts = Counter(tool_calls)
    cost = (
        total_input / 1_000_000 * PRICE_INPUT
        + total_cache_read / 1_000_000 * PRICE_CACHE_READ
        + total_cache_create / 1_000_000 * PRICE_CACHE_CREATE
        + total_output / 1_000_000 * PRICE_OUTPUT
    )
    unique_rounds = set()
    for m in round_markers:
        mo = re.search(r"(\d+)(?:\s*/\s*\d+)?", m)
        if mo:
            unique_rounds.add(int(mo.group(1)))

    return {
        "path": str(path),
        "first_user": first_user,
        "total_tool_calls": len(tool_calls),
        "tool_breakdown": dict(counts),
        "edit_count": counts.get("Edit", 0),
        "agent_dispatches": agent_dispatches,
        "agent_count": len(agent_dispatches),
        "rounds_observed": sorted(unique_rounds) or [None],
        "round_markers": round_markers[:10],
        "tokens": {
            "fresh_input": total_input,
            "cache_read": total_cache_read,
            "cache_create": total_cache_create,
            "output": total_output,
        },
        "cost_usd": cost,
        "last_text": last_text,
    }


def format_report(report: dict, label: str = "Session") -> str:
    lines = [f"=== {label} ===", f"Path: {report['path']}", ""]
    if report["first_user"]:
        lines.append(f"First user message: {report['first_user'][:120]}")
        lines.append("")

    lines.append(f"Total tool calls: {report['total_tool_calls']}")
    for name, n in sorted(report["tool_breakdown"].items(), key=lambda x: -x[1]):
        marker = "  <-- KEY METRIC" if name == "Edit" else ""
        lines.append(f"  {name:<20} {n:>4}{marker}")
    lines.append("")

    lines.append(f"Agent dispatches: {report['agent_count']}")
    for i, a in enumerate(report["agent_dispatches"][:15], 1):
        lines.append(f"  {i}. [{a['subagent']:>18}] model={a['model']:<20} {a['desc']}")
    if report["agent_count"] > 15:
        lines.append(f"  ... +{report['agent_count'] - 15} more")
    lines.append("")

    lines.append(f"Rounds observed: {report['rounds_observed']}")
    lines.append("")

    tok = report["tokens"]
    lines.append("Tokens:")
    lines.append(f"  Fresh input:   {tok['fresh_input']:>12,}")
    lines.append(f"  Cache read:    {tok['cache_read']:>12,}")
    lines.append(f"  Cache create:  {tok['cache_create']:>12,}")
    lines.append(f"  Output:        {tok['output']:>12,}")
    lines.append(f"  Est. cost:     ${report['cost_usd']:.2f} (Opus 4.7 pricing)")
    lines.append("")

    if report["last_text"]:
        lines.append(f"Last assistant text: {report['last_text']}")

    return "\n".join(lines)


def compare(current: dict, baseline: dict) -> str:
    lines = ["", "=== COMPARISON vs BASELINE ===", ""]
    lines.append(f"{'Metric':<25} {'Baseline':>12} {'Current':>12} {'Delta':>12}")
    lines.append("-" * 65)

    def row(label, a, b, fmt=str):
        try:
            delta = b - a
            delta_str = f"{delta:+d}" if isinstance(delta, int) else f"{delta:+.2f}"
        except TypeError:
            delta_str = "n/a"
        lines.append(f"{label:<25} {fmt(a):>12} {fmt(b):>12} {delta_str:>12}")

    row("Total tool calls", baseline["total_tool_calls"], current["total_tool_calls"])
    row("Edit (orchestrator)", baseline["edit_count"], current["edit_count"])
    row("Agent dispatches", baseline["agent_count"], current["agent_count"])
    row("Output tokens", baseline["tokens"]["output"], current["tokens"]["output"])
    row("Cache read tokens", baseline["tokens"]["cache_read"], current["tokens"]["cache_read"])
    row("Cost USD", baseline["cost_usd"], current["cost_usd"], fmt=lambda x: f"${x:.2f}")

    # Verdict on the fix-agent enforcement
    edits_delta = current["edit_count"] - baseline["edit_count"]
    lines.append("")
    lines.append("Verdict on fix-agent enforcement:")
    if current["edit_count"] < 5:
        lines.append("  GREEN: Orchestrator respects the rule (< 5 edits). Prompt-level enforcement sufficient.")
    elif current["edit_count"] < 15:
        lines.append("  YELLOW: Partial compliance (5-14 edits). Consider stronger prompt wording or a hook.")
    else:
        lines.append("  RED: Rule ignored (>= 15 edits). PreToolUse hook needed to enforce at the tool level.")

    return "\n".join(lines)


def main():
    args = sys.argv[1:]
    if not args or args[0] in ("-h", "--help"):
        print(__doc__)
        sys.exit(0)

    path = Path(args[0])
    if not path.exists():
        print(f"File not found: {path}", file=sys.stderr)
        sys.exit(1)

    report = analyze(path)
    print(format_report(report, label="Current session"))

    if len(args) >= 3 and args[1] == "--baseline":
        baseline_path = Path(args[2])
        if not baseline_path.exists():
            print(f"Baseline not found: {baseline_path}", file=sys.stderr)
            sys.exit(1)
        baseline_report = analyze(baseline_path)
        print("")
        print(format_report(baseline_report, label="Baseline"))
        print(compare(report, baseline_report))


if __name__ == "__main__":
    main()
