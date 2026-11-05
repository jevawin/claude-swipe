# Settings window and first-run screen

Roadmap item 2. Mockups: https://claude.ai/artifact/SsErnXKRwMk9FNcnMduse6 (layout A boards, first run, badges).

## Why

PR #1 (Kristina) changed several behaviours that Jamie had set differently: the emoji tile, chat-subject emoji, minimising other windows, a home folder, and the "Ready to clear" section. Settings let each person keep what they want. Jamie's choices are the defaults. A first-run screen explains the two features that need something from the Mac, and lets people opt in.

## Goals

- One Settings window, with a sidebar, ready to hold more settings later without a redesign.
- Every AI feature is off by default. People opt in from the first-run screen or Settings, after a clear warning that it uses their own Claude plan.
- Accessible from the start: real controls, no text over pictures, labelled images.

## Non-goals

- A design system (later), the Lucide icon library (roadmap 7), project roots (roadmap 4), changing the hotkey or turning off the edge trigger.

## Anti-goals

- AI requests that someone didn't knowingly turn on.
- Settings inside the chat panel. The panel hides when the cursor leaves or on any click elsewhere (`App.swift` `tick()` and the global mouse monitor), so a trip to System Settings would close it.

## Settings

Stored in `UserDefaults` (`com.jevawin.claude-swipe`).

| Pane | Setting | Key | Values | Default |
|---|---|---|---|---|
| General | Theme | `theme` | auto, light, dark | auto |
| General | Launch at login | (SMAppService) | on/off | on, as now |
| General | Show welcome again | (button) | | |
| Cards | Card icon | `cardIcon` | status, emoji | status |
| Cards | Show emoji | `showEmoji` | bool | true |
| Cards | Emoji from | `emojiSource` | subject, folder | subject |
| Cards | Hide folder label for | `homeFolder` | folder label or empty | empty (existing key, kept) |
| Windows | Minimise other Claude windows | `minimiseOthers` | bool | false |
| AI | Model | `aiModel` | haiku, sonnet | haiku |
| AI | Sort unclear chats | `aiSort` | bool | false |
| AI | Pick an emoji for each chat | `aiEmoji` | bool | false |
| AI | Ready to clear section | `aiClear` | bool | false |
| AI | Re-pick all emoji | (button) | | |
| (hidden) | First run done | `onboarded` | bool | false |

Behaviour:

