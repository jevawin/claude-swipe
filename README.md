# ClaudeSwipe

A macOS menu bar app that slides out a panel of your recent Claude Code chats, so you can see which ones are waiting on you.

Chats are grouped as:

- **Active**: anything you've touched in the last hour.
- **Waiting · today** and **Waiting · older**: chats that need you, split by when you last touched them.
- **Ready to clear**: done chats where the whole job is finished, so you can archive them. Only shown if you turn it on in Settings › AI.
- **Done**: finished chats, collapsed.

Each card shows the chat's status, folder, a one-line summary and an emoji. The status tile tells you what the chat needs:

- Blue dots: running.
- Amber question mark: waiting for your answer.
- Red cross: blocked, for example on a permission prompt. It needs a click to carry on.
- Green tick: done.
- Violet box: ready to clear.
- Grey: stuck or unsure.

## Install

You need a Mac with Apple's command line tools. If `swiftc --version` fails, run `xcode-select --install` first.

```bash
git clone https://github.com/jevawin/claude-swipe.git
cd claude-swipe
./build.sh --run
```

This builds the app, installs it to `~/Applications/ClaudeSwipe.app` and opens it. A chat bubble icon appears in the menu bar, and a welcome screen walks you through the two optional extras. The app starts at login from then on; turn that off in Settings › General.

## Use

- **Open**: push the cursor against the right edge of the screen, press ⌃⌥C, or click the menu bar icon.
- **Search**: start typing as soon as it opens. `acme` finds chats in an `acme` folder, `clients` finds every `clients/…` folder.
- **Open a chat**: click it, or press Enter for the top match.
- **Change a chat's emoji**: right-click it and pick "Change emoji…". Your pick always wins.
- **Close**: move the cursor away, click elsewhere, or press Esc.
- **Settings**: click the sliders button in the panel header, pick "Settings…" from the menu bar icon, or press ⌘, while the panel is open.

## Settings

- **General**: theme (auto, light or dark), launch at login, and a button to show the welcome screen again.
- **Cards**: whether the status or the emoji is the big icon, whether to show emoji at all, whether emoji come from the chat's subject or its folder, and a folder whose label to hide (most people keep most chats in one folder).
- **Windows**: minimise other Claude windows when you open a chat. Hold Option while you click a chat to flip this setting for that one click.
- **AI**: the model (Haiku or Sonnet), and three switches: sort unclear chats, let AI pick emoji, and the Ready to clear section. A Re-pick button asks again for every chat's emoji.

## Two optional extras

**Jump to the right window** needs Accessibility permission. With it, clicking a chat that's already open in its own window brings that window to the front. Without it, the chat opens in the main Claude window. Allow it from the welcome screen or Settings › Windows. On macOS 27 it lives in System Settings › Privacy & Security › Device Control and Data Access; older macOS calls it Accessibility.

**AI features are off until you turn them on.** They use your own Claude plan. When chats are new or change, ClaudeSwipe sends small requests through your `claude` command-line login. They include each chat's title, your first and latest messages, and Claude's last reply. All of it counts against your plan. You need the `claude` command installed and signed in; Settings › AI shows whether it is.

## Good to know

- It reads Claude's local chat files. The file formats aren't documented, so a Claude update could break it.
- Results the AI already gave stay cached and still show if you turn a switch off. Turning it off only stops new requests.
- Without a signing certificate, every rebuild makes macOS forget the window permission. Run `./make-cert.sh` once: it adds a "ClaudeSwipe Local" certificate to your login keychain, and `build.sh` signs with it from then on. Then grant the permission one last time.
- To set a folder's emoji by hand, edit `~/Library/Application Support/claude-swipe/folder-emoji.json` under `"overrides"`. A key covers that folder and everything under it. These work with AI off.
- Folder names are shown relative to `~/Developer` when chats live there.
- `recent_chats.py` runs on its own too: `python3 recent_chats.py` lists your chats in a terminal and sends no requests. Add `--sort`, `--emoji subject` or `--clear` to use AI; `--help` lists the rest.
