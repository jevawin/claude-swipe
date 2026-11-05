#!/usr/bin/env python3
"""List recent Claude Code chats, newest first, labelled running / waiting /
blocked / done / finished, each with a subject emoji.

Sources (both undocumented, read-only):
- ~/.claude/projects/<dashed-cwd>/<cli-session-id>.jsonl   transcripts
- ~/Library/Application Support/Claude/claude-code-sessions/*/*/local_*.json
  desktop app metadata: title, cwd, isArchived, cliSessionId

Rules decide most chats. With --sort, ones the rules can't call go to the
model in one batch via `claude -p --model <model> --no-session-persistence`.
Verdicts are cached per transcript mtime, so re-runs only ask about changed
chats. Every AI call is opt-in: a bare run sends no requests.

Usage: recent_chats.py [--days N] [--json] [--model haiku|sonnet] [--sort]
       [--emoji off|subject|folder] [--emoji-from subject|folder] [--clear]
       [--repick] [--no-ai]
"""
import argparse, glob, json, os, subprocess, sys, time
from pathlib import Path

HOME = str(Path.home())
PROJECTS = Path(HOME, ".claude/projects")
DESKTOP = Path(HOME, "Library/Application Support/Claude/claude-code-sessions")
CACHE = Path(HOME, "Library/Caches/claude-swipe/verdicts.json")
CHAT_EMOJI = Path(HOME, "Library/Application Support/claude-swipe/chat-emoji.json")  # "overrides" set from the panel
FOLDER_EMOJI = Path(HOME, "Library/Application Support/claude-swipe/folder-emoji.json")  # edit "overrides" to taste
MODEL = "haiku"  # set from --model
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
        ["claude", "-p", "--model", MODEL, "--no-session-persistence",
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


def save_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=1, ensure_ascii=False))


def chat_extras(rows, info, cache, pick_emoji, clear, judge_new, repick):
    """Per-chat subject emoji (picked once; your overrides win) and, with
    clear, whether a done chat's whole piece of work is finished. Cached
    finished verdicts apply whenever clear is on; judge_new asks about the rest.
    Finished verdicts are cached per transcript mtime, like status verdicts.
    Returns {id: emoji} for the subject source (your picks, then auto)."""
    data = load_chat_emoji()
    if repick and pick_emoji:
        ids = {r["id"] for r in rows}
        data["auto"] = {k: v for k, v in data["auto"].items() if k not in ids}
        fresh = load_chat_emoji()
        fresh["auto"] = {k: v for k, v in fresh["auto"].items() if k not in ids}
        save_json(CHAT_EMOJI, fresh)
    todo = []
    for r in rows:
        fkey = "fin:" + info[r["id"]]["key"]
        if clear and r["status"] == "done" and cache.get(fkey):
            r["status"] = "finished"
        pick = pick_emoji and r["id"] not in data["overrides"] and r["id"] not in data["auto"]
        judge = clear and judge_new and r["status"] == "done" and fkey not in cache
        if pick or judge:
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
            print(f"[ai extras failed: {e}]", file=sys.stderr)
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
        save_json(CHAT_EMOJI, fresh)
        data = fresh
    return {r["id"]: data["auto"].get(r["id"]) for r in rows}, data["overrides"], bool(todo)


def folder_emojis(folders, use_ai, repick):
    """folder label -> (emoji, yours). Your overrides win (longest prefix
    match), then AI picks, which are cached so each folder is asked about once."""
    data = json.loads(FOLDER_EMOJI.read_text()) if FOLDER_EMOJI.exists() else {
        "overrides": {"(no folder)": "💭"}, "auto": {}}
    over, auto = data.setdefault("overrides", {}), data.setdefault("auto", {})

    def from_override(f):
        hits = [k for k in over if f == k or f.startswith(k + "/")]
        return over[max(hits, key=len)] if hits else None

    if repick and use_ai:
        for f in folders:
            auto.pop(f, None)
        save_json(FOLDER_EMOJI, data)
    missing = sorted({f for f in folders if not from_override(f) and f not in auto})
    if missing and use_ai:
        prompt = (
            "Pick one emoji for each project folder so a person can spot it at a glance. "
            "Folders under clients/ are client brands: evoke the brand name literally "
            "(blue-heron -> a bird, red-fox -> a fox). Personal projects: "
            "evoke what the name suggests. Avoid giving two folders the same emoji. "
            "Reply with ONLY a JSON object of {folder: emoji}.\n\n" + json.dumps(missing))
        try:
            raw = haiku(prompt)
            auto.update({k: v for k, v in json.loads(raw[raw.find("{"): raw.rfind("}") + 1]).items()
                         if k in missing})
            save_json(FOLDER_EMOJI, data)
        except Exception as e:
            print(f"[ai folder emoji failed: {e}]", file=sys.stderr)
    out = {}
    for f in folders:
        o = from_override(f)
        out[f] = (o, True) if o else (auto.get(f), False)
    return out


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
    ap.add_argument("--no-ai", action="store_true", help="send no requests, whatever else is set")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--model", choices=["haiku", "sonnet"], default="haiku")
    ap.add_argument("--sort", action="store_true", help="AI decides chats the rules can't")
    ap.add_argument("--emoji", choices=["off", "subject", "folder"], default="off",
                    help="which emoji the AI picks")
    ap.add_argument("--emoji-from", choices=["subject", "folder"], default=None,
                    help="which saved emoji to show (default: --emoji, else subject)")
    ap.add_argument("--clear", action="store_true", help="AI marks done chats that are ready to clear")
    ap.add_argument("--repick", action="store_true", help="forget AI emoji picks in the window first")
    args = ap.parse_args()
    global MODEL
    MODEL = args.model
    ai = not args.no_ai
    source = args.emoji if args.emoji != "off" else (args.emoji_from or "subject")

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
            elif ai and args.sort:
                todo.append((row, key, {"id": sid, "title": title, **ctx}))
        rows.append(row)

    if todo:
        verdicts = ask_haiku([t[2] for t in todo])
        for row, key, _ in todo:
            if row["id"] in verdicts:
                row["status"], row["why"] = verdicts[row["id"]]
                row["why"] = "(ai) " + row["why"]
                cache[key] = [row["status"], row["why"]]

    auto, chat_over, asked = chat_extras(rows, info, cache, ai and args.emoji == "subject",
                                         args.clear, ai, args.repick)
    if source == "folder":
        fe = folder_emojis({r["folder"] for r in rows}, ai and args.emoji == "folder", args.repick)
    for r in rows:
        # A per-chat pick from the panel beats everything.
        if r["id"] in chat_over:
            r["emoji"], r["own_emoji"] = chat_over[r["id"]], True
        elif source == "folder":
            r["emoji"], r["own_emoji"] = fe[r["folder"]]
        else:
            r["emoji"], r["own_emoji"] = auto.get(r["id"]), False
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
