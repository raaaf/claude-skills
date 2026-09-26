#!/usr/bin/env python3
"""
Token/cost usage report across recent Claude Code sessions.

Reads session transcripts from ~/.claude/projects/*/*.jsonl (main session
transcripts) plus each session's subagent transcripts under
~/.claude/projects/*/<session-id>/**/*.jsonl, and reports a weighted usage
total, the top sessions by usage, a per-tool-group breakdown, and subagent
types by count and weighted cost.

Weights (input=1, cache read=0.1, cache write=2, output=5) approximate
relative $ cost per token class, not raw token counts.

Usage:
  python3 scripts/usage-report.py --days 7 [--exclude SESSION_ID]
"""
import argparse
import collections
import glob
import json
import os
import time

PROJECTS_DIR = os.path.expanduser('~/.claude/projects')


def weighted_usage(u):
    return (
        u.get('input_tokens', 0)
        + 0.1 * u.get('cache_read_input_tokens', 0)
        + 2 * u.get('cache_creation_input_tokens', 0)
        + 5 * u.get('output_tokens', 0)
    )


def tool_group(name):
    if name.startswith('mcp__claude-in-chrome'):
        return 'Chrome'
    if name.startswith('mcp__'):
        return name.split('__')[1]
    if name in ('WebSearch', 'WebFetch'):
        return 'Web'
    if name in ('Read', 'Edit', 'Write', 'Grep', 'Glob', 'MultiEdit', 'NotebookEdit'):
        return 'Files'
    if name == 'Bash':
        return 'Bash'
    if name in ('Agent', 'Task', 'Workflow'):
        return 'Subagent calls'
    if name == 'Skill':
        return 'Skills'
    return 'Other tools'


def analyze(path):
    """Reads one transcript file, returns (total_weighted, turn_count, group_breakdown) or None."""
    try:
        lines = [json.loads(l) for l in open(path) if l.strip()]
    except (OSError, json.JSONDecodeError):
        return None

    turns = []
    seen_ids = set()
    tool_names = {}
    pending = []  # (turn_index_at_call, group, approx_char_size)

    for entry in lines:
        message = entry.get('message') or {}
        if entry.get('type') == 'assistant':
            for c in message.get('content') or []:
                if isinstance(c, dict) and c.get('type') == 'tool_use':
                    tool_names[c['id']] = c['name']
            usage = message.get('usage')
            msg_id = message.get('id')
            if usage and msg_id not in seen_ids:
                seen_ids.add(msg_id)
                turns.append(usage)
        elif entry.get('type') == 'user':
            content = message.get('content')
            for c in content if isinstance(content, list) else []:
                if isinstance(c, dict) and c.get('type') == 'tool_result':
                    size = len(json.dumps(c.get('content'))) / 4  # rough token estimate
                    pending.append((len(turns), tool_group(tool_names.get(c.get('tool_use_id'), '?')), size))

    if not turns:
        return None

    total = sum(weighted_usage(u) for u in turns)
    n = len(turns)
    groups = collections.Counter()

    # First turn's input establishes the system-prompt/instructions baseline, paid once at full
    # price then again at cache-read price on every later turn.
    base = (turns[0].get('input_tokens', 0)
            + turns[0].get('cache_read_input_tokens', 0)
            + turns[0].get('cache_creation_input_tokens', 0))
    groups['Instructions'] = base * 2 + base * 0.1 * (n - 1)

    for called_at_turn, group, size in pending:
        # A tool result gets re-read (cache read) on every subsequent turn.
        groups[group] += size * 2 + size * 0.1 * max(0, n - called_at_turn - 1)

    groups['Claude output'] = sum(5 * u.get('output_tokens', 0) for u in turns)

    rest = total - sum(groups.values())
    if rest < 0:
        # Estimate overshot the real total; rescale proportionally.
        scale = total / sum(groups.values())
        groups = collections.Counter({k: v * scale for k, v in groups.items()})
    else:
        groups['Conversation/other'] = rest

    return total, n, groups


def project_label(session_file):
    project_dir = session_file.split(os.sep)[-2]
    return project_dir.replace('-Users-rafael-', '')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--days', type=int, default=7, help='look back this many days (default 7)')
    parser.add_argument('--exclude', default=None, help='session id substring to exclude (e.g. the running session)')
    args = parser.parse_args()

    cutoff = time.time() - args.days * 86400
    rows = []
    totals = collections.Counter()
    subagent_cost = collections.Counter()
    subagent_count = collections.Counter()

    for session_file in glob.glob(os.path.join(PROJECTS_DIR, '*', '*.jsonl')):
        if os.path.getmtime(session_file) < cutoff:
            continue
        if args.exclude and args.exclude in session_file:
            continue
        result = analyze(session_file)
        if not result:
            continue
        total, n, groups = result
        session_dir = session_file[:-len('.jsonl')]

        sub_total = 0
        sub_count = 0
        for sub_file in glob.glob(os.path.join(session_dir, '**', '*.jsonl'), recursive=True):
            sub_result = analyze(sub_file)
            if not sub_result:
                continue
            sub_total += sub_result[0]
            sub_count += 1
            meta_path = sub_file[:-len('.jsonl')] + '.meta.json'
            try:
                agent_type = json.load(open(meta_path)).get('agentType', '?')
            except (OSError, json.JSONDecodeError):
                agent_type = '?'
            subagent_cost[agent_type] += sub_result[0]
            subagent_count[agent_type] += 1

        totals.update(groups)
        totals['Subagents'] += sub_total
        rows.append((
            total + sub_total,
            project_label(session_file),
            n,
            total,
            sub_count,
            sub_total,
            groups.most_common(1)[0][0] if groups else '-'
        ))

    rows.sort(reverse=True)

    print('TOTAL weighted usage:', round(sum(r[0] for r in rows) / 1e6, 1), 'M, sessions:', len(rows))
    print()
    print('Top sessions:')
    for r in rows[:12]:
        print(f"{r[0] / 1e6:6.1f}M {r[1][:40]:40} turns={r[2]:4} main={r[3] / 1e6:.1f}M "
              f"subs={r[4]} ({r[5] / 1e6:.1f}M) top={r[6]}")

    print()
    print('Group breakdown:')
    total_all = sum(totals.values()) or 1
    for group, value in totals.most_common():
        print(f"{group:22}{value / 1e6:7.1f}M {100 * value / total_all:4.0f}%")

    print()
    print('Subagent types (count, weighted cost):')
    for agent_type, cost in subagent_cost.most_common(10):
        print(f"{agent_type:25}{subagent_count[agent_type]:4}x {cost / 1e6:6.1f}M")


if __name__ == '__main__':
    main()
