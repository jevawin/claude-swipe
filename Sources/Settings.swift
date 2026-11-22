// Settings: stored preferences, the Settings window and the first-run screen.
// All user-facing text comes from docs/superpowers/specs/2026-11-05-settings-copy.md.

import AppKit
import ServiceManagement
import SwiftUI

// MARK: - Preferences

// One place for every setting. Writes go straight to UserDefaults
// (com.jevawin.claude-swipe); settings the script uses trigger a refresh.
final class Prefs: ObservableObject {
    static let shared = Prefs()
    private let d = UserDefaults.standard
    var onScriptChange: () -> Void = {}
    private var pending: DispatchWorkItem?

    @Published var theme: String { didSet { d.set(theme, forKey: "theme"); applyTheme() } }
    // The panel's see-through values, one set for both themes. Loaded through clampedToFloor.
    @Published var appearance: AppearanceValues {
        didSet {
            d.set(appearance.opacity, forKey: "panelOpacity"); d.set(appearance.background.rawValue, forKey: "panelBackground")
        }
    }
    @Published var density: Density { didSet { d.set(density.rawValue, forKey: "density") } }
    // Text size for rows, 0.85...1.15 of each preset's sizes.
    @Published var textScale: Double { didSet { d.set(textScale, forKey: "textScale") } }
    // Summary lines per preset (Compact has none).
    @Published var linesDefault: Int { didSet { d.set(linesDefault, forKey: "summaryLinesDefault") } }
    @Published var linesCozy: Int { didSet { d.set(linesCozy, forKey: "summaryLinesCozy") } }
    // Where topic icons come from: "subject" or "folder".
    @Published var iconSource: String { didSet { d.set(iconSource, forKey: "iconSource"); scriptChanged() } }
    @Published var homeFolder: String { didSet { d.set(homeFolder, forKey: "homeFolder") } }
    @Published var minimiseOthers: Bool { didSet { d.set(minimiseOthers, forKey: "minimiseOthers") } }
    // Percent to fade Done cards by. Capped at 80 so they stay readable.
    @Published var doneFade: Double { didSet { d.set(doneFade, forKey: "doneFade") } }
    // Whether the Done section is open; remembers the last click.
    @Published var showDone: Bool { didSet { d.set(showDone, forKey: "showDone") } }
    // Model changes only affect new picks, so no refresh.
    @Published var aiModel: String { didSet { d.set(aiModel, forKey: "aiModel") } }
    @Published var aiSort: Bool { didSet { d.set(aiSort, forKey: "aiSort"); scriptChanged() } }
    @Published var aiIcon: Bool { didSet { d.set(aiIcon, forKey: "aiIcon"); scriptChanged() } }
    @Published var aiClear: Bool { didSet { d.set(aiClear, forKey: "aiClear"); scriptChanged() } }
    // Reduce transparency or Increase contrast is on: the panel draws solid (display only;
    // saved values are kept). Updated live when either system setting changes.
    @Published var systemSolid = Prefs.readSystemSolid()
    @Published var loginOn = false  // mirrors SMAppService; set by AppDelegate.updateLoginItem

    var onboarded: Bool {
        get { d.bool(forKey: "onboarded") }
        set { d.set(newValue, forKey: "onboarded") }
    }

