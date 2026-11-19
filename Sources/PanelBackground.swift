// The panel's see-through layers (spec: "See-through background"):
// 1. PanelMaterial + PanelTint: blur and theme tint across the full width.
// 2. The edge fade: an alpha mask on layer 1 only, from fadeStops.
// 3. GroupBackground: each group's own fill and blur (or Liquid Glass on macOS 26+),
//    so rows read the same wherever they sit and never fade.

import AppKit
import SwiftUI

// False hides the Edge fade slider (the spec's fallback if the mask won't work).
let fadeSupported = true

// Liquid Glass (NSGlassEffectView) is macOS 26+.
let glassAvailable: Bool = {
    if #available(macOS 26, *) { return true }
    return false
}()

// Blur has no public radius, so Light and Heavy are two system materials.
// Light: .sidebar, the thinnest behind-window material. Heavy: .fullScreenUI,
// a much denser one. Unverified by eye; change here if they look too alike.
func blurMaterial(_ b: BlurLevel) -> NSVisualEffectView.Material? {
    switch b {
    case .off: return nil
    case .light: return .sidebar
    case .heavy: return .fullScreenUI
    }
}

// Horizontal alpha mask, left to right, rebuilt whenever the view's size changes.
final class FadingEffectView: NSVisualEffectView {
    var stops: [(location: Double, alpha: Double)] = [] { didSet { maskSize = .zero; needsLayout = true } }
    private var maskSize = NSSize.zero

    override func layout() {
        super.layout()
        guard bounds.size != maskSize else { return }
        maskSize = bounds.size
        maskImage = FadingEffectView.mask(stops, size: bounds.size)
    }

    static func mask(_ stops: [(location: Double, alpha: Double)], size: NSSize) -> NSImage? {
        guard !stops.isEmpty, size.width > 0, size.height > 0 else { return nil }
        var s = stops
        if let last = s.last, last.location < 1 { s.append((1, last.alpha)) }
        let colors = s.map { NSColor(white: 0, alpha: CGFloat($0.alpha)) }
        var locations = s.map { CGFloat($0.location) }
        guard let g = NSGradient(colors: colors, atLocations: &locations, colorSpace: .sRGB) else { return nil }
        return NSImage(size: size, flipped: false) { r in g.draw(in: r, angle: 0); return true }
    }
}

// Layer 1: behind-window blur, masked by the edge fade. Hidden when blur is off.
struct PanelMaterial: NSViewRepresentable {
    let blur: BlurLevel
    let fade: Double

    func makeNSView(context: Context) -> FadingEffectView {
        let v = FadingEffectView()
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }

    func updateNSView(_ v: FadingEffectView, context: Context) {
        if let m = blurMaterial(blur) { v.material = m }
        v.isHidden = blurMaterial(blur) == nil
        let s = fadeStops(fade)
        if s.map(\.location) != v.stops.map(\.location) || s.map(\.alpha) != v.stops.map(\.alpha) { v.stops = s }
    }
}

func fadeGradient(_ fade: Double) -> LinearGradient {
    var s = fadeStops(fade).map { Gradient.Stop(color: .black.opacity($0.alpha), location: $0.location) }
    if let last = s.last, last.location < 1 { s.append(.init(color: .black, location: 1)) }
    return LinearGradient(stops: s, startPoint: .leading, endPoint: .trailing)
}

// Layer 1's tint: the theme background at the chosen opacity, under the same fade.
// With the fade at 0 and the panel see-through, a light rim and a top-left shine.
struct PanelTint: View {
    let opacity: Double
    let fade: Double
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tint = Rectangle().fill(Theme.bg.opacity(opacity / 100))
        ZStack(alignment: .leading) {
            if fade > 0 { tint.mask(fadeGradient(fade)) } else { tint }
            if fade == 0 && opacity < 100 {
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
    let style: GlassStyle
    let radius: CGFloat

    func makeNSView(context: Context) -> NSGlassEffectView { NSGlassEffectView() }

    func updateNSView(_ v: NSGlassEffectView, context: Context) {
        v.style = style == .clear ? .clear : .regular
        v.cornerRadius = radius
    }
}

// A group's own blur when glass is off.
struct GroupMaterial: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.blendingMode = .behindWindow
        v.state = .active
        v.wantsLayer = true
        v.layer?.cornerRadius = 12
        v.layer?.masksToBounds = true
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}

// Layer 3: one per section group and the search pill.
struct GroupBackground: View {
    let glass: GlassStyle
    let blur: BlurLevel
    var radius: CGFloat = 12
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let shape = RoundedRectangle(cornerRadius: radius)
        let fillAlpha = glass == .clear ? (dark ? 0.32 : 0.34) : 0.55
        let fill = dark ? Color(.sRGB, red: 48 / 255, green: 48 / 255, blue: 46 / 255, opacity: fillAlpha)
                        : Color(.sRGB, red: 1, green: 1, blue: 1, opacity: fillAlpha)
        ZStack {
            if glass != .off, #available(macOS 26, *) {
                GlassView(style: glass, radius: radius)
            } else if let m = blurMaterial(blur) {
                GroupMaterial(material: m).clipShape(shape)
            }
            shape.fill(fill)
            shape.strokeBorder(dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}