- **Card icon "status"**: status-coloured tile with its SF Symbol, emoji as a small badge (pre-PR #1 look, commit 32e2acf). No emoji: no badge.
- **Card icon "emoji"**: PR #1's emoji tile with a status badge. No emoji: 💬, as now.
- **Show emoji off**: status tile, no badge. The Card icon row is greyed out.
- **Minimise off**: clicking a chat leaves other Claude windows alone; Option-click minimises them. On: the reverse, as in PR #1. Raising a chat's own window still happens either way when Accessibility is allowed.
- **Emoji from folder**: brings back `folder_emojis` from 32e2acf, using the existing `folder-emoji.json` (prefix overrides, then auto picks). A per-chat override set by right-click still wins.
- **Ready to clear off**: no "finished" judging and no Ready to clear section. Done chats stay in Done.
- **Ready to clear badge colour**: violet `hsl(262, 45, 58)` (#8764C4), replacing black, which vanishes on dark cards.
- **Theme**: sets `NSApp.appearance` (nil, aqua or darkAqua), which covers the panel and the Settings window.
- **Hide folder label for**: a menu of "None" plus the folder labels of current chats (plus the saved value if it's not among them).
- **Re-pick all emoji**: a confirm dialog says it uses your plan, names the model and how many chats it covers (last 7 days). Then it clears auto picks (subject: those chats' `auto` entries; folder: those folders' `auto` entries) and refreshes. Your own picks stay. Greyed out when AI emoji is off.
- Changing a setting the script uses triggers a refresh. Model and source changes only affect new picks; the AI pane says so next to Re-pick.

### AI warning

Shown at the top of the AI pane and on the first-run AI block. All user-facing text comes from [2026-11-05-settings-copy.md](2026-11-05-settings-copy.md), which overrides the mockups.

Under it, a status line from `claude auth status --json` (measured: returns `loggedIn`, 0.13s): "found and signed in", "found, not signed in" or "not found". The AI switches are disabled unless it's found and signed in.

## Script interface

The app passes settings to `recent_chats.py` as flags. The script never reads the defaults plist, so it stays testable from a terminal.

All AI flags are opt-in, so a bare run sends no requests.

- `--model haiku|sonnet` (default haiku). Used for all three AI calls.
- `--sort`: run the triage call. Without it, unclear chats stay "unsure". Cached verdicts are still used (no new requests). *(builder's call)*
- `--emoji off|subject|folder` (default `off`): which AI emoji pick runs. Off still shows your own per-chat picks.
- `--emoji-from subject|folder` (default subject): which saved emoji to show when `--emoji` is off.
- `--clear`: run the finished judge. Without it, cached finished verdicts are ignored too.
- `--repick`: clear auto picks for chats in the window (or their folders) before picking.
- `--no-ai` stays: the fast first pass, no requests at all, whatever else is passed.

Each row gains `own_emoji` (true when your own pick decides it), so the app can count chats for Re-pick. Old behaviour: `--sort --emoji subject --clear`.

## Settings window (layout A)

- An `NSWindow` hosting a SwiftUI view: sidebar (General, Cards, Windows, AI) and a pane. About 760×580, not resizable below that.
- Opens from a new button in the panel header (Lucide `settings-2`, drawn as a SwiftUI `Path`: two lines and two circles, 15pt, next to refresh) and "Settings…" (⌘,) in the menu bar menu. Opening it hides the panel and activates the app, since it runs as an accessory app.
- Cards pane starts with a live preview card that follows the settings.
- The Windows and AI panes start with the same blocks as first-run step 2 (pictures included), so people who skipped the welcome see something familiar. The permission state is re-checked every second while the window is open.
- macOS 27 lists the permission under Privacy & Security › Device Control and Data Access (reported by Jamie, not measured); older macOS calls it Accessibility. The copy names both.

## First-run screen

Same window type, three steps, shown at launch while `onboarded` is false. That includes existing installs once, after this update, so they can opt in to AI (it's now off by default).

1. **Welcome**: three ways to open the panel (edge, ⌃⌥C, menu bar).
2. **Two optional extras**, each with a before/after picture, captions below the picture (never over it), an accessibility label on the picture, what it needs, and a choice:
   - Jump to the right window: needs Accessibility. "Allow in System Settings" button (prompts, then opens the Accessibility pane). Sub-switch "Also minimise other Claude windows", off.
   - Sort unclear chats and pick emoji: the AI warning, the `claude` status line, and one switch "Use my Claude for sorting and emoji", off. On sets `aiSort` and `aiEmoji`; Ready to clear stays off (Settings only).
3. **You're set**: points to Settings for the rest, button to open the panel. Sets `onboarded`.

Closing the window at any step also sets `onboarded`. "Show welcome again" in General reopens it.

## Accessibility

- Native SwiftUI `Toggle`, segmented `Picker` and `Button`, so VoiceOver gets roles and labels.
- No text over pictures. Demo pictures carry an accessibility label.
- Secondary text keeps the existing `Theme.secondary` token. Check contrast on the warning box in both themes.

## README

Add PR #1's features (subject emoji, right-click Change emoji, status badges, blocked vs waiting, Ready to clear, minimising, Option-click) and the new Settings and first-run. Replace the `defaults write homeFolder` and `folder-emoji.json` notes with the settings that cover them. Say plainly that AI features are off until turned on, and what they send.

## Builder's calls (not discussed)

- Cached AI verdicts and cached emoji picks still show with the matching AI switch off. Showing them sends nothing. A fresh install has none.
- Folder source: per-chat override beats folder emoji. Your hand-edited prefix overrides in `folder-emoji.json` apply with AI off; only the auto picks need AI.
- The warning is one worst-case sentence, not tailored to each switch. The script keeps today's batching (emoji and finished judge share one call).
- Show emoji off with AI emoji on: the app passes `--emoji off`, so no picks are made while emoji are hidden.
- Show emoji off hides your own picks too. Right-click "Change emoji" stays.
- Re-pick covers the same 7 days as `--days`. The dialog's count comes from the last refresh: chats without your own pick (subject) or distinct folders without a prefix override (folder).
- Existing installs: AI is off from the update until you opt in, including for Jamie's current install. Closing the first-run window counts as done, with everything left off.
- Window size and exact copy, within the mockups.
- How the 1-second Accessibility check is done (timer while visible).
