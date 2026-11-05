# ClaudeSwipe settings and first-run: current draft copy

What the app is: a Mac menu bar app. It slides out a panel listing your recent Claude Code chats, grouped by whether they need you. Each chat is a card with a coloured status tile (running, waiting for you, blocked, done) and an emoji for what the chat is about.

Facts the copy must stay true to:
- Accessibility is a macOS permission (System Settings › Privacy and Security › Accessibility). With it, clicking a chat that is already open in its own (pop-out) window brings that window to the front. Without it, the chat opens in the main Claude window instead.
- "Minimise other Claude windows": after opening a chat, every other Claude window goes to the Dock. Off by default. Holding Option while clicking a chat flips the setting for that one click: if it's off, Option-click opens the chat AND minimises the others; if it's on, Option-click opens the chat and leaves the others alone.
- AI features run small requests through the person's own `claude` command-line login, so they count toward that person's Claude plan usage. They send a chat's title, its opening prompt and its last reply. Model is Haiku (default) or Sonnet. All AI features are off until the person turns them on.
- "Sort unclear chats": when simple rules can't tell whether a chat is waiting for you or finished, AI decides. Off: those chats show as "unsure".
- "Pick an emoji": AI picks one emoji per chat, based on what the chat is about (or per folder, if "Emoji from: Folder"). People can also right-click a chat and pick their own; their own pick always wins.
- "Ready to clear": an extra AI check on finished chats, asking whether the whole job is done, so the chat can be archived. Those chats get their own section.
- Re-pick: changing the model or the emoji source only affects new chats. Re-pick asks the AI again for every chat from the last 7 days. The person's own picks stay.
- "Hide folder label for": each card shows the chat's folder as a small label. Most people keep most chats in one folder, so hiding that one folder's label makes cards cleaner.

## Welcome step 1
- Title: Your Claude chats, one swipe away
- Body: ClaudeSwipe shows which chats are waiting on you, which are running and which are done. Three ways to open it:
- Push the cursor into the right edge / Hold it there for a moment and the panel slides out
- Press Control-Option-C / Works from any app. Press again to close.
- Click the menu bar icon / Settings live there too
- Button: Continue

## Welcome step 2
- Title: Two optional extras
- Body: Each needs something from your Mac. Skip either; you can change them later in Settings.
- Block 1 title: Jump to the right window
- Block 1 body: If a chat is already open in its own window, clicking it brings that window forward instead of reloading it in the main one.
- Picture captions: Before: chat buried / After: chat in front
- Needs line: Needs Accessibility permission / Button: Allow in System Settings
- Sub-switch: Also minimise other Claude windows / Keeps one chat on screen. Option-click does the opposite.
- Block 2 title: Sort unclear chats and pick emoji
- Block 2 body: When the rules can't tell if a chat needs you, Claude reads its opening prompt and last reply and decides. It can also pick each chat's emoji.
- Warning: This uses your own Claude plan. ClaudeSwipe sends small Haiku requests through your claude login whenever new or changed chats appear. They count toward your usage.
- Status lines: claude command found and signed in / found, not signed in / not found
- Switch: Use my Claude for sorting and emoji / Off until you turn it on. Model and details in Settings › AI.
- Buttons: Back / Continue

## Welcome step 3 (not yet written)
- Title, one line pointing to Settings for the rest, button that opens the panel.

## Settings › General
- Theme: Auto / Light / Dark
- Launch at login
- Welcome screen: Show again

## Settings › Cards
- Preview (label above a sample card)
- Card icon: Status first (Emoji as a small badge) / Emoji first (Status as a small badge)
- Show emoji / Off shows the status icon alone
- Emoji from: Chat subject / Folder — Picked by AI, so needs AI turned on. Right-click a chat to pick your own.
- Hide folder label for: None / Your main folder, so its chats look cleaner

## Settings › Windows
- Minimise other Claude windows / Hold Option when you click a chat to do the opposite
- Accessibility status: Accessibility allowed. Chats already open in their own window come to the front. / Not allowed + button Open System Settings

## Settings › AI
- Warning: These use your own Claude plan. ClaudeSwipe sends small Haiku requests through your claude login whenever new or changed chats appear. They count toward your usage. Each one sends a chat's title, opening prompt and last reply.
- Model: Haiku / Sonnet — Haiku is quicker and uses less of your plan
- Sort unclear chats — Off: they show as "unsure"
- Pick an emoji for each chat — Off: only emoji you pick yourself show
- Ready to clear section — One more check on done chats: is the whole job finished?
- Re-pick all emoji — Changing the model or emoji source only affects new chats. This asks Haiku again for every chat from the last 7 days, using your plan. Emoji you picked yourself stay. / Button: Re-pick…
- Re-pick confirm dialog (not yet written): says it uses your plan, the model, and how many chats.
- Status line: claude command found and signed in
