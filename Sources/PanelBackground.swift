// The panel's see-through layers:
// 1. PanelMaterial (Frosted only) + PanelTint: blur and theme tint across the full width.
// 2. GroupBackground: each group's fill (scaled by the same opacity), on Liquid Glass
//    when the background is Glass (macOS 26+).
//
// Measured 19 Nov 2026 (harness over a text backdrop, macOS 27): every public material
// and both glass styles blur text away completely; they differ only in tint. So there
// is one material, not a Light/Heavy choice, and See-through (opacity) is the only amount.

import AppKit
import SwiftUI

// Liquid Glass (NSGlassEffectView) is macOS 26+.
let glassAvailable: Bool = {
    if #available(macOS 26, *) { return true }
    return false
}()

// Frosted's material. .sidebar gave the most even blur in both themes in the harness
// images; .sheet, .windowBackground, .contentBackground and .underPageBackground are opaque.
let frostedMaterial: NSVisualEffectView.Material = .sidebar

// Layer 1's blur: behind-window, full panel. Hidden unless the background is Frosted.
struct PanelMaterial: NSViewRepresentable {
    let visible: Bool

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.blendingMode = .behindWindow
        v.state = .active
        v.material = frostedMaterial
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.isHidden = !visible }
}

// Layer 1's tint: the theme background at the chosen opacity. When see-through,
// a light rim on the left edge and a soft shine in the top left.
struct PanelTint: View {
    let opacity: Double
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(Theme.bg.opacity(opacity / 100))
            if opacity < 100 {
                let dark = scheme == .dark
                // 160° in CSS terms: from the top left, down and slightly right.
                LinearGradient(stops: [.init(color: .white.opacity(dark ? 0.10 : 0.55), location: 0),
                                       .init(color: .white.opacity(0), location: 0.35)],
                               startPoint: UnitPoint(x: 0.33, y: 0), endPoint: UnitPoint(x: 0.67, y: 1))
                Rectangle().fill(Color.white.opacity(dark ? 0.16 : 0.75)).frame(width: 1)
            }
        }
        .allowsHitTesting(false)
    }
}

// Liquid Glass behind a SwiftUI group (macOS 26+).
@available(macOS 26, *)
struct GlassView: NSViewRepresentable {
    let radius: CGFloat

    func makeNSView(context: Context) -> NSGlassEffectView {
        let v = NSGlassEffectView()
        v.style = .regular
        return v
    }

    func updateNSView(_ v: NSGlassEffectView, context: Context) { v.cornerRadius = radius }
}

// Layer 2: one per section group and the search pill.
struct GroupBackground: View {
    let look: AppearanceValues
    var radius: CGFloat = 12
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let shape = RoundedRectangle(cornerRadius: radius)
        let a = groupFillAlpha(opacity: look.opacity, background: look.background)
        let fill = dark ? Color(.sRGB, red: 48 / 255, green: 48 / 255, blue: 46 / 255, opacity: a)
                        : Color(.sRGB, red: 1, green: 1, blue: 1, opacity: a)
        ZStack {
            if look.background == .glass, #available(macOS 26, *) {
                GlassView(radius: radius)
            }
            shape.fill(fill)
            shape.strokeBorder(dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}
