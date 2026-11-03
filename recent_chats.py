#!/usr/bin/env python3
"""List recent Claude Code chats, newest first, labelled waiting / done / running.

Sources (both undocumented, read-only):
- ~/.claude/projects/<dashed-cwd>/<cli-session-id>.jsonl   transcripts
- ~/Library/Application Support/Claude/claude-code-sessions/*/*/local_*.json
  desktop app metadata: title, cwd, isArchived, cliSessionId

Rules decide most chats. Ones the rules can't call go to Haiku in one batch
via `claude -p --model haiku --no-session-persistence`. Verdicts are cached
per transcript mtime, so re-runs only ask about changed chats.

Usage: recent_chats.py [--days N] [--no-ai] [--json]
"""
import argparse, glob, json, os, subprocess, sys, time
from pathlib import Path

HOME = str(Path.home())
PROJECTS = Path(HOME, ".claude/projects")
DESKTOP = Path(HOME, "Library/Application Support/Claude/claude-code-sessions")
CACHE = Path(HOME, "Library/Caches/claude-swipe/verdicts.json")
RUNNING_SECS = 90  # tool call or prompt with no reply younger than this = still working


def desktop_meta():
    """cliSessionId -> desktop metadata."""
    out = {}
    for f in DESKTOP.glob("*/*/local_*.json"):
        try:
            d = json.loads(f.read_text())
        except Exception:
            continue
        if d.get("cliSessionId"):
            out[d["cliSessionId"]] = d
    return out


def text_of(content):
    if isinstance(content, str):
        return content
    return "\n".join(b.get("text", "") for b in content if b.get("type") == "text")


def is_real_prompt(rec):
    """A user message typed (or sent) as a prompt, not a tool result."""
    c = rec.get("message", {}).get("content")
    if isinstance(c, str):
        return True
    return any(b.get("type") == "text" for b in c or []) and not any(
        b.get("type") == "tool_result" for b in c or [])


def read_turns(path):
    recs, meta = [], {"title": None, "cwd": None, "branch": None}
    with open(path, errors="replace") as fh:
        for line in fh:
            try:
                r = json.loads(line)
            except Exception:
                continue
            t = r.get("type")
            if t == "custom-title":
                meta["title"] = r.get("customTitle")
            elif t in ("user", "assistant") and not r.get("isSidechain"):
                recs.append(r)
                meta["cwd"] = r.get("cwd") or meta["cwd"]
                meta["branch"] = r.get("gitBranch") or meta["branch"]
    return recs, meta


def classify(recs, age):
    """Return (status, reason, needs_ai, context_for_ai)."""
    if not recs:
        return "empty", "", False, None
    last_prompt_i = max((i for i, r in enumerate(recs)
                         if r["type"] == "user" and is_real_prompt(r)), default=-1)
    prompt = text_of(recs[last_prompt_i]["message"]["content"]) if last_prompt_i >= 0 else ""
    turn = recs[last_prompt_i + 1:]
    if not turn:
        return ("running" if age < RUNNING_SECS else "stuck"), "prompt sent, no reply", False, None

    tool_uses, texts = [], []
    for r in turn:
        if r["type"] != "assistant":
            continue
        for b in r["message"].get("content", []):
            if b.get("type") == "tool_use":
                tool_uses.append(b)
            elif b.get("type") == "text" and b.get("text", "").strip():
                texts.append(b["text"].strip())

    for b in reversed(tool_uses):
        name, inp = b.get("name", ""), b.get("input", {})
        if name.endswith("wrap_up"):
            if inp.get("ask"):
                return "waiting", inp["ask"], False, None
            if recs[-1]["type"] == "assistant":
                return "done", inp.get("recap", ""), False, None
        if name in ("AskUserQuestion", "ExitPlanMode") and b is tool_uses[-1]:
            return "waiting", "question / plan approval", False, None

    last = recs[-1]
    if last["type"] == "user" or any(b.get("type") == "tool_use"
                                     for b in last["message"].get("content", [])):
        # Mid-turn: tool running, or a permission prompt / interruption.
        if age < RUNNING_SECS:
            return "running", "working", False, None
        return "stuck", "stopped mid-turn (permission prompt or interrupted?)", False, None

    final = texts[-1] if texts else ""
    if final.rstrip().endswith("?"):
        return "waiting", final.strip().splitlines()[-1][:160], False, None
    return "unsure", "", True, {"prompt": prompt[-600:], "reply": final[-1500:]}


