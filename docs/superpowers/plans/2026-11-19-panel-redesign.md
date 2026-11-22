# Panel Redesign and Appearance Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle the chat panel to the "E" design (flush, grouped, see-through), add an Appearance pane that tunes it live, and replace emoji with SF Symbol topic icons.

**Architecture:**
- Pure logic goes in a new Foundation-only file, `Sources/Appearance.swift`: values, presets, clamping, the accessibility override, the fade stops, Settings placement and prefs migration. A plain swiftc test runner tests it, because the repo builds with Command Line Tools and has no Xcode test target.
- AppKit views for the see-through layers go in `Sources/PanelBackground.swift`.
- The SwiftUI restyle stays in `App.swift` and `Settings.swift`, following the existing pattern.
- The script gets an SF Symbol allowlist shared with the app.

**Tech Stack:** Swift 5 (swiftc, Command Line Tools), SwiftUI plus AppKit, `NSVisualEffectView`, `NSGlassEffectView` (macOS 26+), Python 3 (`recent_chats.py`, unittest).

**Spec:** `docs/superpowers/specs/2026-11-19-panel-redesign-design.md`. Read it first. Mockups: https://claude.ai/artifact/CQqaokmZuA3SRLnUiANUAg (boards E, E2, Settings · Appearance).

## Global Constraints

- `LSMinimumSystemVersion` 14.0. Liquid Glass only behind `#available(macOS 26, *)`. No private APIs.
- Panel width 440pt. Flush to `visibleFrame.maxX`, full `visibleFrame` height, no corner radius, no window shadow.
- Opacity floor: one constant, `opacityFloor = 60`. The slider minimum, Clear's opacity and load-time clamping all read it.
- Defaults: opacity 66, blur `.light`, fade 40, glass `.regular`, density `.cozy`, theme `auto`.
- Styles:
  - Solid: 100, `.off`, 0, `.off`.
  - Frosted: 66, `.light`, 40, `.regular`.
  - Clear: `opacityFloor`, `.heavy`, 70, `.clear`.
- Fade stops: none when fade is 0. Otherwise alpha 0 at x=0, alpha 0.5 at `fade/200` of the width, alpha 1 at `fade/100`.
- Reduce transparency or Increase contrast shows opacity 100, blur off, fade 0 and glass off, at display time only. Saved values never change.
- The panel stays open the whole time the Settings window is open.
- Topic symbols come only from `icons.json`. Anything else shows the state's own symbol from `statusStyle`.
- Copy follows `docs/superpowers/specs/2026-11-05-settings-copy.md` style: short, plain, no em dashes.
- Build with `./build.sh`. Commit after each task. Co-author line per the repo's attribution rule.

## Review Focus

- A saved opacity below the floor (an old value, or a hand-edited plist) loads as the floor, not as an unreadable panel. Test in Task 1 (`clampedToFloor`).
- An AI pick that isn't on the allowlist, or a stale emoji string, shows the state symbol, never a blank circle. Tests in Task 3 (Python and Swift).
- A Settings window on a screen narrower than window plus panel overlaps the panel but never goes off-screen. Test in Task 1 (`settingsOriginNarrowScreen`).
- Reduce transparency toggled while the panel is open turns the panel solid at once, and the saved values come back when it's turned off. Test in Task 1 (`effectiveSolidKeepsInput`), plus a manual check in Task 7.
- An existing user with `emojiSource=folder` and `aiEmoji=true` keeps that choice as `iconSource=folder` and `aiIcon=true`. A second launch doesn't overwrite later changes. Test in Task 2 (`migrationRunsOnce`).

---

### Task 1: Appearance model and Swift test runner

**Files:**
- Create: `Sources/Appearance.swift` (Foundation and CoreGraphics only, no AppKit or SwiftUI)
- Create: `tests/run.sh`, `tests/main.swift`

