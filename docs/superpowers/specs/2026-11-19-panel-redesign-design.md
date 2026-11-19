# Panel redesign and Appearance settings

Mockups: https://claude.ai/artifact/CQqaokmZuA3SRLnUiANUAg. The boards that count are "E · Quieter" (EDark, ELight), "E2 · Gradient fade" and "Settings · Appearance". The A to D rows are history.

## Why

The panel was never designed. It feels busy, soft and unfinished: cards with borders, emoji tiles, a separate title and search box, and a floating box that stops short of the screen edge. Jamie wants it cleaner and more Claude-like, and wants a glass sidebar inspired by Monocle that touches the screen edge. Monocle gets too clear to read on light backgrounds, so ours must stay readable by default, and each person can tune how see-through it is.

## Goals

- A cleaner panel: grouped rows with hairlines, search as the title, round icons whose colour is the state.
- A full-height panel flush to the right screen edge, with content a few points in.
- See-through by default, but readable over anything, including a white window.
- An Appearance tab where people tune opacity, blur, edge fade and glass, see each change live on the real panel, and can always get back to the defaults.

## Non-goals

- Remembering the open or closed state of every section. That's a future change. Done keeps its current collapse (`showDone`).
- Colour-blind support beyond today's. Users aren't colour blind today; an accessibility option can come later.
- A floating (inset) panel option. Jamie dropped it: it doesn't suit the new design.
- Private APIs for blur or glass.

## Anti-goals

- A panel that's hard to read on a light background (Monocle's flaw).
- Text that sits in the faded part of the background with nothing behind it.
- A settings tab that feels overwhelming or can't be undone.

## Constraints

- `LSMinimumSystemVersion` is 14.0. Liquid Glass (`NSGlassEffectView`) is macOS 26+.
- Measured in the macOS SDK headers (19 Nov 2026):
  - `NSVisualEffectView` has no blur radius property.
  - `NSVisualEffectView.maskImage` takes an alpha mask that masks the material but not subviews.
  - `NSGlassEffectView` has `style` (regular or clear), `tintColor` and `cornerRadius`. There's no strength setting.
  - `CIMaskedVariableBlur` exists, but only for images the app draws itself, not for the windows behind it.
- The canvas fakes glass and blur with CSS. Liquid Glass's light-bending edges, and how the real material looks at each setting, can only be judged in a build.
- The panel hides when the cursor leaves or on a click elsewhere (`App.swift` global mouse monitor and `tick()`).

## Approaches considered

1. **Restyle the current panel in place** (cards, separate title, floating box). It's the cheapest, but it keeps the busy, boxy look Jamie wants gone. Rejected.
2. **Glass as a separate theme** next to light and dark. It doubles the design work and drifts from the main look. Rejected: Jamie reframed glass as modifiers on light and dark.
3. **One layout (E), with see-through settings layered on light and dark.** Chosen. Opacity, blur, fade and glass are settings that apply to either theme.

## The panel

### Placement

- The panel is flush to the right edge of the screen's `visibleFrame`: full height, no 8pt gap, no rounded corners, no outer border or shadow on the left edge.
- Width stays at 440pt, today's value. The mockups used 400 *(my call, not tested)*.
- The slide-in and slide-out animation stays as it is.

### Layout (E with the pill search)

- **Search as the title:** a 40pt rounded pill (12pt corner radius) at the top, with the placeholder "Search Claude chats" (15pt medium), a search icon, and Refresh and Settings buttons inside it. There's no separate "Claude chats" header.
- **Section headers** (Active, Waiting · today, Waiting · older, Done):
  - 12.5pt semibold in full text colour.
  - The count follows in regular weight at 80% opacity.
  - A chevron sits at the right. Only Done collapses for now.
- **Groups:**
  - One rounded group (12pt corner radius) per section.
  - A 1pt hairline outline, and no drop shadow or inner highlight.
  - Row dividers run the full width of the group.
- **Rows (cozy):**
  - 13pt vertical padding.
  - A 32pt round icon, then the title (14pt semibold) and the summary under it (12.5pt, secondary colour), 4pt apart.
  - Age and folder sit at the right, stacked.
  - The selected row gets a faint fill.
