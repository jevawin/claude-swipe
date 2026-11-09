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
    @Published var cardIcon: String { didSet { d.set(cardIcon, forKey: "cardIcon") } }
    @Published var showEmoji: Bool { didSet { d.set(showEmoji, forKey: "showEmoji"); scriptChanged() } }
    @Published var emojiSource: String { didSet { d.set(emojiSource, forKey: "emojiSource"); scriptChanged() } }
    @Published var homeFolder: String { didSet { d.set(homeFolder, forKey: "homeFolder") } }
    @Published var minimiseOthers: Bool { didSet { d.set(minimiseOthers, forKey: "minimiseOthers") } }
    // Percent to fade Done cards by. Capped at 80 so they stay readable.
    @Published var doneFade: Double { didSet { d.set(doneFade, forKey: "doneFade") } }
    // Whether the Done section is open; remembers the last click.
    @Published var showDone: Bool { didSet { d.set(showDone, forKey: "showDone") } }
    // Model changes only affect new picks, so no refresh.
    @Published var aiModel: String { didSet { d.set(aiModel, forKey: "aiModel") } }
    @Published var aiSort: Bool { didSet { d.set(aiSort, forKey: "aiSort"); scriptChanged() } }
    @Published var aiEmoji: Bool { didSet { d.set(aiEmoji, forKey: "aiEmoji"); scriptChanged() } }
    @Published var aiClear: Bool { didSet { d.set(aiClear, forKey: "aiClear"); scriptChanged() } }
    @Published var loginOn = false  // mirrors SMAppService; set by AppDelegate.updateLoginItem

    var onboarded: Bool {
        get { d.bool(forKey: "onboarded") }
        set { d.set(newValue, forKey: "onboarded") }
    }

    init() {
        d.register(defaults: [
            "theme": "auto", "cardIcon": "status", "showEmoji": true, "emojiSource": "subject",
            "homeFolder": "", "minimiseOthers": false, "doneFade": 40.0, "showDone": true, "aiModel": "haiku",
            "aiSort": false, "aiEmoji": false, "aiClear": false,
        ])
        theme = d.string(forKey: "theme") ?? "auto"
        cardIcon = d.string(forKey: "cardIcon") ?? "status"
        showEmoji = d.bool(forKey: "showEmoji")
        emojiSource = d.string(forKey: "emojiSource") ?? "subject"
        homeFolder = d.string(forKey: "homeFolder") ?? ""
        minimiseOthers = d.bool(forKey: "minimiseOthers")
        doneFade = min(80, max(0, d.double(forKey: "doneFade")))
        showDone = d.bool(forKey: "showDone")
        aiModel = d.string(forKey: "aiModel") ?? "haiku"
        aiSort = d.bool(forKey: "aiSort")
        aiEmoji = d.bool(forKey: "aiEmoji")
        aiClear = d.bool(forKey: "aiClear")
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

    var pickEmoji: Bool { showEmoji && aiEmoji }
    var anyAI: Bool { aiSort || aiClear || pickEmoji }
    var modelName: String { aiModel == "sonnet" ? "Sonnet" : "Haiku" }

    // Flags for recent_chats.py. Every AI flag is opt-in, so none set means no requests.
    var scriptArgs: [String] {
        var a = ["--model", aiModel, "--emoji-from", emojiSource]
        if aiSort { a.append("--sort") }
        if aiClear { a.append("--clear") }
        if pickEmoji { a += ["--emoji", emojiSource] }
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
        ("General", ""), ("Cards", "rectangle.stack"), ("Windows", "macwindow.on.rectangle"), ("AI", "sparkles"),
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
            Row(title: "Theme") {
                Picker("Theme", selection: $prefs.theme) {
                    Text("Auto").tag("auto"); Text("Light").tag("light"); Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            Hairline()
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

    var folders: [String] {
        var f = Array(Set(store.chats.map(\.folder))).sorted()
        if !prefs.homeFolder.isEmpty && !f.contains(prefs.homeFolder) { f.insert(prefs.homeFolder, at: 0) }
        return f
    }

    var cards: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Preview").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.secondary)
                Card(chat: sampleChat)
                    .frame(maxWidth: 440)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.bg))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
            }
            Group_ {
                Row(title: "Card icon") {
                    Picker("Card icon", selection: $prefs.cardIcon) {
                        Text("Status first (emoji as a small badge)").tag("status")
                        Text("Emoji first (status as a small badge)").tag("emoji")
                    }
                    .pickerStyle(.radioGroup).labelsHidden().fixedSize()
                }
                .disabled(!prefs.showEmoji)
                .opacity(prefs.showEmoji ? 1 : 0.5)
                Hairline()
                Row(title: "Show emoji", helper: "Off: cards show the status icon on its own") {
                    Toggle("Show emoji", isOn: $prefs.showEmoji).toggleStyle(.switch).labelsHidden()
                }
                Hairline()
                Row(title: "Emoji from",
                    helper: "Claude picks these, so AI must be on. Right-click a chat to pick your own.") {
                    Picker("Emoji from", selection: $prefs.emojiSource) {
                        Text("Chat subject").tag("subject"); Text("Folder").tag("folder")
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                .disabled(!prefs.showEmoji)
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
             emoji: "✍️", own_emoji: nil)
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
                Row(title: "Let AI pick emoji", helper: "Off: only your own emoji picks show") {
                    Toggle("Let AI pick emoji", isOn: $prefs.aiEmoji).toggleStyle(.switch).labelsHidden()
                }
                Hairline()
                Row(title: "Ready to clear section",
                    helper: "Checks each done chat once more to see if the whole job is finished. Chats that pass get their own section.") {
                    Toggle("Ready to clear section", isOn: $prefs.aiClear).toggleStyle(.switch).labelsHidden()
                }
            }
            .disabled(!ready)
            Group_ {
                Row(title: "Re-pick all emoji",
                    helper: "Changing the model or emoji source only affects new chats. Re-pick asks Claude again for every chat from the last 7 days, using your plan. Your own picks stay.") {
                    Button("Re-pick…") { actions.repick() }
                }
            }
            .disabled(!ready || !prefs.pickEmoji)
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
                        get: { prefs.aiSort && prefs.aiEmoji },
                        set: { prefs.aiSort = $0; prefs.aiEmoji = $0 }))
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
            Text("Sort unclear chats and pick emoji").font(.system(size: 15, weight: .semibold))
            Text("Sometimes ClaudeSwipe cannot tell if a chat needs you or is done. With this on, Claude reads your latest message and its last reply, and decides. It can also pick an emoji for each chat.")
                .font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 14) {
                SortDemo(sorted: false, label: "Picture: a chat card marked unsure, with no emoji",
                         caption: "Before: chat marked unsure, no emoji")
                SortDemo(sorted: true, label: "Picture: the same card marked done, with an emoji",
                         caption: "After: chat sorted, with an emoji")
            }
            WarningBox(text: warning)
            PrivacyNote(text: "ClaudeSwipe never signs in to your Claude account. It uses the claude command you already set up, and only checks that you are signed in.")
            ClaudeStatusLine(state: status.claude)
        }
        .padding(14)
    }
}

// Before/after picture of one card: unsure and plain, then sorted with an emoji badge.
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
                    RoundedRectangle(cornerRadius: 7).fill(st.color)
                        .overlay(Image(systemName: st.icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white))
                        .overlay(alignment: .bottomTrailing) {
                            if sorted {
                                Circle().fill(Theme.cardHover).frame(width: 16, height: 16)
                                    .overlay(Text("🧾").font(.system(size: 9)))
                                    .overlay(Circle().stroke(Theme.card, lineWidth: 1.5))
                                    .offset(x: 5, y: 5)
                            }
                        }
                        .frame(width: 26, height: 26)
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
