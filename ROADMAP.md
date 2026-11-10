# Roadmap

One item per session. Branch for each item, PR when ready, don't commit to `main`.

## Done

1. **Merged Kristina's PR #1** (status badges, subject emoji, window minimising, stable signing). Merge commit `8608e7c`. Her behaviour changes become settings in item 2.

## Next

2. **Settings panel and first-run screen.** *Largely built and merged in PR #3* (`Sources/Settings.swift`), which landed before this roadmap did. `Prefs` now covers theme, card icon, emoji on/off and source, home folder, minimise-others, AI model (Haiku or Sonnet) and a toggle per AI feature (`aiSort`, `aiClear`, `aiEmoji`), plus onboarding and a permission status light. Someone needs to walk the panel against the list below and strike what's done — I haven't checked the badge colour or the README. The original plan was: design first (21st.dev settings panels, Lucide icon), agree, then build. Settings:
   - Emoji position: on the status tile (badge) or as the tile with a status badge. Default: badge on the status tile. Later becomes icon position.
   - Emoji: on/off, source (folder or chat subject), model (Haiku or Sonnet).
   - Theme: auto, light, dark.
   - Window handling: minimise other Claude windows when opening a chat (needs Accessibility). Off by default.
   - Hide the folder chip for a home folder (replaces the `defaults write homeFolder` command).
   - "Ready to clear" badge: black doesn't show in dark mode, so it needs a new colour. The grouping behind it is item 7.
   - First-run screen: for each feature that needs a permission, show a short demo, what it needs, and an on/off choice.
   - Update the README for PR #1's features.
3. **Project structure for two people and their Claudes.** Clone `clumeral-game` and `pub-quiz` temporarily and review all their docs, not just `.clancy` (no longer used). A short `CLAUDE.md` that points to the right doc for each kind of work, a QA checklist, "always branch and PR", and when to use superpowers skills.
4. **Folder labels: project roots.** Plan and design properly first. Today's rules are hard-coded: strip `~/Developer/`, and (from PR #1) anything up to `/My Drive/` or `/iCloud~md~obsidian/Documents/`.
   - One list of project roots. The longest matching root is stripped.
   - Default roots: `~/Developer` if it exists, `~/Library/CloudStorage/<any>/` (plus `My Drive/` for Google Drive), `~/Library/Mobile Documents/<any app>/Documents/`. Google Drive and iCloud layouts are taken from PR #1's code, not checked on a real folder.
   - Users add their own roots in settings.
   - Only show `~` when the folder really sits under the home folder. Paths outside it (`/private/tmp`, `/Users/Shared/…`) stay absolute.
   - Long paths: decide how to shorten something like `~/Documents/Work/Clients/Client-A/Projects/A-Project/`. Options to weigh: keep the last two parts, collapse the middle (`~/Documents/…/A-Project`), or suggest a new root when many chats share a long prefix.
5. **Emoji from the opening of a chat.** Use the first three messages, not the last. PR #1 already uses the first prompt; extend it.
6. **Terminal and VS Code chats.** Parked: the list now shows desktop chats only, since the tool is for switching between them. If this comes back: Transcripts record `entrypoint`: `claude-desktop`, `claude-vscode` or `cli`. Better titles (first prompt, not the session ID), folder labels, a fitting open action for each, and decide whether a stopped terminal chat should show as blocked.
   - Show the source app's real icon next to the time ("10m ago in VS Code"), about 13pt.
   - Only show icons when the panel holds chats from more than one source. Someone who only uses VS Code sees no icons.