    init() {
        migrateIconPrefs(d)
        d.register(defaults: [
            "theme": "auto", "iconSource": "subject",
            "panelOpacity": defaultAppearance.opacity, "panelBackground": defaultAppearance.background.rawValue,
            "density": Density.standard.rawValue, "textScale": 1.0, "summaryLinesDefault": 2, "summaryLinesCozy": 1,
            "homeFolder": "", "minimiseOthers": false, "doneFade": 40.0, "showDone": true, "aiModel": "haiku",
            "aiSort": false, "aiIcon": false, "aiClear": false,
        ])
        theme = d.string(forKey: "theme") ?? "auto"
        appearance = clampedToFloor(AppearanceValues(
            background: BackgroundStyle(rawValue: d.string(forKey: "panelBackground") ?? "") ?? defaultAppearance.background,
            opacity: d.double(forKey: "panelOpacity")))
        // Before 22 Nov 2026 "cozy" was the roomy preset, now called Default.
        if !d.bool(forKey: "densityRenamed") {
            if d.string(forKey: "density") == "cozy" { d.set(Density.standard.rawValue, forKey: "density") }
            d.set(true, forKey: "densityRenamed")
        }
        density = Density(rawValue: d.string(forKey: "density") ?? "") ?? .standard
        textScale = min(1.15, max(0.85, d.double(forKey: "textScale")))
        linesDefault = min(3, max(1, d.integer(forKey: "summaryLinesDefault")))
        linesCozy = min(3, max(1, d.integer(forKey: "summaryLinesCozy")))
        iconSource = d.string(forKey: "iconSource") ?? "subject"
        homeFolder = d.string(forKey: "homeFolder") ?? ""
        minimiseOthers = d.bool(forKey: "minimiseOthers")
        doneFade = min(80, max(0, d.double(forKey: "doneFade")))
        showDone = d.bool(forKey: "showDone")
        aiModel = d.string(forKey: "aiModel") ?? "haiku"
        aiSort = d.bool(forKey: "aiSort")
        aiIcon = d.bool(forKey: "aiIcon")
        aiClear = d.bool(forKey: "aiClear")
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.systemSolid = Prefs.readSystemSolid() }
    }

    static func readSystemSolid() -> Bool {
        let w = NSWorkspace.shared
        return w.accessibilityDisplayShouldReduceTransparency || w.accessibilityDisplayShouldIncreaseContrast
    }

    // Coalesces several switches flipped at once (the welcome switch sets two) into one refresh.
    private func scriptChanged() {
        pending?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.onScriptChange() }
        pending = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: w)
    }

    func applyTheme() {
        NSApp.appearance = theme == "light" ? NSAppearance(named: .aqua)
            : theme == "dark" ? NSAppearance(named: .darkAqua) : nil
    }

    // Theme, density and the four background values back to their defaults.
    func resetAppearance() {
        theme = "auto"
        appearance = defaultAppearance
        density = .standard
        textScale = 1.0
        linesDefault = 2
        linesCozy = 1
    }

    func summaryLines(_ d: Density) -> Int { d == .cozy ? linesCozy : d == .standard ? linesDefault : 0 }

    var pickIcon: Bool { aiIcon }
    var anyAI: Bool { aiSort || aiClear || pickIcon }
    var modelName: String { aiModel == "sonnet" ? "Sonnet" : "Haiku" }

    // Flags for recent_chats.py. Every AI flag is opt-in, so none set means no requests.
    var scriptArgs: [String] {
        var a = ["--model", aiModel, "--icon-from", iconSource]
        if aiSort { a.append("--sort") }
        if aiClear { a.append("--clear") }
        if pickIcon { a += ["--icon", iconSource] }
        return a
    }
}

// MARK: - System status

enum ClaudeCLI { case unknown, ready, signedOut, missing }

// Whether the claude command is there and signed in, and whether Accessibility
// is allowed. The Accessibility check runs every second while a window is open.
final class SystemStatus: ObservableObject {
    @Published var claude: ClaudeCLI = .unknown
    @Published var axAllowed = AXIsProcessTrusted()
    private var timer: Timer?

    func start() {
        checkClaude()
        axAllowed = AXIsProcessTrusted()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            let v = AXIsProcessTrusted()
            if self?.axAllowed != v { self?.axAllowed = v }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    // `claude auth status --json` returns {"loggedIn": bool, ...} (measured, 0.13s).
    func checkClaude() {
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            p.arguments = ["claude", "auth", "status", "--json"]
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            p.environment = env
            let out = Pipe()
            p.standardOutput = out
            p.standardError = Pipe()
            var result = ClaudeCLI.missing
            if (try? p.run()) != nil {
                let data = out.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                if p.terminationStatus == 127 {
                    result = .missing  // env: command not found
                } else if let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    result = (j["loggedIn"] as? Bool) == true ? .ready : .signedOut
                } else {
                    result = .signedOut
                }
            }
            DispatchQueue.main.async { self.claude = result }
        }
    }
}

// MARK: - Shared pieces

// Lucide "settings-2" (two sliders), drawn from its 24×24 SVG paths.
struct Settings2Icon: Shape {
    func path(in r: CGRect) -> Path {
        let s = min(r.width, r.height) / 24
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * s, y: r.minY + y * s) }
        var p = Path()
        p.move(to: pt(20, 7)); p.addLine(to: pt(11, 7))
        p.move(to: pt(14, 17)); p.addLine(to: pt(5, 17))
        p.addEllipse(in: CGRect(origin: pt(14, 14), size: CGSize(width: 6 * s, height: 6 * s)))
        p.addEllipse(in: CGRect(origin: pt(4, 4), size: CGSize(width: 6 * s, height: 6 * s)))
        return p
    }
}

