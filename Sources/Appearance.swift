// Appearance model: the panel's see-through values, the style presets, and the
// small rules around them. Foundation and CoreGraphics only, so tests/run.sh can
// compile it without AppKit or SwiftUI.

import CoreGraphics
import Foundation

enum BlurLevel: String, CaseIterable { case off, light, heavy }
enum GlassStyle: String, CaseIterable { case off, regular, clear }
enum Density: String, CaseIterable { case cozy, compact }

struct AppearanceValues: Equatable {
    var opacity: Double  // percent, opacityFloor...100
    var blur: BlurLevel
    var fade: Double     // percent of the panel width, 0...100
    var glass: GlassStyle
}

// The lowest panel opacity the slider allows. Starter value; Jamie tunes it.
// The slider minimum, Clear's opacity and load-time clamping all read this.
let opacityFloor: Double = 60

enum StylePreset: String, CaseIterable {
    case solid, frosted, clear

    var values: AppearanceValues {
        switch self {
        case .solid: return AppearanceValues(opacity: 100, blur: .off, fade: 0, glass: .off)
        case .frosted: return AppearanceValues(opacity: 66, blur: .light, fade: 40, glass: .regular)
        case .clear: return AppearanceValues(opacity: opacityFloor, blur: .heavy, fade: 70, glass: .clear)
        }
    }
}

let defaultAppearance = StylePreset.frosted.values

// A saved value below the floor (old or hand-edited) loads as the floor.
func clampedToFloor(_ v: AppearanceValues) -> AppearanceValues {
    var v = v
    v.opacity = min(100, max(opacityFloor, v.opacity))
    v.fade = min(100, max(0, v.fade))
    return v
}

// nil means the values match no preset: the pane shows "Custom".
func matchedPreset(_ v: AppearanceValues) -> StylePreset? {
    StylePreset.allCases.first { $0.values == v }
}

// What the panel draws. Reduce transparency or Increase contrast forces solid;
// glass needs macOS 26. The saved values are never changed.
func effective(_ v: AppearanceValues, solidRequired: Bool, glassAvailable: Bool) -> AppearanceValues {
    if solidRequired { return StylePreset.solid.values }
    var v = v
    if !glassAvailable { v.glass = .off }
    return v
}

// Horizontal alpha stops for the edge fade, left (0) to right (1): clear at the
// left edge, half at fade/200 of the width, solid at fade/100. None at fade 0.
func fadeStops(_ fade: Double) -> [(location: Double, alpha: Double)] {
    guard fade > 0 else { return [] }
    return [(0, 0), (fade / 200, 0.5), (fade / 100, 1)]
}

// Centred in `visible`, then moved left just enough to clear the panel, but never
// past visible.minX (it overlaps the panel when there's no room). Same coordinate
// space as visibleFrame.
func settingsOrigin(window: CGSize, panel: CGRect, visible: CGRect) -> CGPoint {
    var x = visible.minX + (visible.width - window.width) / 2
    if x + window.width > panel.minX { x = panel.minX - window.width }
    x = max(visible.minX, x)
    let y = visible.minY + (visible.height - window.height) / 2
    return CGPoint(x: x, y: y)
}

// One-time copy of the old emoji prefs to the topic icon keys. Runs once per
// defaults domain (flag iconPrefsMigrated), so later changes are never overwritten.
func migrateIconPrefs(_ d: UserDefaults) {
    guard !d.bool(forKey: "iconPrefsMigrated") else { return }
    if let s = d.string(forKey: "emojiSource") { d.set(s, forKey: "iconSource") }
    // The old gate was showEmoji && aiEmoji (showEmoji defaulted to on), so AI picks
    // that were off because emoji were hidden stay off.
    if d.object(forKey: "aiEmoji") != nil {
        let shown = d.object(forKey: "showEmoji") == nil || d.bool(forKey: "showEmoji")
        d.set(d.bool(forKey: "aiEmoji") && shown, forKey: "aiIcon")
    }
    d.removeObject(forKey: "cardIcon")
    d.removeObject(forKey: "showEmoji")
    d.set(true, forKey: "iconPrefsMigrated")
}

// Each state's own SF Symbol. statusStyle (App.swift) reads its names from here.
let statusSymbol: [String: String] = [
    "running": "ellipsis", "waiting": "questionmark", "blocked": "xmark", "done": "checkmark",
    "finished": "archivebox.fill", "stuck": "exclamationmark", "unsure": "circle.dotted",
]

// The chat's topic symbol if it's on the allowlist, else the state's own symbol.
// So a stale emoji or a made-up AI pick never shows a blank circle.
func topicSymbol(_ icon: String?, status: String, allow: Set<String>) -> String {
    if let i = icon, allow.contains(i) { return i }
    return statusSymbol[status] ?? statusSymbol["unsure"]!
}

// While Settings is open, the panel stays up through stray clicks and the cursor
// leaving. Only an explicit action (opening a chat, Esc, the hotkey) hides it.
func panelMayHide(settingsOpen: Bool, explicit: Bool) -> Bool {
    !settingsOpen || explicit
}
