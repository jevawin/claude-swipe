// Appearance model: the panel's background style and see-through amount, and the
// small rules around them. Foundation and CoreGraphics only, so tests/run.sh can
// compile it without AppKit or SwiftUI.
//
// Changed 19 Nov 2026 after the first build (Jamie): public materials and Liquid Glass
// always blur fully and differ only in tint, so Blur Light/Heavy, Glass Regular/Clear
// and Edge fade were replaced by one Background choice and one See-through slider.

import CoreGraphics
import Foundation

// Solid: theme colour, no blur. Frosted: one behind-window material. Glass (macOS 26+):
// Liquid Glass groups over a tint, no panel material.
enum BackgroundStyle: String, CaseIterable { case solid, frosted, glass }
// Default: icon, title over summary, age over folder (was "Cozy" before 22 Nov 2026).
// Cozy: the same text size, with less space and smaller icons. Compact: one line, no summary.
enum Density: String, CaseIterable {
    case standard = "default", cozy, compact
    var label: String { self == .standard ? "Default" : rawValue.capitalized }
}

// Sizes for one row. Text size scales every number except the summary line count.
struct RowMetrics {
    let icon, title, summary, meta, vpad, spacing, gap: CGFloat
    static func of(_ d: Density, scale s: CGFloat) -> RowMetrics {
        switch d {
        case .standard: return RowMetrics(icon: 32*s, title: 14*s, summary: 12.5*s, meta: 12*s, vpad: 13*s, spacing: 12*s, gap: 4*s)
        case .cozy:     return RowMetrics(icon: 26*s, title: 14*s, summary: 12.5*s, meta: 12*s, vpad: 8*s, spacing: 10*s, gap: 2*s)
        case .compact:  return RowMetrics(icon: 24*s, title: 14*s, summary: 0, meta: 12*s, vpad: 8*s, spacing: 10*s, gap: 0)
        }
    }
}

struct AppearanceValues: Equatable {
    var background: BackgroundStyle
    var opacity: Double  // percent of paint: panel tint and group fill, opacityFloor...100
}

// The lowest opacity the See-through slider allows. 0, so See-through goes to 100%:
// Jamie tried blur and glass on their own and kept it (19 Nov 2026). The slider and load-time
// clamping read this.
let opacityFloor: Double = 0

let defaultAppearance = AppearanceValues(background: .frosted, opacity: 66)

// A saved value outside the range (old or hand-edited) loads clamped.
func clampedToFloor(_ v: AppearanceValues) -> AppearanceValues {
    var v = v
    v.opacity = min(100, max(opacityFloor, v.opacity))
    return v
}

// What the panel draws. Reduce transparency or Increase contrast forces solid; Solid
// is always opaque; Glass needs macOS 26 and falls back to Frosted. Saved values never change.
func effective(_ v: AppearanceValues, solidRequired: Bool, glassAvailable: Bool) -> AppearanceValues {
    if solidRequired { return AppearanceValues(background: .solid, opacity: 100) }
    var v = v
    if v.background == .solid { v.opacity = 100 }
    if v.background == .glass && !glassAvailable { v.background = .frosted }
    return v
}

// Each group's own fill, scaled by the same opacity as the panel tint, so See-through
// at 0 leaves only the blur or glass. Glass groups start thinner (32%, as in the spec).
func groupFillAlpha(opacity: Double, background: BackgroundStyle) -> Double {
    let base = background == .glass ? 0.32 : 0.55
    return (base * opacity).rounded() / 100  // whole percent
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

// What each row shows for its folder label: the shortest run of last folders that no
// other folder in the list shares. "clients/bookmygarage" shows "bookmygarage", but
// "clients/acme" and "personal/acme" both keep their parent. "~/Developer" shows
// "Developer". A worktree keeps its branch ("claude-swipe @main"). The full label stays
// the key for icons, search and Settings.
func shortFolders(_ labels: [String]) -> [String: String] {
    func split(_ label: String) -> (path: [Substring], branch: String?) {
        let parts = label.components(separatedBy: " @")
        let branch = parts.count > 1 ? parts.dropFirst().joined(separator: " @") : nil
        return (parts[0].split(separator: "/"), branch)
    }
    let paths = Set(labels.map { split($0).path })
    var out: [String: String] = [:]
    for label in Set(labels) {
        let (path, branch) = split(label)
        guard !path.isEmpty else { out[label] = label; continue }
        var n = 1
        while n < path.count && paths.contains(where: { $0 != path && $0.suffix(n) == path.suffix(n) }) { n += 1 }
        let short = path.suffix(n).joined(separator: "/")
        out[label] = branch.map { short + " @" + $0 } ?? short
    }
    return out
}
