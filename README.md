# ClaudeSwipe

A slide-out panel of recent Claude Code chats, grouped by "waiting on you", "stuck", "working" and "done".

- Open: push the cursor against the right edge of the rightmost screen for 0.25s, or press ⌃⌥C, or use the menu bar icon.
- Close: move the cursor away, click elsewhere, or press Esc.
- Search: type as soon as it opens. Every word must match the title, folder or preview. Enter opens the top match, Esc clears.
- Click a desktop-app chat to open it (`claude://code/continue?session=local_…`). Click a terminal chat to copy a `claude -r` command.

## Build

```bash
./build.sh --run
```

This installs to `~/Applications/ClaudeSwipe.app` and launches it. The app turns on launch at login the first time it runs. Toggle it from the menu bar icon.

Needs Xcode's `swiftc` and `python3`. The Haiku pass uses the `claude` CLI on your login (`claude -p --model haiku --no-session-persistence`).

## How it labels chats

`recent_chats.py` reads `~/.claude/projects/*/*.jsonl` and the desktop app's `claude-code-sessions/*/*/local_*.json`. Both formats are undocumented and may change. Rules decide most chats. The rest go to Haiku in one batch, and verdicts are cached in `~/Library/Caches/claude-swipe/verdicts.json`.

## Not done yet

- Trackpad edge swipe. Needs BetterTouchTool or the private MultitouchSupport framework. Turn off the system gesture in System Settings → Trackpad → More Gestures → Notification Centre.
