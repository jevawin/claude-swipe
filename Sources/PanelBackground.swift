// The panel's see-through layers:
// 1. PanelMaterial (Frosted only) + PanelTint: blur and theme tint across the full width.
// 2. GroupBackground: each group's fill (solid on Frosted, scaled by opacity on Glass), on Liquid Glass
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

// Frosted's material. Measured 19 Nov 2026 (harness, See-through 100%, gap pixel of the
// panel over a white / dark window): .sidebar paints its own theme tint so thickly that
// See-through barely changed anything (dark theme over dark window: 59 vs 50 solid).
// .hudWindow has the thinnest tint of the public materials tried (dark over white 168
// vs 103 for .sidebar; light over dark 168 vs 224) and still blurs text away.
// .sheet, .windowBackground, .contentBackground and .underPageBackground are opaque.
let frostedMaterial: NSVisualEffectView.Material = .hudWindow

// Layer 1's blur: behind-window, full panel. Hidden unless the background is Frosted.
// It fades with See-through, so 100% see-through is fully clear: no blur at all
// (Jamie, 23 Nov 2026; before, the blur stayed at full strength and only the tint faded).
// Unverified: that alphaValue on a behind-window NSVisualEffectView fades the blur smoothly.
// Offscreen renders can't draw it; Jamie to check on screen.
struct PanelMaterial: NSViewRepresentable {
    let visible: Bool
    var alpha: Double = 1

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.blendingMode = .behindWindow
        v.state = .active
        v.material = frostedMaterial
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.isHidden = !visible || alpha <= 0
        v.alphaValue = CGFloat(alpha)
    }
}

// Layer 1's tint: the theme background at the chosen opacity. When see-through,
// a light rim on the left edge and a soft shine in the top left.
struct PanelTint: View {
    let opacity: Double
    var sheen: Double = 1  // scales the rim and shine; Frosted fades them out towards 100% see-through
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(Theme.panelBg.opacity(opacity / 100))
            if opacity < 100 {
                let dark = scheme == .dark
                // 160° in CSS terms: from the top left, down and slightly right.
                LinearGradient(stops: [.init(color: .white.opacity((dark ? 0.10 : 0.55) * sheen), location: 0),
                                       .init(color: .white.opacity(0), location: 0.35)],
                               startPoint: UnitPoint(x: 0.33, y: 0), endPoint: UnitPoint(x: 0.67, y: 1))
                Rectangle().fill(Color.white.opacity((dark ? 0.16 : 0.75) * sheen)).frame(width: 1)
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
            if look.background == .glass {
                // Depth for Glass: a sheen across the top and a rim lit from the top left,
                // fading to a faint edge at the bottom right.
                shape.fill(LinearGradient(stops: [.init(color: .white.opacity(dark ? 0.10 : 0.35), location: 0),
                                                  .init(color: .white.opacity(0), location: 0.45)],
                                          startPoint: .top, endPoint: .bottom))
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(dark ? 0.35 : 0.9),
                                                           .white.opacity(dark ? 0.05 : 0.25),
                                                           .white.opacity(dark ? 0.15 : 0.5)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            } else {
                shape.strokeBorder(dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }
}

// Glass groups float: a soft shadow under each one. Applied after the group is clipped,
// so the shadow isn't cut off.
struct GlassLift: ViewModifier {
    let on: Bool
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content.shadow(color: .black.opacity(on ? (scheme == .dark ? 0.35 : 0.12) : 0), radius: 8, x: 0, y: 3)
    }
}