def ask_haiku(items):
    """items: [{id, title, prompt, reply}] -> {id: (status, why)}"""
    instr = (
        "You triage chat sessions between a user and a coding assistant. For each one, "
        "decide whether the assistant's last reply leaves the user something to answer or "
        "decide (\"waiting\"), or whether the exchange reached a natural end (\"done\"). "
        "An offer like 'want me to do X?' counts as waiting. A plain report of finished "
        "work counts as done. Reply with ONLY a JSON array of "
        "{\"id\":..., \"status\":\"waiting\"|\"done\", \"why\":\"<12 words\"}.\n\n"
        + json.dumps(items, ensure_ascii=False))
    try:
        res = subprocess.run(
            ["claude", "-p", "--model", "haiku", "--no-session-persistence",
             "--output-format", "text"],
            input=instr, capture_output=True, text=True, timeout=180)
        raw = res.stdout.strip()
        raw = raw[raw.find("["): raw.rfind("]") + 1]
        return {x["id"]: (x["status"], x.get("why", "")) for x in json.loads(raw)}
    except Exception as e:
        print(f"[haiku failed: {e}]", file=sys.stderr)
        return {}


def folder_label(cwd, branch):
    if not cwd:
        return "?"
    if "/scratch-workspaces/" in cwd:
        return "(no folder)"
    p = cwd.replace(HOME + "/Developer/", "").replace(HOME, "~")
    if "/.claude/worktrees/" in p:
        repo, _, wt = p.partition("/.claude/worktrees/")
        p = f"{repo} @{branch or wt}"
    return p


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=float, default=3)
    ap.add_argument("--no-ai", action="store_true")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    now = time.time()
    meta = desktop_meta()
    cache = json.loads(CACHE.read_text()) if CACHE.exists() else {}
    rows, todo = [], []

    for f in glob.glob(str(PROJECTS / "*" / "*.jsonl")):
        mtime = os.path.getmtime(f)
        age = now - mtime
        if age > args.days * 86400:
            continue
        sid = Path(f).stem
        dm = meta.get(sid, {})
        if dm.get("isArchived"):
            continue
        recs, m = read_turns(f)
        status, why, needs_ai, ctx = classify(recs, age)
        if status == "empty":
            continue
        title = dm.get("title") or m["title"] or (ctx or {}).get("prompt", "")[:60] or sid[:8]
        row = {"id": sid, "status": status, "why": why, "title": title,
               "folder": folder_label(dm.get("cwd") or m["cwd"], m["branch"]),
               "age": age, "app": "desktop" if dm else "cli",
               "desktop_id": dm.get("sessionId"),
               "cwd": dm.get("cwd") or m["cwd"]}
        key = f"{sid}:{mtime}"
        if needs_ai:
            if key in cache:
                row["status"], row["why"] = cache[key]
            elif not args.no_ai:
                todo.append((row, key, {"id": sid, "title": title, **ctx}))
        rows.append(row)

    if todo:
        verdicts = ask_haiku([t[2] for t in todo])
        for row, key, _ in todo:
            if row["id"] in verdicts:
                row["status"], row["why"] = verdicts[row["id"]]
                row["why"] = "(ai) " + row["why"]
                cache[key] = [row["status"], row["why"]]
        CACHE.parent.mkdir(parents=True, exist_ok=True)
        CACHE.write_text(json.dumps(cache))

    order = {"waiting": 0, "stuck": 1, "unsure": 2, "running": 3, "done": 4}
    rows.sort(key=lambda r: (order.get(r["status"], 9), r["age"]))

    if args.json:
        print(json.dumps(rows, indent=1))
        return
    for r in rows:
        a = max(0, r["age"])
        age = f"{int(a // 60)}m" if a < 3600 else f"{int(a // 3600)}h" if a < 86400 else f"{int(a // 86400)}d"
        print(f"{r['status']:<8} {age:>4}  {r['folder'][:34]:<34}  {r['title'][:40]:<40}  {r['why'][:70]}")


if __name__ == "__main__":
    main()