- **Rows (compact):**
  - 8pt vertical padding, with a 24pt icon.
  - One line: title, then folder and age.
  - The summary shows only on the selected row.
- **Icon:**
  - A circle whose colour is the chat's state.
  - It holds the chat's topic symbol: an SF Symbol in the state's colour, on a tint of that colour (default).
  - A "solid" variant (white symbol on the full colour) exists on the canvas. It isn't a setting; the builder keeps tint.
  - The topic icon is no longer shown next to the folder.
- **State colours:** the existing `statusStyle` colours. Running is blue, waiting amber, blocked red, done green, finished violet, and stuck and unsure grey.

### Colours

- Dark: the current tokens (bg #262624, text #FAF9F5).
  - Secondary text in the new panel is #C4C2BA, brightened so it stays readable at lower opacity.
  - Groups are `rgba(48,48,46,0.55)` with a 6% white hairline.
- Light: text #141413, secondary #57564F.
  - Groups are `rgba(255,255,255,0.55)` with a 5% black hairline.
- Clear glass makes groups more see-through: about 32% fill in dark and 34% in light.

### See-through background

The panel background has three layers. Text never relies on the bottom one alone.

1. **Background material:** blur plus a theme tint at the chosen opacity, across the full panel width.
2. **Edge fade:** an alpha mask on layer 1 only. It's fully transparent at the left edge and fully opaque at the fade distance. The midpoint sits at half the distance, at 50% alpha.
3. **Groups:** each group has its own fill and its own blur, so rows read the same wherever they sit and never fade.
   - With glass on, the group is a Liquid Glass view.
   - With glass off, it's a flat blurred fill.

Section headers sit on layer 1, so over the fade they get a soft glow in the panel colour to stay readable. As on the canvas, that's two text shadows in the panel's base colour: 6pt radius at 95% and 12pt at 80%. It's shown only when the fade is above 0. The search pill is a group, so it doesn't need one.

**Build order and fallbacks** *(my call)*: the riskiest piece is the see-through stack inside the borderless panel (material, gradient mask, and glass behind SwiftUI groups). Build and check it first, before the restyle.
- If group glass won't work, use the flat blurred fill.
- If the fade mask won't work, ship with a hard edge and hide the Edge fade slider.
- Either way, report back rather than invent a different look.
- The window shadow stays off on the left edge. With the fade on, the panel has no visible edge at all, so `hasShadow` is off.

A light rim on the panel's left edge and a soft shine in the top left show only when the fade is 0 and the panel is see-through.

## Appearance settings

### Where

- A new **Appearance** pane, second in the sidebar after General. The panes are General, Appearance, Cards, Windows, AI.
- Theme moves from General to Appearance.
- **Live panel while Settings is open** (Jamie): the panel stays open the whole time the Settings window is open, on any pane, on the Settings window's screen.
  - Nothing hides it while Settings is open: not clicks in Settings, not the cursor leaving, not clicks elsewhere.
  - Opening Settings from the panel (today `bringUp()` hides it first) leaves it open.
  - When Settings closes, normal hiding resumes.
- **Settings placement** (Jamie): the Settings window opens centred on the screen, as now. If that would overlap the panel, it moves left just enough to clear it. If there's no room to clear it, it overlaps.
- One shared set of values covers both themes.

### Controls, in order

| Control | Key | Type | Range or values | Default |
|---|---|---|---|---|
| Theme | `theme` (existing) | Buttons | Auto, Light, Dark | Auto |
| Style | (derived) | Picture tiles | Solid, Frosted, Clear; shows "Custom" when the values match none | Frosted |
| Opacity | `panelOpacity` | Slider + animated preview | floor to 100% | 66% |
| Blur | `panelBlur` | Picture tiles | Off, Light, Heavy | Light |
| Edge fade | `panelFade` | Slider + animated preview | 0 (hard edge) to 100 (fades across the full width) | 40 |
| Glass | `panelGlass` | Picture tiles | Off, Regular, Clear | Regular |
| Density | `density` | Picture tiles | Cozy, Compact | Cozy |
| Reset to defaults | (button) | | Dimmed when everything is at its default | |

- **Style presets** set all four background values at once. Theme and density are untouched.

  | Style | Opacity | Blur | Edge fade | Glass |
  |---|---|---|---|---|
  | Solid | 100 | Off | 0 | Off |
  | Frosted (default) | 66 | Light | 40 | Regular |
  | Clear | the floor | Heavy | 70 | Clear |

- **Opacity floor:** the slider stops at the floor, with no warning past it. The starter floor is **60%**; Jamie tests and picks the real one. One constant in code: the slider's minimum and Clear's opacity both read it, and a saved value below it is raised to it on load.
  - Worst-case contrast check (a white or black window behind, no blur, computed 19 Nov 2026): dark at 66% with 55% groups gives section labels 4.72:1 and secondary text in groups 4.77:1. Light at 62% gives 6.58 and 4.86.
  - At 60% that check doesn't pass for section labels. The glow and the blur are expected to make up the difference, but that's unmeasured. That's why Jamie tests it.
- **Glass on older macOS:** below macOS 26 the Glass tiles are disabled, with the note "Needs macOS 26 or later", and groups use the flat blurred fill.
- **Reduce transparency:** when macOS "Reduce transparency" is on, the panel is solid: opacity 100, blur 0, fade 0, glass off. The background and glass controls are disabled, with a note saying why.
  - Increase contrast does the same *(my call)*.
  - It overrides only at display time. Saved values are kept and come back when the system setting is turned off. The panel updates live (`NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`) *(my call)*.
- **Reset to defaults** sets Theme and Density back as well as the four background values (that's what the mockup does).
- **Previews:**
  - Opacity and Edge fade each have a small preview that shows its current value. It animates from min to max while you hover over it, and stays still under Reduce motion.
  - Style, Blur, Glass and Density show picture tiles. Theme doesn't need one.

### Cards pane

- Card icon (status or emoji) and Show emoji go: the round state icon replaces both.
- "Emoji from" becomes **"Topic icon from"** (subject, folder), and AI "Pick an emoji" becomes **"Pick a topic icon"**. See Topic icons.
- *(Builder's call: the exact copy, following the existing copy doc's style.)*

## Topic icons (SF Symbols replace emoji)

- **A fixed allowlist** *(my call)*: a curated list of about 60 SF Symbol names, each checked to exist on macOS 14. It lives in one file that both the script and the app read.
  - The AI prompt includes the list and must pick from it.
  - The right-click override picker shows the same list.
  - The app still falls back to the state's symbol if a name isn't on the list. That makes the unverified `NSImage(systemSymbolName:)` nil check unnecessary.
- **No topic symbol** (AI off, which is the default, or no pick yet): the circle shows the state's own symbol, today's status glyphs *(my call)*.
- **Data and flags** *(my call)*:
  - New files `chat-icons.json` and `folder-icons.json`, in the same "overrides" plus "auto" shape. The old emoji files are left on disk and ignored.
  - Flags are renamed: `--icon off|subject|folder` and `--icon-from subject|folder`. Rows carry `icon` and `own_icon`.
  - Prefs: `showEmoji` and `cardIcon` go. `emojiSource` becomes `iconSource`, and `aiEmoji` becomes `aiIcon`. Old values are copied across once on first launch.
  - Search does not match symbol names.

## Left to the builder

- How to build the edge fade (gradient `maskImage` on the material view, plus a masked tint layer) and the group glass (`NSGlassEffectView` behind each SwiftUI group, or SwiftUI's glass modifier if available).
- Exact spacing where the canvas and SwiftUI differ by a point or two.
- The hover-preview animation itself: a short min-to-max loop is enough.

## Blur (decided)

macOS has no public blur radius, so Blur is a choice, not a slider (Jamie, 19 Nov 2026):
- **Off:** no material, tint only.
- **Light:** a thinner system material.
- **Heavy:** a thicker system material.

The builder picks the two `NSVisualEffectView` materials (or glass styles on macOS 26) that look clearly different, and notes which in the code. If this looks bad in the build, the fallback is the earlier idea: a slider that fades the full system blur in and out.