struct Settings2Image: View {
    var size: CGFloat = 15
    var body: some View {
        Settings2Icon()
            .stroke(style: StrokeStyle(lineWidth: size / 24 * 2, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
    }
}

enum Warn {
    static let bg = themed(NSColor(srgbRed: 0.992, green: 0.945, blue: 0.906, alpha: 1),   // #FDF1E7
                           NSColor(srgbRed: 0.227, green: 0.165, blue: 0.125, alpha: 1))   // #3A2A20
    static let border = themed(NSColor(srgbRed: 0.949, green: 0.831, blue: 0.749, alpha: 1), // #F2D4BF
                               NSColor(srgbRed: 0.42, green: 0.275, blue: 0.188, alpha: 1))  // #6B4630
    static let text = themed(NSColor(srgbRed: 0.361, green: 0.184, blue: 0.09, alpha: 1),  // #5C2F17
                             NSColor(srgbRed: 0.961, green: 0.851, blue: 0.776, alpha: 1)) // #F5D9C6
}

struct WarningBox: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 12)).padding(.top, 1)
                .accessibilityHidden(true)
            Text(text).font(.system(size: 12)).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Warn.text)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Warn.bg))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Warn.border, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Warning: \(text)")
    }
}

// Green or red light with a short state, e.g. "claude command found and signed in".
struct StatusLight: View {
    let ok: Bool
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(ok ? statusStyle["done"]!.color : statusStyle["blocked"]!.color)
                .frame(width: 8, height: 8).accessibilityHidden(true)
            Text(text).font(.system(size: 12)).foregroundStyle(Theme.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct ClaudeStatusLine: View {
    let state: ClaudeCLI
    var body: some View {
        if state != .unknown {
            StatusLight(ok: state == .ready, text: state == .ready ? "claude command found and signed in"
                        : state == .signedOut ? "claude command found but not signed in"
                        : "claude command not found")
        }
    }
}

// Neutral privacy callout with a padlock, next to the warnings.
struct PrivacyNote: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock").font(.system(size: 12)).padding(.top, 1).accessibilityHidden(true)
            Text(text).font(.system(size: 12)).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.text.opacity(0.85))
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.cardHover))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Privacy: \(text)")
    }
}

let privacyLocal = "Your chats stay on your Mac. ClaudeSwipe reads Claude's chat files on this Mac, has no servers of its own, and sends nothing anywhere unless you turn on the AI features."

// A labelled setting: title and helper text on the left, the control on the right.
struct Row<Control: View>: View {
    let title: String
    var helper: String? = nil
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                if let h = helper {
                    Text(h).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        .lineSpacing(1).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control()
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }
}

// Rounded white group holding rows, with hairlines between them.
struct Group_<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }
}

struct Hairline: View {
    var body: some View { Rectangle().fill(Theme.border).frame(height: 1) }
}

// First click per launch: macOS's own prompt, which adds ClaudeSwipe to the list and
// has its own Open System Settings button. Later clicks open the pane directly.
// Doing both at once showed the prompt and the pane together.
private var promptedThisLaunch = false
func openAccessibilitySettings() {
    if !promptedThisLaunch {
        promptedThisLaunch = true
        UserDefaults.standard.set(true, forKey: "axPrompted")
        if !AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) { return }
    }
    if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
        NSWorkspace.shared.open(u)
    }
}

let aiWarningSettings = "These features use your own Claude plan. When chats are new or change, ClaudeSwipe sends small requests through your claude login. They include each chat's title, your first and latest messages, and Claude's last reply. All of it counts against your plan."
let aiWarningWelcome = "This uses your own Claude plan. When chats are new or change, ClaudeSwipe sends small requests through your claude login. They include each chat's title, your first and latest messages, and Claude's last reply. All of it counts against your plan."
let minimiseHelper = "When you open a chat, every other Claude window goes to the Dock. Hold Option while you click a chat to flip this setting for that one click."

// MARK: - Settings window

struct SettingsActions {
    let showWelcome: () -> Void
    let repick: () -> Void
    let setLogin: (Bool) -> Void
}

struct SettingsView: View {
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject var status: SystemStatus
    @ObservedObject var store: Store
    let actions: SettingsActions
    @LocalState private var pane: String

    init(status: SystemStatus, store: Store, actions: SettingsActions, initialPane: String = "General") {
        self.status = status; self.store = store; self.actions = actions
        _pane = LocalState(wrappedValue: initialPane)
    }

