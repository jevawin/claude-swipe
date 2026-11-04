#!/usr/bin/env python3
"""List recent Claude Code chats, newest first, labelled running / waiting /
blocked / done / finished, each with a subject emoji.

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
CHAT_EMOJI = Path(HOME, "Library/Application Support/claude-swipe/chat-emoji.json")  # "overrides" set from the panel
HAIKU_BATCH = 30
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
        # Slash commands like /login log these, but they aren't prompts.
        return not c.lstrip().startswith(("<local-command-", "<command-name>"))
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
    if not any(r["type"] == "user" and is_real_prompt(r) for r in recs):
        return "empty", "", False, None  # nothing typed, e.g. only /login
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
            if inp.get("ask") or inp.get("blocked"):
                return "waiting", inp.get("ask") or inp.get("recap", ""), False, None
            if recs[-1]["type"] == "assistant":
                # No ask, but the closing message can still put questions to the user.
                final = texts[-1] if texts else ""
                if "?" not in final:
                    return "done", inp.get("recap", ""), False, None
                return "unsure", "", True, {"prompt": prompt[-600:], "reply": final[-1500:]}
        if name in ("AskUserQuestion", "ExitPlanMode") and b is tool_uses[-1]:
            return "blocked", "question / plan approval", False, None

    last = recs[-1]
    if last["type"] == "user" or any(b.get("type") == "tool_use"
                                     for b in last["message"].get("content", [])):
        # Mid-turn: tool running, or a permission prompt / interruption.
        if age < RUNNING_SECS:
            return "running", "working", False, None
        return "blocked", "stopped mid-turn (permission prompt or interrupted?)", False, None

    final = texts[-1] if texts else ""
    if final.rstrip().endswith("?"):
        return "waiting", final.strip().splitlines()[-1][:160], False, None
    return "unsure", "", True, {"prompt": prompt[-600:], "reply": final[-1500:]}


def app_summary(dm, recs):
    """The desktop app's own post-turn verdict, if it covers the latest reply.

    Measured 2026-11-03: postTurnSummary.status_category is one of completed,
    blocked or review_ready; postTurnSummaryFor names the assistant message it
    summarises. Undocumented, so anything else falls back to our rules.
    """
    p = dm.get("postTurnSummary") or {}
    last = recs[-1] if recs else None
    if not p or not last or last["type"] != "assistant":
        return None
    if dm.get("postTurnSummaryFor") != last.get("uuid"):
        return None
    cat = p.get("status_category")
    if cat in ("blocked", "review_ready"):
        return "waiting", p.get("needs_action") or p.get("status_detail", "")
    if cat == "completed":
        return "done", p.get("status_detail", "")
    return None


def section(status, engaged):
    """Group by when you last touched the chat, then by whether it needs you."""
    if engaged < 3600:
        return "active"
    if status == "finished":
        return "clear"
    if status == "done":
        return "done"
    return "today" if engaged < 86400 else "older"


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
        raw = haiku(instr)
        raw = raw[raw.find("["): raw.rfind("]") + 1]
        return {x["id"]: (x["status"], x.get("why", "")) for x in json.loads(raw)}
    except Exception as e:
        print(f"[haiku failed: {e}]", file=sys.stderr)
        return {}


def haiku(prompt):
    res = subprocess.run(
        ["claude", "-p", "--model", "haiku", "--no-session-persistence",
         "--output-format", "text"],
        input=prompt, capture_output=True, text=True, timeout=180)
    return res.stdout.strip()


def first_prompt(recs):
    return next((text_of(r["message"]["content"]) for r in recs
                 if r["type"] == "user" and is_real_prompt(r)), "")


def last_reply(recs):
    for r in reversed(recs):
        if r["type"] == "assistant":
            t = text_of(r["message"].get("content", []))
            if t.strip():
                return t.strip()
    return ""


def load_chat_emoji():
    try:
        d = json.loads(CHAT_EMOJI.read_text())
    except Exception:
        d = {}
    return {"overrides": d.get("overrides", {}), "auto": d.get("auto", {})}


def chat_extras(rows, info, cache, use_ai):
    """Per-chat subject emoji (picked once; your overrides win) and, for done
    chats, whether the whole piece of work is finished and ready to clear.
    Finished verdicts are cached per transcript mtime, like status verdicts."""
    data = load_chat_emoji()
    todo = []
    for r in rows:
        fkey = "fin:" + info[r["id"]]["key"]
        if r["status"] == "done" and cache.get(fkey):
            r["status"] = "finished"
        pick = r["id"] not in data["overrides"] and r["id"] not in data["auto"]
        judge = r["status"] == "done" and fkey not in cache
        if use_ai and (pick or judge):
            item = {"id": r["id"], "title": r["title"],
                    "opening": info[r["id"]]["opening"][:300],
                    "pick_emoji": pick, "judge_finished": judge}
            if judge:
                item["last_reply"] = info[r["id"]]["reply"][-600:]
            todo.append((r, fkey, item))

    picked = {}
    for i in range(0, len(todo), HAIKU_BATCH):
        batch = todo[i:i + HAIKU_BATCH]
        prompt = (
            "You label chat sessions between a user and an AI assistant. For each item:\n"
            "- If pick_emoji is true, choose ONE emoji for the chat's subject: what the work "
            "is about, not the app or tool it happens in. Writing a LinkedIn post -> a writing "
            "emoji; tidying contacts -> a contacts emoji; an invoice -> a receipt emoji. Avoid "
            "generic picks (computer, robot, speech bubble, tick). Chats on different subjects "
            "should get different emojis.\n"
            "- If judge_finished is true, read last_reply and decide whether the whole piece of "
            "work is wrapped up, so the chat could be archived (true), or whether it is a pause "
            "between steps, with a follow-up offered or more to come (false). Later batches, stages "
            "or phases, or anything left for the user to review, tick, approve or decide, mean "
            "false. When unsure, false.\n"
            "Reply with ONLY a JSON array of {\"id\":..., \"emoji\":\"...\" (only if asked), "
            "\"finished\":true|false (only if asked)}.\n\n"
            + json.dumps([b[2] for b in batch], ensure_ascii=False))
        try:
            raw = haiku(prompt)
            out = {x["id"]: x for x in json.loads(raw[raw.find("["): raw.rfind("]") + 1])}
        except Exception as e:
            print(f"[haiku extras failed: {e}]", file=sys.stderr)
            continue
        for r, fkey, item in batch:
            x = out.get(r["id"], {})
            if item["pick_emoji"] and x.get("emoji"):
                picked[r["id"]] = x["emoji"]
            if item["judge_finished"] and "finished" in x:
                cache[fkey] = bool(x["finished"])
                if x["finished"]:
                    r["status"] = "finished"

    if picked:
        # Re-read first so an override set from the panel meanwhile isn't lost.
        fresh = load_chat_emoji()
        fresh["auto"].update(picked)
        CHAT_EMOJI.parent.mkdir(parents=True, exist_ok=True)
        CHAT_EMOJI.write_text(json.dumps(fresh, indent=1, ensure_ascii=False))
        data = fresh
    for r in rows:
        r["emoji"] = data["overrides"].get(r["id"]) or data["auto"].get(r["id"])
    return bool(todo)


def folder_label(cwd, branch):
    if not cwd:
        return "?"
    if "/scratch-workspaces/" in cwd:
        return "(no folder)"
    for root in ("/My Drive/", "/iCloud~md~obsidian/Documents/"):
        if root in cwd:
            return cwd.split(root, 1)[1]
    p = cwd.replace(HOME + "/Developer/", "").replace(HOME, "~")
    if "/.claude/worktrees/" in p:
        repo, _, wt = p.partition("/.claude/worktrees/")
        p = f"{repo} @{branch or wt}"
    return p


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=float, default=7)
    ap.add_argument("--no-ai", action="store_true")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    now = time.time()
    meta = desktop_meta()
    cache = json.loads(CACHE.read_text()) if CACHE.exists() else {}
    rows, todo, info = [], [], {}

    for f in glob.glob(str(PROJECTS / "*" / "*.jsonl")):
        mtime = os.path.getmtime(f)
        age = now - mtime
        if age > args.days * 86400:
            continue
        sid = Path(f).stem
        dm = meta.get(sid, {})
        if dm.get("isArchived") or dm.get("scheduledTaskId"):
            continue  # scheduled tasks run themselves; not chats to swipe
        recs, m = read_turns(f)
        status, why, needs_ai, ctx = classify(recs, age)
        if status == "empty":
            continue
        verdict = app_summary(dm, recs)
        if verdict and status not in ("running", "stuck", "blocked"):
            (status, why), needs_ai = verdict, False
        # Engagement: last time you looked at it, wrote in it, or Claude wrote in it.
        touched = max(mtime, float(dm.get("lastFocusedAt") or 0) / 1000,
                      float(dm.get("latestUserFrameAt") or 0) / 1000)
        title = dm.get("title") or m["title"] or (ctx or {}).get("prompt", "")[:60] or sid[:8]
        row = {"id": sid, "status": status, "why": why, "title": title,
               "folder": folder_label(dm.get("cwd") or m["cwd"], m["branch"]),
               "age": age, "engaged": now - touched, "app": "desktop" if dm else "cli",
               "desktop_id": dm.get("sessionId"),
               "cwd": dm.get("cwd") or m["cwd"]}
        key = f"{sid}:{mtime}"
        info[sid] = {"key": key, "opening": first_prompt(recs), "reply": last_reply(recs)}
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

    asked = chat_extras(rows, info, cache, not args.no_ai)
    if todo or asked:
        CACHE.parent.mkdir(parents=True, exist_ok=True)
        CACHE.write_text(json.dumps(cache))

    for r in rows:
        r["section"] = section(r["status"], r["engaged"])
    order = {"active": 0, "today": 1, "older": 2, "clear": 3, "done": 4}
    rows.sort(key=lambda r: (order[r["section"]], r["engaged"]))

    if args.json:
        print(json.dumps(rows, indent=1))
        return
    for r in rows:
        a = max(0, r["engaged"])
        age = f"{int(a // 60)}m" if a < 3600 else f"{int(a // 3600)}h" if a < 86400 else f"{int(a // 86400)}d"
        print(f"{r['section']:<6} {r['status']:<8} {age:>4}  {r['folder'][:30]:<30}  {r['title'][:38]:<38}  {r['why'][:60]}")


if __name__ == "__main__":
    main()
