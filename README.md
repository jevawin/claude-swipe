# ClaudeSwipe

A macOS menu bar app that slides out a full-height panel of your recent Claude Code chats on the right of the screen, so you can see which ones are waiting on you.

Chats are grouped as:

- **Pinned**: chats you pinned, always at the top.
- **Active**: anything you've touched in the last hour.
- **Waiting · today** and **Waiting · older**: chats that need you, split by when you last touched them.
- **Done**: finished chats, shown faded. Click the header to collapse it.
- **Ready to clear**: done chats where the whole job is finished, so you can archive them. They sit under Done, faded a step further. Only shown if you turn it on in Settings › AI.

Each row shows a round icon, the chat's title, a one-line summary, how long ago you touched it, and its folder. The folder is the shortest name no other chat shares: `bookmygarage`, but `clients/acme` and `personal/acme` when both are there. Hover over it for the full path.

The icon's colour tells you what the chat needs:

- Blue: running.
- Amber: waiting for your answer.
- Red: blocked, for example on a permission prompt. It needs a click to carry on.
- Green: done.
- Faded green: ready to clear. A done chat the AI thinks is finished with.
- Grey: stuck or unsure.

The symbol inside is the chat's topic icon (an SF Symbol, such as a banknote or a hammer) if it has one. Otherwise it's the state's own symbol: dots, question mark, cross, tick, box, exclamation mark or dotted circle.

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
- **Pin a chat**: right-click it and pick "Pin". Pinned chats stay at the top and never move to Done or Ready to clear, even if you haven't opened them in a week. Right-click and pick "Unpin" to put it back.
- **Change a chat's topic icon**: right-click it and pick "Change topic icon…". Your pick always wins.
- **Close**: move the cursor away, click elsewhere, or press Esc.
- **Settings**: click the sliders button in the search bar, pick "Settings…" from the menu bar icon, or press ⌘, while the panel is open.

## Settings

- **General**: launch at login, and a button to show the welcome screen again.
- **Appearance**: theme (auto, light or dark); background (Solid, Frosted, or Glass on macOS 26 and later); how see-through the panel is; and density (Cozy shows each chat's summary, Compact fits more chats on one line each). Reduce transparency or Increase contrast in macOS forces Solid.
- **Cards**: whether topic icons come from the chat's subject or its folder, which folders' labels to hide (most people keep most chats in one or two folders) or a switch to hide them all, and how faint Done chats are.
- **Windows**: minimise other Claude windows when you open a chat. Hold Command or Option while you click a chat to flip this setting for that one click.
- **AI**: the model (Haiku or Sonnet), and three switches: sort unclear chats, let AI pick a topic icon for each chat, and the Ready to clear section. A Re-pick button asks again for every chat's topic icon.

## Two optional extras

**Jump to the right window** needs Accessibility permission. With it, clicking a chat that's already open in its own window brings that window to the front. Without it, the chat opens in the main Claude window. Allow it from the welcome screen or Settings › Windows. On macOS 27 it lives in System Settings › Privacy & Security › Device Control and Data Access; older macOS calls it Accessibility.

**AI features are off until you turn them on.** They use your own Claude plan. When chats are new or change, ClaudeSwipe sends small requests through your `claude` command-line login. They include each chat's title, your first and latest messages, and Claude's last reply. All of it counts against your plan. You need the `claude` command installed and signed in; Settings › AI shows whether it is.

## Good to know

- It reads Claude's local chat files. The file formats aren't documented, so a Claude update could break it.
- Results the AI already gave stay cached and still show if you turn a switch off. Turning it off only stops new requests.
- Without a signing certificate, every rebuild makes macOS forget the window permission. Run `./make-cert.sh` once: it adds a "ClaudeSwipe Local" certificate to your login keychain, and `build.sh` signs with it from then on. Then grant the permission one last time.
- If the permission still won't stick, look for other copies of ClaudeSwipe.app, such as a `build/` folder in another checkout. They share an ID, and System Settings may record the wrong copy. Delete them, run `tccutil reset Accessibility com.jevawin.claude-swipe`, and grant it again.
- To set a folder's topic icon by hand, edit `~/Library/Application Support/claude-swipe/folder-icons.json` under `"overrides"`. A key covers that folder and everything under it. The value must be a name from `icons.json`; anything else shows the state's symbol. These work with AI off.
- Folder names are shown relative to `~/Developer` when chats live there.
- `recent_chats.py` runs on its own too: `python3 recent_chats.py` lists your chats in a terminal and sends no requests. Add `--sort`, `--icon subject` or `--clear` to use AI; `--help` lists the rest.
