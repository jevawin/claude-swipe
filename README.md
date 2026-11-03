# ClaudeSwipe

A macOS menu bar app that slides out a panel of your recent Claude Code chats, so you can see which ones are waiting on you.

Chats are grouped as:

- **Active**: anything you've touched in the last hour.
- **Waiting · today** and **Waiting · older**: chats that need a reply, split by when you last touched them.
- **Done**: finished chats, collapsed.

Each card shows the chat's status, folder, a one-line summary, and an emoji for the folder.

## Install

You need a Mac with Apple's command line tools. If `swiftc --version` fails, run `xcode-select --install` first.

```bash
git clone https://github.com/jevawin/claude-swipe.git
cd claude-swipe
./build.sh --run
```

This builds the app, installs it to `~/Applications/ClaudeSwipe.app` and opens it. A chat bubble icon appears in the menu bar. The app starts at login from then on; turn that off from the menu bar icon.

Optional: if the `claude` command-line tool is installed and signed in, the app uses Haiku to sort unclear chats and pick folder emojis. Without it, everything else still works.

## Use

- **Open**: push the cursor against the right edge of the screen, press ⌃⌥C, or click the menu bar icon.
- **Search**: start typing as soon as it opens. `acme` finds chats in an `acme` folder, `clients` finds every `clients/…` folder.
- **Open a chat**: click it, or press Enter for the top match. If the chat is already open in its own window, that window comes to the front.
- **Close**: move the cursor away, click elsewhere, or press Esc.

The first time you click a chat, macOS asks for Accessibility permission. That's what lets it bring the right window forward. If you skip it, chats still open in the main Claude window.

## Good to know

- It reads Claude's local chat files. The file formats aren't documented, so a Claude update could break it.
- The Haiku step sends the last message or two of an unclear chat, and your folder names, through your own `claude` login.
- After a rebuild, macOS may forget the Accessibility permission. Turn ClaudeSwipe off and on again in System Settings → Privacy and Security → Accessibility.
- Change a folder's emoji in `~/Library/Application Support/claude-swipe/folder-emoji.json`, under `"overrides"`. A key covers that folder and everything under it.
- Folder names are shown relative to `~/Developer` when chats live there.