**Interfaces:**
- Produces:
  - `enum BlurLevel: String, CaseIterable { case off, light, heavy }`
  - `enum GlassStyle: String, CaseIterable { case off, regular, clear }`
  - `enum Density: String, CaseIterable { case cozy, compact }`
  - `enum StylePreset: String, CaseIterable { case solid, frosted, clear }` with `var values: AppearanceValues`
  - `struct AppearanceValues: Equatable { var opacity: Double; var blur: BlurLevel; var fade: Double; var glass: GlassStyle }`
  - `let opacityFloor: Double = 60`
  - `let defaultAppearance: AppearanceValues` (equal to `StylePreset.frosted.values`)
  - `func clampedToFloor(_ v: AppearanceValues) -> AppearanceValues`: opacity to `opacityFloor...100`, fade to `0...100`
  - `func matchedPreset(_ v: AppearanceValues) -> StylePreset?`: nil means Custom
  - `func effective(_ v: AppearanceValues, solidRequired: Bool, glassAvailable: Bool) -> AppearanceValues`
  - `func fadeStops(_ fade: Double) -> [(location: Double, alpha: Double)]`
  - `func settingsOrigin(window: CGSize, panel: CGRect, visible: CGRect) -> CGPoint`

- [ ] **Step 1: Write the test runner and failing tests**

`tests/run.sh` compiles `Sources/Appearance.swift tests/main.swift` with `swiftc -swift-version 5`, without `-parse-as-library`, then runs the binary. Exit is non-zero on any failure. `tests/main.swift` has a `check(_ name: String, _ cond: Bool)` helper that prints PASS/FAIL and counts failures, and these checks:

```swift
check("presetsMatchSpec",
  StylePreset.solid.values == AppearanceValues(opacity: 100, blur: .off, fade: 0, glass: .off) &&
  StylePreset.frosted.values == AppearanceValues(opacity: 66, blur: .light, fade: 40, glass: .regular) &&
  StylePreset.clear.values == AppearanceValues(opacity: opacityFloor, blur: .heavy, fade: 70, glass: .clear))
check("defaultIsFrosted", matchedPreset(defaultAppearance) == .frosted)
check("customWhenTouched", matchedPreset(AppearanceValues(opacity: 67, blur: .light, fade: 40, glass: .regular)) == nil)
check("clampedToFloor", clampedToFloor(AppearanceValues(opacity: 20, blur: .light, fade: 140, glass: .off)).opacity == 60
  && clampedToFloor(AppearanceValues(opacity: 20, blur: .light, fade: 140, glass: .off)).fade == 100)
let custom = AppearanceValues(opacity: 70, blur: .heavy, fade: 55, glass: .clear)
check("effectiveSolidKeepsInput", effective(custom, solidRequired: true, glassAvailable: true)
  == AppearanceValues(opacity: 100, blur: .off, fade: 0, glass: .off) && custom.opacity == 70)
check("glassOffBelow26", effective(custom, solidRequired: false, glassAvailable: false).glass == .off)
check("fadeZeroNoStops", fadeStops(0).isEmpty)
check("fadeStops40", fadeStops(40).map(\.location) == [0, 0.2, 0.4] && fadeStops(40).map(\.alpha) == [0, 0.5, 1])
let vis = CGRect(x: 0, y: 0, width: 1512, height: 944)
let panel = CGRect(x: 1072, y: 0, width: 440, height: 944)
check("settingsOriginCentredWhenClear", settingsOrigin(window: CGSize(width: 600, height: 580), panel: panel, visible: vis).x == 456)
check("settingsOriginShiftsLeft", settingsOrigin(window: CGSize(width: 760, height: 580), panel: panel, visible: vis).x == 312)
let narrow = CGRect(x: 0, y: 0, width: 1000, height: 700)
check("settingsOriginNarrowScreen", settingsOrigin(window: CGSize(width: 760, height: 580), panel: CGRect(x: 560, y: 0, width: 440, height: 700), visible: narrow).x == 0)
```

`settingsOrigin` rule:
- Start centred in `visible`.
- If the window's right edge passes `panel.minX`, move left until the right edge equals `panel.minX`.
- Never go past `visible.minX`, even if that overlaps the panel.
- y stays centred.
- Worked values: centred x = (1512 − 760)/2 = 376, right edge 1136 > 1072, so x = 1072 − 760 = 312. For the 600-wide window, centred x = 456 and the right edge is 1056, which clears the panel.