    let panes: [(name: String, icon: String)] = [
        ("General", ""), ("Appearance", "circle.lefthalf.filled"), ("Cards", "rectangle.stack"), ("Windows", "macwindow.on.rectangle"), ("AI", "sparkles"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(panes, id: \.name) { p in
                    let on = pane == p.name
                    Button { pane = p.name } label: {
                        HStack(spacing: 8) {
                            if p.icon.isEmpty { Settings2Image() } else {
                                Image(systemName: p.icon).font(.system(size: 13)).frame(width: 15)
                            }
                            Text(p.name).font(.system(size: 13, weight: on ? .medium : .regular))
                            Spacer()
                        }
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .foregroundStyle(on ? Color.white : Theme.text)
                        .background(RoundedRectangle(cornerRadius: 6).fill(on ? Theme.brand : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 12)
            .frame(width: 200)
            .background(Theme.sidebar)
            Rectangle().fill(Theme.border).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(pane).font(.system(size: 18, weight: .semibold)).accessibilityAddTraits(.isHeader)
                    switch pane {
                    case "Appearance": appearancePane
                    case "Cards": cards
                    case "Windows": windows
                    case "AI": ai
                    default: general
                    }
                }
                .padding(.horizontal, 24).padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(Theme.text)
        .background(Theme.bg)
        .frame(minWidth: 760, minHeight: 580)
    }

    var general: some View {
        VStack(alignment: .leading, spacing: 14) {
        Group_ {
            Row(title: "Launch at login") {
                Toggle("Launch at login", isOn: Binding(get: { prefs.loginOn }, set: { actions.setLogin($0) }))
                    .toggleStyle(.switch).labelsHidden()
            }
            Hairline()
            Row(title: "Welcome screen") {
                Button("Show again") { actions.showWelcome() }
            }
        }
        PrivacyNote(text: privacyLocal)
        }
    }

    // The four background values are greyed out while macOS forces the panel solid.
    var appearancePane: some View {
        let solid = prefs.systemSolid
        let look = effective(prefs.appearance, solidRequired: false, glassAvailable: glassAvailable)
        let isDefault = prefs.appearance == defaultAppearance && prefs.theme == "auto" && prefs.density == .standard && prefs.textScale == 1.0
        return VStack(alignment: .leading, spacing: 14) {
            if solid {
                WarningBox(text: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
                    ? "Reduce transparency is on in macOS System Settings, so the panel is solid. Turn it off there to use these controls."
                    : "Increase contrast is on in macOS System Settings, so the panel is solid. Turn it off there to use these controls.")
            }
            Group_ {
                Row(title: "Theme") {
                    Picker("Theme", selection: $prefs.theme) {
                        Text("Auto").tag("auto"); Text("Light").tag("light"); Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
            }
            Group_ {
                tiles("Background", helper: glassAvailable ? "Frosted blurs what's behind. Glass puts each group of chats on Liquid Glass."
                                                           : "Frosted blurs what's behind. Glass needs macOS 26 or later.",
                      BackgroundStyle.allCases, selected: look.background, name: { $0.rawValue.capitalized },
                      set: { prefs.appearance.background = $0 },
                      look: { var v = prefs.appearance; v.background = $0; return effective(v, solidRequired: false, glassAvailable: true) },
                      disabled: { $0 == .glass && !glassAvailable })
                    .disabled(solid).opacity(solid ? 0.5 : 1)
                Hairline()
                Row(title: "See-through", helper: "How much of what's behind shows through your chats. Higher is harder to read over busy windows.") {
                    HStack(spacing: 8) {
                        SliderPreview(values: { var v = prefs.appearance; v.opacity = 100 - $0; return v },
                                      value: 100 - prefs.appearance.opacity, range: 0...(100 - opacityFloor))
                        Slider(value: Binding(get: { 100 - prefs.appearance.opacity }, set: { prefs.appearance.opacity = 100 - $0 }),
                               in: 0...(100 - opacityFloor), step: 1).frame(width: 130)
                        Text("\(Int(100 - prefs.appearance.opacity))%").monospacedDigit()
                            .foregroundStyle(Theme.secondary).frame(width: 38, alignment: .trailing)
                    }
                }
                .disabled(solid || look.background == .solid).opacity(solid || look.background == .solid ? 0.5 : 1)
            }
            Group_ {
                tiles("Density", helper: "Default shows each chat's summary. Cozy is the same, tighter. Compact fits more chats on one line each.",
                      Density.allCases, selected: prefs.density, name: { $0.label },
                      set: { prefs.density = $0 }, look: { _ in look }, density: { $0 })
                Hairline()
                Row(title: "Text size", helper: "Shrinks or grows text and spacing in any density.") {
                    HStack(spacing: 8) {
                        Slider(value: $prefs.textScale, in: 0.85...1.15, step: 0.05).frame(width: 130)
                        Text("\(Int((prefs.textScale * 100).rounded()))%").monospacedDigit()
                            .foregroundStyle(Theme.secondary).frame(width: 44, alignment: .trailing)
                    }
                }
                Hairline()
                Row(title: "Summary lines", helper: prefs.density == .compact ? "Compact shows no summary." : "How much of each chat's summary shows.") {
                    Picker("Summary lines", selection: Binding(
                        get: { prefs.density == .cozy ? prefs.linesCozy : prefs.linesDefault },
                        set: { if prefs.density == .cozy { prefs.linesCozy = $0 } else { prefs.linesDefault = $0 } })) {
                        Text("1").tag(1); Text("2").tag(2); Text("3").tag(3)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                .disabled(prefs.density == .compact).opacity(prefs.density == .compact ? 0.5 : 1)
            }
            HStack {
                Spacer()
                Button("Reset to defaults") { prefs.resetAppearance() }.disabled(isDefault)
            }
        }
    }

    // A row of picture tiles under a title, one per choice.
    func tiles<T: Hashable>(_ title: String, helper: String, _ all: [T], selected: T, name: @escaping (T) -> String,
                            set: @escaping (T) -> Void, look: @escaping (T) -> AppearanceValues,
                            density: ((T) -> Density)? = nil, disabled: @escaping (T) -> Bool = { _ in false }) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(helper).font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
            HStack(spacing: 14) {
                ForEach(all, id: \.self) { c in
                    PictureTile(label: name(c), selected: selected == c, action: { set(c) }) {
                        if let d = density?(c) { DensityPicture(density: d) }
                        else { MiniPanel(values: look(c), density: prefs.density) }
                    }
                    .disabled(disabled(c)).opacity(disabled(c) ? 0.5 : 1)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var folders: [String] {
        var f = Array(Set(store.chats.map(\.folder))).sorted()
        if !prefs.homeFolder.isEmpty && !f.contains(prefs.homeFolder) { f.insert(prefs.homeFolder, at: 0) }
        return f
    }

    var cards: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Preview").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.secondary)
                ChatRow(chat: sampleChat, selected: false, density: prefs.density, divider: false)
                    .background(GroupBackground(look: AppearanceValues(background: .solid, opacity: 100)))
                    .frame(maxWidth: 440)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.bg))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
            }
            Group_ {
                Row(title: "Topic icon from",
                    helper: "Claude picks these, so AI must be on. Right-click a chat to pick your own.") {
                    Picker("Topic icon from", selection: $prefs.iconSource) {
                        Text("Chat subject").tag("subject"); Text("Folder").tag("folder")
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                Hairline()
                Row(title: "Hide folder label for",
                    helper: "Most chats sit in one folder. Hide that folder's label to keep cards tidy.") {
                    Picker("Hide folder label for", selection: $prefs.homeFolder) {
                        Text("None").tag("")
                        ForEach(folders, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden().frame(maxWidth: 220)
                }
                Hairline()
                Row(title: "Fade done chats",
                    helper: "Done chats show fainter so open work stands out. 80% at most, so they stay readable.") {
                    HStack(spacing: 8) {
                        Slider(value: $prefs.doneFade, in: 0...80, step: 5).frame(width: 130)
                        Text("\(Int(prefs.doneFade))%").monospacedDigit()
                            .foregroundStyle(Theme.secondary).frame(width: 34, alignment: .trailing)
                        Button("No fade") { prefs.doneFade = 0 }.disabled(prefs.doneFade == 0)
                    }
                }
            }
        }
    }

    var sampleChat: Chat {
        Chat(id: "preview", status: "waiting", why: "Want me to send the draft to the team now?",
             title: "Write the launch post", folder: "clients/acme",
             age: 600, engaged: 600, section: "today", app: "desktop", desktop_id: nil, cwd: nil,
             icon: "pencil", own_icon: nil)
    }

    var windows: some View {
        JumpBlock(status: status, minimiseTitle: "Minimise other Claude windows")
    }

    var ai: some View {
        let ready = status.claude == .ready
        return VStack(alignment: .leading, spacing: 14) {
            Group_ { AIIntro(status: status, warning: aiWarningSettings) }
            Group_ {
                Row(title: "Model", helper: "Haiku is faster and uses less of your plan") {
                    Picker("Model", selection: $prefs.aiModel) {
                        Text("Haiku").tag("haiku"); Text("Sonnet").tag("sonnet")
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                Hairline()
                Row(title: "Sort unclear chats", helper: "Off: those chats show as \"unsure\"") {
                    Toggle("Sort unclear chats", isOn: $prefs.aiSort).toggleStyle(.switch).labelsHidden()
                }
                Hairline()
                Row(title: "Pick a topic icon for each chat", helper: "Off: chats show their state icon, or your own pick") {
                    Toggle("Pick a topic icon for each chat", isOn: $prefs.aiIcon).toggleStyle(.switch).labelsHidden()
                }
                Hairline()
                Row(title: "Ready to clear section",
                    helper: "Checks each done chat once more to see if the whole job is finished. Chats that pass get their own section.") {
                    Toggle("Ready to clear section", isOn: $prefs.aiClear).toggleStyle(.switch).labelsHidden()
                }
            }
            .disabled(!ready)
            Group_ {
                Row(title: "Re-pick all topic icons",
                    helper: "Changing the model or icon source only affects new chats. Re-pick asks Claude again for every chat from the last 7 days, using your plan. Your own picks stay.") {
                    Button("Re-pick…") { actions.repick() }
                }
            }
            .disabled(!ready || !prefs.pickIcon)
        }
    }
}

// MARK: - First-run screen

struct WelcomeView: View {
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject var status: SystemStatus
    let finish: () -> Void  // closes the window and shows the panel
    @LocalState private var step: Int

    init(status: SystemStatus, finish: @escaping () -> Void, initialStep: Int = 1) {
        self.status = status; self.finish = finish
        _step = LocalState(wrappedValue: initialStep)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch step {
                    case 2: extras
                    case 3: ready
                    default: welcome
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Hairline()
            HStack {
                Text("Step \(step) of 3").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                Spacer()
                if step == 2 { Button("Back") { step = 1 } }
                if step < 3 {
                    Button("Continue") { step += 1 }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Show my chats") { finish() }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
        .foregroundStyle(Theme.text)
        .background(Theme.bg)
        .frame(width: 560, height: 680)
    }

    func title(_ s: String) -> some View {
        Text(s).font(.system(size: 22, weight: .semibold)).accessibilityAddTraits(.isHeader)
            .fixedSize(horizontal: false, vertical: true)
    }

    func body(_ s: String) -> some View {
        Text(s).font(.system(size: 14)).foregroundStyle(Theme.text.opacity(0.85))
            .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
    }

    var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            title("Your Claude chats, one swipe away")
            body("ClaudeSwipe shows which chats are waiting for you, which are running and which are done. There are three ways to open it:")
            Group_ {
                Row(title: "Push the cursor into the right edge",
                    helper: "Hold it there for a moment and the panel slides out") { way("arrow.right.to.line") }
                Hairline()
                Row(title: "Press Control-Option-C", helper: "Works from any app. Press again to close.") {
                    Text("⌃⌥C").font(.system(size: 14, weight: .medium, design: .rounded))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.border, lineWidth: 1))
                        .accessibilityHidden(true)
                }
                Hairline()
                Row(title: "Click the menu bar icon", helper: "Settings are there too") {
                    way("bubble.left.and.text.bubble.right")
                }
            }
            PrivacyNote(text: privacyLocal)
        }
    }

    func way(_ icon: String) -> some View {
        Image(systemName: icon).font(.system(size: 18)).foregroundStyle(Theme.brand).frame(width: 40)
            .accessibilityHidden(true)
    }

    var extras: some View {
        VStack(alignment: .leading, spacing: 16) {
            title("Two optional extras")
            body("One needs a Mac permission. The other uses your Claude plan. You can skip either one and change your mind later in Settings.")
            JumpBlock(status: status, minimiseTitle: "Also minimise other Claude windows")
            Group_ {
                AIIntro(status: status, warning: aiWarningWelcome)
                Hairline()
                Row(title: "Use my Claude plan", helper: "Off until you turn it on. Pick the model and more in Settings › AI.") {
                    Toggle("Use my Claude plan", isOn: Binding(
                        get: { prefs.aiSort && prefs.aiIcon },
                        set: { prefs.aiSort = $0; prefs.aiIcon = $0 }))
                        .toggleStyle(.switch).labelsHidden()
                }
                .disabled(status.claude != .ready)
            }
        }
    }

    var ready: some View {
        VStack(alignment: .leading, spacing: 16) {
            title("You're ready")
            body("Everything else lives in Settings. Open it from the menu bar icon.")
        }
    }
}

// The two extras, shared by the first-run screen and Settings, so they look the same in both.

// Where macOS keeps the permission. Named "Device Control and Data Access" on
// macOS 27 (as seen by Jamie, not measured here); "Accessibility" before that.
let permissionPath = "System Settings › Privacy & Security › Device Control and Data Access (called Accessibility on older macOS)"

struct JumpBlock: View {
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject var status: SystemStatus
    let minimiseTitle: String

    var body: some View {
        Group_ {
            VStack(alignment: .leading, spacing: 12) {
                Text("Jump to the right window").font(.system(size: 15, weight: .semibold))
                Text("If a chat is already open in its own window, clicking it brings that window to the front. Without this, the chat opens in the main Claude window instead.")
                    .font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: 14) {
                    Demo(chatInFront: false, label: "Picture: the chat window sits behind other Claude windows",
                         caption: "Before: chat hidden behind other windows")
                    Demo(chatInFront: true, label: "Picture: the chat window is in front of the others",
                         caption: "After: chat in front")
                }
                HStack(spacing: 12) {
                    Button("Open System Settings") { openAccessibilitySettings() }
                    StatusLight(ok: status.axAllowed, text: status.axAllowed
                                ? "Window permission allowed" : "Window permission not allowed")
                }
                Text("Needs a Mac permission. Turn on ClaudeSwipe in \(permissionPath).")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                PrivacyNote(text: "ClaudeSwipe only uses this to find, raise and minimise Claude's windows. It reads their titles, never what is in them.")
            }
            .padding(14)
            Hairline()
            Row(title: minimiseTitle, helper: minimiseHelper) {
                Toggle(minimiseTitle, isOn: $prefs.minimiseOthers).toggleStyle(.switch).labelsHidden()
            }
        }
    }
}

struct AIIntro: View {
    @ObservedObject var status: SystemStatus
    let warning: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sort unclear chats and pick topic icons").font(.system(size: 15, weight: .semibold))
            Text("Sometimes ClaudeSwipe cannot tell if a chat needs you or is done. With this on, Claude reads your latest message and its last reply, and decides. It can also pick a topic icon for each chat.")
                .font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 14) {
                SortDemo(sorted: false, label: "Picture: a chat marked unsure, with no topic icon",
                         caption: "Before: chat marked unsure, no topic icon")
                SortDemo(sorted: true, label: "Picture: the same chat marked done, with a topic icon",
                         caption: "After: chat sorted, with a topic icon")
            }
            WarningBox(text: warning)
            PrivacyNote(text: "ClaudeSwipe never signs in to your Claude account. It uses the claude command you already set up, and only checks that you are signed in.")
            ClaudeStatusLine(state: status.claude)
        }
        .padding(14)
    }
}

// Before/after picture of one chat: unsure with its state icon, then sorted with a topic icon.
struct SortDemo: View {
    let sorted: Bool
    let label: String
    let caption: String

    var body: some View {
        let st = statusStyle[sorted ? "done" : "unsure"]!
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Theme.bg)
                HStack(alignment: .top, spacing: 8) {
                    StateIcon(symbol: sorted ? "banknote" : st.icon, color: st.color, size: 26)
                    VStack(alignment: .leading, spacing: 5) {
                        RoundedRectangle(cornerRadius: 2).fill(Theme.text.opacity(0.7)).frame(width: 70, height: 5)
                        RoundedRectangle(cornerRadius: 2).fill(Theme.border).frame(width: 46, height: 4)
                        RoundedRectangle(cornerRadius: 2).fill(Theme.border).frame(width: 90, height: 4)
                    }
                    .padding(.top, 3)
                }
                .padding(10)
                .frame(width: 170, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
            }
            .frame(height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isImage)
            Text(caption).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}

// Before/after picture: two simple windows, caption below (never on top).
struct Demo: View {
    let chatInFront: Bool
    let label: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8).fill(Theme.bg)
                if chatInFront {
                    mini(highlight: false).frame(width: 120, height: 70).offset(x: 12, y: 12).opacity(0.5)
                    mini(highlight: true).frame(width: 130, height: 76).offset(x: 54, y: 30)
                } else {
                    mini(highlight: true).frame(width: 130, height: 76).offset(x: 54, y: 30).opacity(0.5)
                    mini(highlight: false).frame(width: 120, height: 70).offset(x: 12, y: 12)
                    mini(highlight: false).frame(width: 110, height: 64).offset(x: 82, y: 44)
                }
            }
            .frame(height: 124)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isImage)
            Text(caption).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    func mini(highlight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in Circle().fill(Theme.border).frame(width: 5, height: 5) }
            }
            RoundedRectangle(cornerRadius: 2).fill(highlight ? Theme.brand : Theme.border).frame(width: 60, height: 5)
            RoundedRectangle(cornerRadius: 2).fill(Theme.border).frame(width: 80, height: 4)
            RoundedRectangle(cornerRadius: 2).fill(Theme.border).frame(width: 50, height: 4)
            Spacer(minLength: 0)
        }
        .padding(7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(highlight ? Theme.brand : Theme.border, lineWidth: highlight ? 1.5 : 1))
    }
}

