# ClaudeSwipe settings and first-run: copy

Format: `Label / helper text`. Where a line has two parts, the first is the control name and the second is the helper text under it. On picker lines the options are separated by ` / ` and the helper text is tagged `Helper:`.

## Welcome step 1
- Title: Your Claude chats, one swipe away
- Body: ClaudeSwipe shows which chats are waiting for you, which are running and which are done. There are three ways to open it:
- Push the cursor into the right edge / Hold it there for a moment and the panel slides out
- Press Control-Option-C / Works from any app. Press again to close.
- Click the menu bar icon / Settings are there too
- Button: Continue

## Welcome step 2
- Title: Two optional extras
- Body: One needs a Mac permission. The other uses your Claude plan. You can skip either one and change your mind later in Settings.
- Block 1 title: Jump to the right window
- Block 1 body: If a chat is already open in its own window, clicking it brings that window to the front. Without this, the chat opens in the main Claude window instead.
- Picture captions: Before: chat hidden behind other windows / After: chat in front
- Needs line: Needs Accessibility permission, so ClaudeSwipe can bring windows to the front / Button: Allow in System Settings
- Sub-switch: Also minimise other Claude windows / When you open a chat, every other Claude window goes to the Dock. Hold Option while you click a chat to flip this setting for that one click.
- Block 2 title: Sort unclear chats and pick emoji
- Block 2 body: Sometimes ClaudeSwipe cannot tell if a chat needs you or is done. With this on, Claude reads your latest message and its last reply, and decides. It can also pick an emoji for each chat.
- Warning: This uses your own Claude plan. When chats are new or change, ClaudeSwipe sends small requests through your claude login. They include each chat's title, your first and latest messages, and Claude's last reply. All of it counts against your plan.
- Status lines: claude command found and signed in / claude command found but not signed in / claude command not found
- Switch: Use my Claude plan / Off until you turn it on. Pick the model and more in Settings › AI.
- Buttons: Back / Continue

## Welcome step 3
- Title: You're ready
- Body: Everything else lives in Settings. Open it from the menu bar icon.
- Button: Show my chats

## Settings › General
- Theme: Auto / Light / Dark
- Launch at login
- Welcome screen: Show again

## Settings › Cards
- Preview
- Card icon: Status first (emoji as a small badge) / Emoji first (status as a small badge)
- Show emoji / Off: cards show the status icon on its own
- Emoji from: Chat subject / Folder. Helper: Claude picks these, so AI must be on. Right-click a chat to pick your own.
- Hide folder label for: None (plus folder names). Helper: Most chats sit in one folder. Hide that folder's label to keep cards tidy.

## Settings › Windows
- Minimise other Claude windows / When you open a chat, every other Claude window goes to the Dock. Hold Option while you click a chat to flip this setting for that one click.
- Accessibility status (allowed): Accessibility allowed. Clicking a chat that is open in its own window brings that window to the front.
- Accessibility status (not allowed): Accessibility not allowed. Chats open in the main Claude window instead. / Button: Open System Settings

## Settings › AI
- Warning: These features use your own Claude plan. When chats are new or change, ClaudeSwipe sends small requests through your claude login. They include each chat's title, your first and latest messages, and Claude's last reply. All of it counts against your plan.
- Model: Haiku / Sonnet. Helper: Haiku is faster and uses less of your plan
- Sort unclear chats / Off: those chats show as "unsure"
- Let AI pick emoji / Off: only your own emoji picks show
- Ready to clear section / Checks each done chat once more to see if the whole job is finished. Chats that pass get their own section.
- Re-pick all emoji / Changing the model or emoji source only affects new chats. Re-pick asks Claude again for every chat from the last 7 days, using your plan. Your own picks stay. / Button: Re-pick…
- Re-pick confirm dialog title: Re-pick all emoji?
- Re-pick confirm dialog body: ClaudeSwipe will ask {model} to pick an emoji again for {count} chats from the last 7 days. This uses your Claude plan. Emoji you picked yourself will not change.
- Re-pick confirm dialog body (when Emoji from is Folder): ClaudeSwipe will ask {model} to pick an emoji again for {count} folders with chats from the last 7 days. This uses your Claude plan. Emoji you picked yourself will not change.
- Re-pick confirm dialog buttons: Re-pick / Cancel
- Status line: claude command found and signed in

## Notes

Fixed after review against `recent_chats.py`: sorting sends the latest prompt (not the opening one) and Claude's last reply; emoji picks send the title and opening prompt; Ready to clear sends the last reply. Requests are batched, up to 30 chats each. "{count} chats" gets a singular form in code.

Copy-writer's notes:
- Meaning change: the Settings › AI warning and the Re-pick helper no longer name Haiku. The Model picker on the same screen offers Sonnet, so a fixed "Haiku" would be wrong half the time. The Welcome step 2 warning also drops "Haiku" because the person can change the model before any request is sent.
- Meaning change: Welcome step 2 body now says the two extras need different things (a Mac permission versus your Claude plan). The draft said both "need something from your Mac", which is only true for one.
- Meaning change: both warnings now carry the same three facts (uses your plan, sent on new or changed chats, sends title + opening prompt + last reply). The Welcome warning had left out what is sent.
- Meaning change: the Option-click helper now says what minimise does (other Claude windows go to the Dock) and that Option flips the setting for one click. "Keeps one chat on screen" and "does the opposite" are gone from every string.
- Switch names shortened to fit 2-5 words: "Use my Claude for sorting and emoji" is now "Use my Claude plan"; "Pick an emoji for each chat" is now "Let AI pick emoji". Rename if the shorter names lose something you need.
- Unsure: Re-pick dialog count. The design spec says the count is chats without your own pick (Chat subject) or distinct folders (Folder), so it is not "every chat". I gave two bodies so the noun stays true, and kept the noun out of the title. If you want one body, use the chats version and accept it is off under Folder.
- Unsure: "{count} chats" reads wrongly when the count is 1 ("1 chats"). The copy cannot fix this on its own; you need a singular string or a plural rule in code. Only the dialog body is affected now.
- Assumption: "Hide folder label for" is a menu with "None" plus folder names (confirmed in the design spec), so "Your main folder, so its chats look cleaner" was helper text, not an option. I rewrote it as helper text. The draft's em dash separators are replaced with "Helper:" on picker lines and " / " elsewhere.
