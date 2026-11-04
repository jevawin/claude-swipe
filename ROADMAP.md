# Roadmap

One item per session. Branch for each item, PR when ready, don't commit to `main`.

## Done

1. **Merged Kristina's PR #1** (status badges, subject emoji, window minimising, stable signing). Merge commit `8608e7c`. Her behaviour changes become settings in item 2.

## Next

2. **Settings panel and first-run screen.** Design first (21st.dev settings panels, Lucide icon), agree, then build. Settings:
   - Emoji position: on the status tile (badge) or as the tile with a status badge. Default: badge on the status tile. Later becomes icon position.
   - Emoji: on/off, source (folder or chat subject), model (Haiku or Sonnet).
   - Theme: auto, light, dark.
   - Window handling: minimise other Claude windows when opening a chat (needs Accessibility). Off by default.
   - Hide the folder chip for a home folder (replaces the `defaults write homeFolder` command).
   - "Ready to clear" section (an extra Haiku check on done chats). Its black badge needs a colour that shows in dark mode.
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
6. **Terminal and VS Code chats.** Transcripts record `entrypoint`: `claude-desktop`, `claude-vscode` or `cli`. Better titles (first prompt, not the session ID), folder labels, a fitting open action for each, and decide whether a stopped terminal chat should show as blocked.
   - Show the source app's real icon next to the time ("10m ago in VS Code"), about 13pt.
   - Only show icons when the panel holds chats from more than one source. Someone who only uses VS Code sees no icons.

## Later

7. **Icon library** (Lucide) as an alternative to emojis.
8. **Trackpad edge swipe.** Parked while you test the cursor-edge trigger.
9. **Signing with an Apple Developer certificate**, once the account exists. The self-signed "ClaudeSwipe Local" option from PR #1 stays until then.

## Parked

- **Archive from the panel.** Not possible from outside the Claude app: it rewrites session files from memory (tested 2026-11-03). Revisit if Claude adds an archive deep link.