// MARK: - Appearance pane pieces

// A mini desktop with a mini panel on its right, drawn in the given style. Used by
// the picture tiles and the slider previews. A sketch, not the real material.
struct MiniPanel: View {
    let values: AppearanceValues
    var density: Density = .standard
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { g in
            let dark = scheme == .dark
            let w = g.size.width, h = g.size.height
            let pw = w * 0.5
            let window = VStack(alignment: .leading, spacing: 3) {
                ForEach(0..<4, id: \.self) { _ in Capsule().fill(Color.black.opacity(0.55)).frame(height: 2.5) }
            }
            .padding(5)
            .frame(width: w * 0.7, height: h * 0.62, alignment: .topLeading)
            .background(Color.white)
            .offset(x: w * 0.12, y: h * 0.18)
            ZStack(alignment: .topLeading) {
                // Desktop: a light window over a darker wallpaper, so see-through shows.
                LinearGradient(colors: [Color(nsColor: hsl(210, 40, 55)), Color(nsColor: hsl(262, 35, 45))],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                window
                // The panel: Frosted blurs everything behind it; Glass blurs only behind groups.
                ZStack(alignment: .top) {
                    if values.background == .frosted {
                        ZStack(alignment: .topLeading) {
                            LinearGradient(colors: [Color(nsColor: hsl(210, 40, 55)), Color(nsColor: hsl(262, 35, 45))],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                            window.offset(x: -(w - pw))
                        }
                        .blur(radius: 3)
                        .clipped()
                    }
                    Rectangle().fill((dark ? Color(nsColor: hsl(60, 2.7, 14.5)) : Color(nsColor: hsl(48, 33.3, 97.1)))
                        .opacity(values.opacity / 100))
                    VStack(spacing: density == .compact ? 2 : 3) {
                        ForEach(0..<(density == .standard ? 3 : density == .cozy ? 4 : 5), id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(values.background == .glass ? (dark ? Color(white: 0.35) : Color(white: 0.92)).opacity(0.85)
                                      : (dark ? Color(white: 0.19) : .white).opacity(groupFillAlpha(opacity: values.opacity, background: values.background)))
                                .overlay(RoundedRectangle(cornerRadius: 2).stroke(values.background == .glass ? .white.opacity(0.8) : .clear, lineWidth: 0.5))
                                .frame(height: density == .standard ? 8 : density == .cozy ? 6.5 : 5)
                        }
                    }
                    .padding(4)
                }
                .frame(width: pw, height: h)
                .clipped()
                .offset(x: w - pw)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

// The Density tiles: a close-up of the solid panel, so the row layout is the only
// difference. Default: two rows with a summary line. Cozy: three tighter ones. Compact: five one-line rows.
struct DensityPicture: View {
    let density: Density
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let ink = dark ? Color.white : Color.black
        let cozy = density != .compact
        let tight = density == .cozy
        VStack(spacing: 0) {
            ForEach(0..<(density == .standard ? 2 : tight ? 3 : 5), id: \.self) { i in
                if i > 0 { Rectangle().fill(ink.opacity(0.12)).frame(height: 0.5) }
                HStack(spacing: 4) {
                    Circle().fill(Theme.brand.opacity(0.7)).frame(width: tight ? 7 : cozy ? 9 : 5, height: tight ? 7 : cozy ? 9 : 5)
                    VStack(alignment: .leading, spacing: 2.5) {
                        Capsule().fill(ink.opacity(0.75)).frame(width: 30, height: 2.5)
                        if cozy { Capsule().fill(ink.opacity(0.35)).frame(width: 44, height: 2) }
                    }
                    Spacer(minLength: 0)
                    Capsule().fill(ink.opacity(0.35)).frame(width: 8, height: 2)
                }
                .padding(.horizontal, 5)
                .frame(height: density == .standard ? 20 : tight ? 14 : 8.4)
            }
        }
        .background(RoundedRectangle(cornerRadius: 4).fill(dark ? Color(white: 0.19) : .white))
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(dark ? Color(nsColor: hsl(60, 2.7, 14.5)) : Color(nsColor: hsl(48, 33.3, 97.1)))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

// An 84×54 picture with its name under it. The selected one gets a brand ring.
struct PictureTile<Picture: View>: View {
    let label: String
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let picture: () -> Picture

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                picture()
                    .frame(width: 84, height: 54)
                    .padding(2)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Theme.brand : .clear, lineWidth: 2))
                Text(label).font(.system(size: 12, weight: selected ? .medium : .regular))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

// A 64×42 preview showing the slider's current value. On hover it runs from min to
// max and back, unless Reduce motion is on.
struct SliderPreview: View {
    let values: (Double) -> AppearanceValues
    let value: Double
    let range: ClosedRange<Double>
    @LocalState private var hovering = false

    var body: some View {
        Group {
            if hovering {
                // A 2.4s loop: min, max, min.
                TimelineView(.animation) { ctx in
                    let t = (1 - cos(ctx.date.timeIntervalSinceReferenceDate * .pi / 1.2)) / 2
                    MiniPanel(values: values(range.lowerBound + (range.upperBound - range.lowerBound) * t))
                }
            } else {
                MiniPanel(values: values(value))
            }
        }
        .frame(width: 64, height: 42)
        .onHover { hovering = $0 && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    }
}