- [ ] **Step 2: Run it to make sure it fails**

Run: `tests/run.sh`
Expected: compile errors (the types aren't defined yet).

- [ ] **Step 3: Implement everything in `Sources/Appearance.swift`**

Match the signatures in Interfaces. `fadeStops` returns `[(0,0), (fade/200, 0.5), (fade/100, 1)]` for fade > 0.

- [ ] **Step 4: Run the tests and make sure they pass**

Run: `tests/run.sh`
Expected: every line PASS, exit 0. Also run `./build.sh` and expect `installed …`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Appearance.swift tests/run.sh tests/main.swift
git commit -m "Appearance model: presets, floor, solid override, fade stops, Settings placement"
```

### Task 2: Prefs keys and one-time migration

**Files:**
- Modify: `Sources/Settings.swift:12-85` (the `Prefs` class)
- Modify: `Sources/Appearance.swift` (add the migration function)
- Test: `tests/main.swift`

**Interfaces:**
- Consumes: Task 1 types, `clampedToFloor`.
- Produces:
  - `func migrateIconPrefs(_ d: UserDefaults)` in `Appearance.swift`. It copies `emojiSource` to `iconSource` and `aiEmoji` to `aiIcon` only if the flag `iconPrefsMigrated` is unset, sets the flag, and removes `cardIcon` and `showEmoji`.
  - `Prefs` gains `@Published var appearance: AppearanceValues` (stored as `panelOpacity` Double, `panelBlur` String, `panelFade` Double, `panelGlass` String), `@Published var density: Density` (key `density`), `@Published var iconSource: String` and `@Published var aiIcon: Bool`, plus `func resetAppearance()` (theme `auto`, `defaultAppearance`, density `.cozy`).
  - `Prefs` loses `cardIcon`, `showEmoji`, `emojiSource` and `aiEmoji`. `pickEmoji` becomes `pickIcon` (equal to `aiIcon`).
  - `scriptArgs` becomes `["--model", aiModel, "--icon-from", iconSource]`, plus `--sort`, `--clear`, and `["--icon", iconSource]` when `pickIcon`.

- [ ] **Step 1: Write the failing tests** (use `UserDefaults(suiteName: "test.\(UUID())")!`)

```swift
let d = UserDefaults(suiteName: "test.\(UUID())")!
d.set("folder", forKey: "emojiSource"); d.set(true, forKey: "aiEmoji"); d.set("emoji", forKey: "cardIcon")
migrateIconPrefs(d)
check("migrationCopies", d.string(forKey: "iconSource") == "folder" && d.bool(forKey: "aiIcon") && d.object(forKey: "cardIcon") == nil)
d.set("subject", forKey: "iconSource"); migrateIconPrefs(d)
check("migrationRunsOnce", d.string(forKey: "iconSource") == "subject")
```

- [ ] **Step 2: Run them to make sure they fail**

Run: `tests/run.sh`
Expected: compile error, `migrateIconPrefs` is not defined.

- [ ] **Step 3: Implement**

Add `migrateIconPrefs` to `Appearance.swift`. Update `Prefs`:
- `init` calls `migrateIconPrefs(d)` before reading anything.
- Register the new defaults.
- Load `appearance` through `clampedToFloor`.
- Writes to `iconSource` or `aiIcon` call `scriptChanged()`.
- `resetAppearance()` sets all three values.
- Fix every use of the removed properties: `App.swift` (`Card`, `filtered`, `confirmRepick`) and the Cards and AI panes in `Settings.swift`. Point them at the new names; the full restyle comes in Tasks 5 and 6.

- [ ] **Step 4: Run the tests and the build**

Run: `tests/run.sh && ./build.sh`
Expected: all PASS, then `installed …`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Appearance.swift Sources/Settings.swift Sources/App.swift tests/main.swift
git commit -m "Prefs: appearance, density and icon keys, one-time migration from emoji keys"
```

### Task 3: SF Symbol topic icons (script and app)

**Files:**
- Create: `icons.json` (repo root): `{"symbols": ["paintpalette", "key", "doc.text", …]}`, about 60 names.
- Create: `tests/test_icons.py`
- Modify: `recent_chats.py:26-27, 217-331, 352-431` (paths, the pick prompt, `folder_emojis`, argparse, row output)
- Modify: `Sources/App.swift:10-24` (`Chat`), `598-640` (`editEmoji` becomes `editIcon`), `build.sh` (copy `icons.json` into Resources)

**Interfaces:**
- Produces (Python):
  - `load_allowlist(path) -> set[str]`
  - `valid_icon(name, allow) -> str | None`
  - Flags `--icon off|subject|folder` and `--icon-from subject|folder`, replacing `--emoji` and `--emoji-from`.
  - Files `chat-icons.json` and `folder-icons.json`, in the same `{"overrides":{}, "auto":{}}` shape, next to the old emoji files. The old emoji files are not read.
  - Each row has `icon` (str or None) and `own_icon` (bool).
- Produces (Swift):
  - `Chat.icon: String?` and `Chat.own_icon: Bool?`, replacing `emoji` and `own_emoji`.
  - `func topicSymbol(_ icon: String?, status: String, allow: Set<String>) -> String` in `Appearance.swift`. It returns `icon` if it's in `allow`, otherwise the status symbol name.
  - Because `Appearance.swift` stays AppKit-free, pass status symbols as `[String: String]`. Add `let statusSymbol: [String: String]` there, holding the names from `statusStyle`, and make `statusStyle` read from it.
  - `let iconAllowlist: Set<String>` loaded once from `Bundle.main` `icons.json`.

- [ ] **Step 1: Write the failing tests**

`tests/test_icons.py` (unittest, imports `recent_chats` via `sys.path`):

- `test_valid_icon_accepts_listed`: `valid_icon("key", {"key"}) == "key"`.
- `test_valid_icon_rejects_unlisted_and_emoji`: `valid_icon("🔑", {"key"}) is None` and `valid_icon("sparkles.rectangle.stack.fill.badge", {"key"}) is None`.
- `test_allowlist_file_loads`: `len(load_allowlist(Path("icons.json"))) >= 40`.
- `test_bare_run_has_icon_off`: `parse_args([])` gives `icon == "off"`. (Factor argparse into `parse_args(argv)` if it isn't already.)
- `test_prompt_embeds_allowlist`: the pick prompt builder includes every allowlist name. Expose the prompt as `pick_prompt(allow) -> str`.

In `tests/main.swift`:

```swift
check("topicSymbolListed", topicSymbol("key", status: "waiting", allow: ["key"]) == "key")
check("topicSymbolFallback", topicSymbol("🔑", status: "waiting", allow: ["key"]) == "questionmark")
check("topicSymbolNil", topicSymbol(nil, status: "done", allow: ["key"]) == "checkmark")
```

- [ ] **Step 2: Run them to make sure they fail**

Run: `python3 -m unittest tests/test_icons.py -v; tests/run.sh`
Expected: ImportError or AttributeError, and a Swift compile error.

- [ ] **Step 3: Implement**

- Python: the AI pick asks for ONE name from the embedded list. Run the reply through `valid_icon` and drop invalid names, so the auto entry stays unset.
- Swift: `Chat` decodes the new keys.
- `editIcon` replaces the emoji text field with an `NSPopUpButton`, or a menu of `iconAllowlist` sorted, plus "Use automatic". It writes `chat-icons.json` overrides the same way `editEmoji` wrote emoji.
- Remove `c.emoji` from the search haystack in `filtered`.
- Pick allowlist names that exist in SF Symbols 3 (macOS 12) or earlier, covering common work topics: design, code, docs, mail, money, time, images, data, people, settings and travel.

- [ ] **Step 4: Verify each name resolves, then run the tests**

Run: `swift -e 'import AppKit; import Foundation; let s = try! JSONDecoder().decode([String:[String]].self, from: Data(contentsOf: URL(fileURLWithPath: "icons.json")))["symbols"]!; let bad = s.filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil }; print(bad.isEmpty ? "all resolve" : "missing: \(bad)")'`

Expected: `all resolve`. This checks this Mac's OS only; macOS 14 availability rests on choosing SF Symbols 3-era names. Note "unverified on 14" in the commit message.

Then run `python3 -m unittest tests/test_icons.py -v && tests/run.sh && ./build.sh`. Expected: all pass, `installed …`.

- [ ] **Step 5: Commit**

```bash
git add icons.json recent_chats.py tests/test_icons.py Sources/App.swift Sources/Appearance.swift tests/main.swift build.sh
git commit -m "Topic icons: SF Symbol allowlist shared by script and app, replaces emoji"
```

### Task 4: See-through background stack (build this first, it's the riskiest)

**Files:**
- Create: `Sources/PanelBackground.swift`
- Modify: `Sources/App.swift:364-376` (panel setup), `488-492` (`show(on:)` frame)

**Interfaces:**
- Consumes: `AppearanceValues`, `fadeStops`, `effective`, `Prefs.appearance`.
- Produces (SwiftUI):
  - `struct PanelMaterial: NSViewRepresentable` with `(blur: BlurLevel, fade: Double)`: an `NSVisualEffectView` (`.behindWindow`, `.active`) whose `maskImage` is a horizontal gradient from `fadeStops`. `.off` hides it.
  - `struct PanelTint: View` with `(opacity: Double, fade: Double)`: the theme bg colour at `opacity/100`, masked by a `LinearGradient` from the same stops.
  - `struct GroupBackground: View` with `(glass: GlassStyle)`, applied with `.background(GroupBackground(...))` on each section group and the search pill, 12pt corner radius. On macOS 26 with glass `.regular` or `.clear`, it uses `NSGlassEffectView` (`style` to match) behind the group, wrapped as `NSViewRepresentable`. Otherwise it's a flat fill (`rgba(48,48,46,0.55)` dark, `rgba(255,255,255,0.55)` light) over a `.withinWindow` material, with a 1pt hairline (6% white dark, 5% black light).
  - `func blurMaterial(_ b: BlurLevel) -> NSVisualEffectView.Material?`: off returns nil. Light and heavy are the builder's pick of two materials that look clearly different, with a comment naming them.
  - Clear glass groups use a thinner fill: 32% dark, 34% light.
  - When fade is 0 and opacity is below 100: a 1pt light rim on the panel's left edge (16% white dark, 75% white light), and a soft shine in the top left (a 160° linear gradient, 10% white dark or 55% white light, fading out by about 35% of the panel).

- [ ] **Step 1: Wire a test screen**

- Panel: `hasShadow = false`.
- `show(on:)` target: `NSRect(x: vf.maxX - width, y: vf.minY, width: width, height: vf.height)`.
- `PanelView`'s root background becomes `ZStack { PanelMaterial; PanelTint }`, reading `effective(prefs.appearance, solidRequired: false, glassAvailable: …)`.
- Put one `GroupBackground` behind the existing list as a placeholder.

- [ ] **Step 2: Build and check the stack by eye**

Run: `./build.sh --run`. Open a white window (TextEdit) and a dark window under the panel's right edge, then open the panel.

Expected:
- The panel touches the right and bottom edges with no shadow.
- The background fades from clear at the left edge to solid around 40% across.
- Blur shows only where it's opaque.
- The group stays readable across the full width.
- Set `defaults write com.jevawin.claude-swipe panelGlass clear` and `panelBlur heavy`, then reopen; the look changes.

- [ ] **Step 3: Apply the fallback rules if a layer fails**

The spec's order:
- Glass won't render behind SwiftUI: use the flat group fill.
- The fade mask won't work: use a hard edge and set a flag `fadeSupported = false`, which Task 6 reads to hide the slider.

Write down what failed, with what you saw, in the commit message and in your report. Don't invent another look.

- [ ] **Step 4: Run the build and the tests**

Run: `tests/run.sh && ./build.sh`
Expected: PASS, `installed …`.

- [ ] **Step 5: Commit**

```bash
git add Sources/PanelBackground.swift Sources/App.swift
git commit -m "Panel: flush full-height window, material and fade mask, group glass"
```

### Task 5: Panel restyle (layout E)

**Files:**
- Modify: `Sources/App.swift:180-336` (`PanelView` body and `Card`, which becomes `ChatRow`)

**Interfaces:**
- Consumes: `GroupBackground`, `topicSymbol`, `iconAllowlist`, `Prefs.density`, `statusStyle`, the effective fade value.
- Produces:
  - `struct ChatRow: View` with `(chat: Chat, selected: Bool, density: Density, divider: Bool)`.
  - `struct StateIcon: View` with `(symbol: String, color: Color, size: CGFloat)`.

- [ ] **Step 1: Build the layout to the spec's "Layout (E with the pill search)" section, using its exact sizes**

- Search pill: 40pt high, placeholder "Search Claude chats", 15pt medium, Refresh and Settings buttons inside. Remove the old header.
- Section headers:
  - 12.5pt semibold.
  - The count in regular weight at 80% opacity.
  - A chevron.
  - When fade > 0, two text shadows in the panel bg colour: radius 6 at 95% and radius 12 at 80%.
- One `GroupBackground` per section, with full-width 1pt dividers between rows.
- `ChatRow` cozy:
  - 13pt vertical padding.
  - `StateIcon` 32pt: a circle in the state colour at about 18% (dark) or 14% (light), holding the symbol in the state colour.
  - Title 14pt semibold, summary 12.5pt secondary, 4pt apart.
  - Age over folder at the right.
- `ChatRow` compact: 8pt padding, 24pt icon, one line, with the summary only when selected.
- Secondary text: #C4C2BA dark, #57564F light.
- Keep the existing behaviour: Done collapse (`showDone`), `doneFade`, the `homeFolder` label hiding, selection, open on click, the right-click menu (now `editIcon`), Esc.

- [ ] **Step 2: Build and compare against the canvas boards EDark and ELight**

Run: `./build.sh --run`. Check both themes (General → Theme) and both densities (`defaults write com.jevawin.claude-swipe density compact`).

Expected:
- Matches the boards within a point or two.
- No emoji anywhere.
- A chat with no pick shows its state symbol.
- VoiceOver reads each row's state name (keep the existing accessibility labels).

- [ ] **Step 3: Run the tests**

Run: `tests/run.sh && python3 -m unittest tests/test_icons.py`
Expected: all PASS.

- [ ] **Step 4: Commit**

```bash
git add Sources/App.swift
git commit -m "Panel: layout E with search pill, grouped rows and round state icons"
```

### Task 6: Appearance pane

**Files:**
- Modify: `Sources/Settings.swift:348-430` (panes list, `general`) and add `var appearance: some View`. Update the Cards and AI panes.

**Interfaces:**
- Consumes: `Prefs.appearance`, `Prefs.density`, `Prefs.theme`, `resetAppearance()`, `matchedPreset`, `StylePreset`, `opacityFloor`, `defaultAppearance`, `fadeSupported` (Task 4), and `Prefs.systemSolid` (Task 7, until then always false).
- Produces: the `"Appearance"` pane.

- [ ] **Step 1: Build the pane to the spec's "Controls, in order" table and the Settings mockup**

- Panes: General, Appearance (`circle.lefthalf.filled`), Cards, Windows, AI. Theme moves from General to Appearance.
- Style:
  - Three picture tiles (84×54) drawn in SwiftUI, a mini desktop with a mini panel in that style.
  - The selected tile gets a 2pt `Theme.brand` ring.
  - A "Custom" tag shows when `matchedPreset` is nil.
  - A click sets `prefs.appearance = preset.values`.
- Opacity: a slider from `opacityFloor` to 100, with a 64×42 preview. The preview shows the current value and animates min to max on hover; no animation when `accessibilityDisplayShouldReduceMotion`.
- Edge fade: a slider from 0 to 100 with a preview. Hidden when `fadeSupported` is false.
- Blur: Off, Light and Heavy tiles.
- Glass: Off, Regular and Clear tiles. Disabled below macOS 26, with the note "Needs macOS 26 or later".
- Density: Cozy and Compact tiles, with the line "Cozy shows each chat's summary. Compact fits more chats on one line each."
- Reset to defaults: dimmed when `prefs.appearance == defaultAppearance && prefs.theme == "auto" && prefs.density == .cozy`.
- When `systemSolid`: a note, "Reduce transparency is on in macOS System Settings, so the panel is solid. Turn it off there to use these controls.", and the background and glass controls are disabled.
- Cards pane: remove Card icon and Show emoji. "Emoji from" becomes "Topic icon from". The AI pane's "Pick an emoji…" becomes "Pick a topic icon for each chat", and Re-pick copy says "topic icon".

- [ ] **Step 2: Build and click through every control**

Run: `./build.sh --run` and open Settings → Appearance.

Expected:
- Each control changes the panel live (once Task 7 lands, or with the panel open).
- Touching a slider shows Custom.
- Clicking Frosted clears it.
- Reset dims afterwards.
- `defaults read com.jevawin.claude-swipe panelOpacity` reflects the slider.

- [ ] **Step 3: Run the tests**

Run: `tests/run.sh`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Sources/Settings.swift
git commit -m "Settings: Appearance pane with styles, sliders, tiles and reset"
```

### Task 7: Live panel while Settings is open, placement, accessibility

**Files:**
- Modify: `Sources/App.swift` (`tick()` ~458, global mouse monitor ~396, `hide`, `bringUp` ~666, `openSettings` ~672, `windowWillClose` ~690) and `Sources/Settings.swift` (`Prefs`)

**Interfaces:**
- Consumes: `settingsOrigin`, `effective`, `show(on:)`.
- Produces:
  - `var settingsOpen: Bool { settingsWindow?.isVisible == true }` on `AppDelegate`.
  - `Prefs.systemSolid: Bool`, true when `NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency || accessibilityDisplayShouldIncreaseContrast`. It's updated on `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`, and the panel's `effective(...)` call reads it.

- [ ] **Step 1: Implement**

- `hide(reason:)` returns early while `settingsOpen`, except during quit.
- `bringUp` stops calling `hide()` for the Settings window. The Welcome window still hides the panel.
- `openSettings`:
  - Shows the panel on the Settings window's screen (or the mouse's screen on first open).
  - Then places the window with `setFrameOrigin(settingsOrigin(window:panel:visible:))`. Convert to AppKit's bottom-left origin; the function works in the same coordinate space as `visibleFrame`.
- `windowWillClose` for Settings: leaves the panel up, so normal hiding (cursor leave, click elsewhere) takes over from there.

- [ ] **Step 2: Build and check by hand**

Run: `./build.sh --run`.

- Open Settings from the menu bar. The panel appears and stays while you drag sliders, click other panes, click the desktop, and move the cursor far away.
- On a small screen (or with the window widened to 1100), the window sits left of the panel and overlaps only when there's no room.
- Turn on System Settings → Accessibility → Display → Reduce transparency while the panel is open. The panel turns solid at once and the Appearance controls disable with the note. Turn it off and your values come back.
- Close Settings, move the cursor away, and the panel hides.

- [ ] **Step 3: Run the tests**

Run: `tests/run.sh && python3 -m unittest tests/test_icons.py`
Expected: all PASS.

- [ ] **Step 4: Commit**

```bash
git add Sources/App.swift Sources/Settings.swift
git commit -m "Panel stays open with Settings; Settings avoids the panel; follows Reduce transparency"
```

Order: Task 4 needs Task 1 (types) and should run right after Task 2, ahead of Task 3, so the risky stack is proven early. Recommended order: 1, 2, 4, 3, 5, 6, 7.