7. **Chat categorisation and sorting.** "Ready to clear" fires on chats that are still being worked: of the 10 verdicts that can be checked, 4 are premature (measured below). Make grouping a user choice, and tune the AI pass before trusting it.
   - How it works now, read from the code at `56fefdf`. Status has three sources, in order: the rules in `classify()`; the desktop app's own `postTurnSummary` when it covers the latest reply (`app_summary`, `recent_chats.py:129` — `completed` becomes `done` with no Haiku call); then Haiku for whatever is left (`ask_haiku`, `:161`, waiting vs done, gated by `--sort`).
   - "Ready to clear" is a *second* Haiku pass, over `done` chats only (`chat_extras`, `recent_chats.py:215`, gated by `--clear`). It gets the title, the first 300 characters and the last 600 — so "give it the first and last message" is what it does today, not the fix.
   - Sections are hard-coded in `section()` (`recent_chats.py:150`): active (touched under an hour ago), clear, done, today (under a day), older. The order dict is at `:421` and the sort key — section, then time touched — at `:422`. **This is the part that is genuinely still to do.**
   - Already built, so not work: the AI model choice (`--model haiku|sonnet`, `Prefs.aiModel`) and an off switch per AI feature (`aiSort`, `aiClear`, `aiEmoji`; `anyAI` at `Settings.swift:68`). Turning "Ready to clear" off is a toggle that exists today. `--clear` also gates whether *cached* finished verdicts apply (`:231`), which commit `29f2297` made deliberate for the fast pass — so the cache behaviour is intended, not a wart to work around.
   - **Measured 2026-11-07**, from the verdict cache (`~/Library/Caches/claude-swipe/verdicts.json`: 79 finished verdicts over 27 sessions), checked against the transcripts:
     - 28 verdicts came back `true`; 19 of 27 sessions got at least one.
     - 10 of those 28 have a later write visible. **5 were written to again within 30 minutes** (2.3, 10.3, 12.1, 15.9, 19.6 min), and **4 of the 5 are confirmed premature**: the next thing in the transcript is a prompt the user typed, classified with the script's own `is_real_prompt()`. One is a go-ahead to commit, two ask follow-up questions about the work in hand, one asks for a change. The 2.3-minute case is one of them.
     - The 5th (15.9 min) has no records after the verdict timestamp, so it stays unverified. A method artefact, not a clean case.
     - Gaps are upper bounds: judgements only run when the script runs, so the real next write can be sooner.
     - Two sessions show the judge reversing itself (`true`, then `false` later). `5b072b83` went `fffffffffffTTfffffffffTf` over 28 hours.
     - The other 18 `true` verdicts have no later judgement, so they can't be checked and may well be right. The claim is "4 of the 10 checkable verdicts are premature", not "the judge is wrong 70% of the time".
     - Checked and ruled out: two of these are background sessions, so a write after a verdict could have been an injected `<side-sessions-event>` rather than real work. It wasn't — all three short gaps on `5b072b83` carry typed prompts.
   - Mechanism: two routes reach `done` (the app's `postTurnSummary`, or the first Haiku pass) and both end at the same finished judge, which says `true` on 600 characters of tail even though its own prompt says "when unsure, false". Only 2 sessions have a confirmed premature verdict — one got `done` from Haiku, one from the rules or the app — so the sample is far too small to say which route is the bigger problem. Worth noting the first pass is *told* "A plain report of finished work counts as done" (`recent_chats.py:167`), and in a long iterative chat every intermediate report matches that; `5b072b83`'s cached reasons show that flip, from asking the user to test and report back (waiting) to confirming the work with no open question (done). Evidence for one session, not a general finding.
   - Chat length does **not** explain it, against my first guess. Median lines for ever-finished chats is 566 against 701 for never-finished — the wrong way round. All 6 chats over 1,500 lines did get a finished verdict, but no never-finished chat is longer than 1,127, so length can't be separated from group membership in this sample. Don't build on it.
   - Diagnostic for next time: `chat_extras` never writes `why`, so every chat in "Ready to clear" passed the finished judge regardless. `why` only says where its `done` came from — an `(ai)` prefix means the first Haiku pass, no prefix means the rules or the app. The cache is the better source: repeated `fin:` keys for one session id, plus the gap to the next write, find premature verdicts without waiting for one to happen.
   - Grouping, as a setting in item 2's panel: none (one flat list); recency (active, today, this week, older); folder, using item 4's labels; source app — desktop, VS Code, terminal, from item 6's `entrypoint`; alphabetical; Claude's status; smart (AI), the current behaviour, once tuned.
   - Sorting, separately: time touched (default) or title. Grouping picks the sections, sorting orders chats inside each one, so the two can't conflict. "None" is a single section.
   - The measurements above were taken against the code as it stood at `e35f252`, before PR #3 landed. Re-checked at `56fefdf`: the finished judge is behaviourally identical — same 300/600 inputs, same prompt wording, same `section()` thresholds — so the findings carry over. Only the line numbers moved.
   - Tuning levers to weigh, not decided: put turn count and chat age in the prompt (note the length finding below — don't assume length is the signal); send the last two or three exchanges instead of 600 characters; require explicit wrap-up language; a right-click "not finished" override stored like the emoji overrides (`App.swift:551`), which also builds a labelled set to tune against; Sonnet for this pass only.

## kevawin's ideas

In the order kevawin plans to build them, one branch and PR each. Items 11 to 13 first, then she'll reassess.

11. **Pin chats.** Some chats get reused every day and shouldn't drop into Done. Right-click a card to pin or unpin it. Pinned chats sit in their own section at the top and never move to Done or Ready to clear. Store pins by session ID, like the emoji overrides.
12. **Card size setting.** Compact, normal and large in Settings › Cards, changing font size, padding and tile size, so more chats fit (or fewer, bigger ones). Fixed sizes first; sizing to fit the screen could come later.
13. **Show linked chats.** A chat started from another one (a side session) should look related to its parent, even when the titles and emoji differ. For example, a shared outline colour on the emoji tile, or the child shown under its parent. The desktop metadata has fields such as `spawnSeed` and `lastSpawnRootDetected` that may hold the link (unchecked).
14. **Numbered sections on the welcome screen.** "Two optional extras" reads as one block, because both cards share the same shading. Number them 1 and 2, and give each card an orange outline in Claude's colours so they're clearly separate.
15. **Custom shortcut.** Let people choose their own hotkey in Settings › General instead of the fixed ⌃⌥C. The welcome screen's "Press Control-Option-C" line shows whatever is set, so rerunning the welcome screen after a change reminds you of your own shortcut.
16. **Turn off or rename sections, and drag chats between them.** Overlaps item 7, which already plans grouping as a setting (including "none"). Dragging a chat to another section would be a manual override, like item 7's right-click "not finished" idea. Agree the approach with item 7 before building.
17. **A new name (suggestion).** Something about switching, such as Claude Switcher, since the app is for switching between chats and windows. Jamie's call. Changing the bundle ID would reset everyone's window permission, so the display name might change without it.

## Later

8. **Icon library** (Lucide) as an alternative to emojis.
9. **Trackpad edge swipe.** Parked while you test the cursor-edge trigger.
10. **Signing with an Apple Developer certificate**, once the account exists. The self-signed "ClaudeSwipe Local" option from PR #1 stays until then.

## Parked

- **Archive from the panel.** Not possible from outside the Claude app: it rewrites session files from memory (tested 2026-11-03). Revisit if Claude adds an archive deep link.
