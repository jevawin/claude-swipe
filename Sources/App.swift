// ClaudeSwipe: a slide-out panel of recent Claude Code chats.
// Opens when the cursor pushes against the right screen edge, or on ⌃⌥C.
// Data comes from recent_chats.py (bundled in Resources), run with --json.

import AppKit
import Carbon
import ServiceManagement
import SwiftUI

struct Chat: Codable, Identifiable, Hashable {
    let id: String
    let status: String
    let why: String
    let title: String
    let folder: String
    let age: Double
    let engaged: Double
    var section: String
    let app: String
    let desktop_id: String?
    let cwd: String?
    var emoji: String?
    var own_emoji: Bool?  // your own pick decides the emoji (counted for Re-pick)
    var pinned: Bool?
}

// Appends to ~/Library/Logs/ClaudeSwipe.log (NSLog lines didn't show in `log show`).
func debugLog(_ msg: String) {
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/ClaudeSwipe.log")
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(msg)\n"
    if let h = try? FileHandle(forWritingTo: url) {
        h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
    } else {
        try? line.write(to: url, atomically: true, encoding: .utf8)
    }
}

final class Store: ObservableObject {
    @Published var chats: [Chat] = []
    @Published var updating = false
    @Published var error: String?
    @Published var notice: String?
    @Published var query = ""
    @Published var focusTick = 0  // bumped on each show to focus the search field
    var lastRun = Date.distantPast
    var again = false
    let script: String

    init(script: String) { self.script = script }

    func refresh(repick: Bool = false) {
        if updating { again = true; return }
        updating = true
        let base = ["--json"] + Prefs.shared.scriptArgs
        let ai = Prefs.shared.anyAI || repick
        DispatchQueue.global(qos: .userInitiated).async {
            // Rules + cached verdicts first (fast), then, only if an AI setting is on,
            // the pass that asks about new chats.
            let fast = Store.run(self.script, base + ["--no-ai"])
            DispatchQueue.main.async { self.apply(fast) }
            let full = ai ? Store.run(self.script, base + (repick ? ["--repick"] : [])) : fast
            DispatchQueue.main.async {
                self.apply(full)
                self.updating = false
                self.lastRun = Date()
                if self.again { self.again = false; self.refresh() }
            }
        }
    }

    private func apply(_ r: Result<[Chat], Error>) {
        switch r {
        case .success(let c): chats = c; error = nil
        case .failure(let e): error = "\(e)"
        }
    }

    static func run(_ script: String, _ args: [String]) -> Result<[Chat], Error> {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["python3", script] + args
        let home = NSHomeDirectory()
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        p.environment = env
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do {
            try p.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            if p.terminationStatus != 0 {
                let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                return .failure(NSError(domain: "script", code: Int(p.terminationStatus),
                                        userInfo: [NSLocalizedDescriptionKey: msg]))
            }
            return .success(try JSONDecoder().decode([Chat].self, from: data))
        } catch {
            return .failure(error)
        }
    }
}

// MARK: - Theme

// HSL values copied from the Claude desktop app's CSS tokens (--bg-100, --text-100 etc.).
func hsl(_ h: CGFloat, _ s: CGFloat, _ l: CGFloat) -> NSColor {
    let s = s / 100, l = l / 100
    let v = l + s * min(l, 1 - l)
    return NSColor(hue: h / 360, saturation: v == 0 ? 0 : 2 * (1 - l / v), brightness: v, alpha: 1)
}

func themed(_ light: NSColor, _ dark: NSColor) -> Color {
    Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light })
}

enum Theme {
    static let bg = themed(hsl(48, 33.3, 97.1), hsl(60, 2.7, 14.5))         // --bg-100
    static let text = themed(hsl(60, 2.6, 7.6), hsl(48, 33.3, 97.1))        // --text-100
    static let secondary = themed(hsl(51, 3.1, 43.7), hsl(48, 4.8, 59.2))   // --text-400
    static let border = themed(hsl(51, 16.5, 84.5), hsl(50, 9, 73.7).withAlphaComponent(0.15))
    static let brand = Color(nsColor: hsl(15, 63.1, 59.6))                  // --accent-brand
    static let card = themed(.white, hsl(60, 2.1, 18.4))                    // --bg-000
    static let cardHover = themed(hsl(53, 28.6, 94.5), hsl(60, 2.1, 21))
    static let sidebar = themed(hsl(50, 25, 92), hsl(60, 2.5, 12.5))
}

// MARK: - Views

// Status sets the card's tile (or its badge): colour, SF Symbol and a spoken name.
let statusStyle: [String: (color: Color, icon: String)] = [
    "running": (Color(nsColor: hsl(210, 60, 52)), "ellipsis"),
    "waiting": (Color(nsColor: hsl(38, 92, 50)), "questionmark"),        // a question for you
    "blocked": (Color(nsColor: hsl(0, 72, 52)), "xmark"),               // needs a click to carry on
    "done": (Color(nsColor: hsl(120, 35, 42)), "checkmark"),
    "finished": (Color(nsColor: hsl(262, 45, 58)), "archivebox.fill"),   // ready to archive or delete
    "stuck": (Color(nsColor: hsl(48, 4.8, 50)), "exclamationmark"),
    "unsure": (Color(nsColor: hsl(48, 4.8, 50)), "circle.dotted"),
]

// Sections come from recent_chats.py: pinned chats, then touched in the last
// hour, then not-done chats split by today vs older, then everything done.
let sections: [(key: String, label: String)] = [
    ("pinned", "Pinned"),
    ("active", "Active"),
    ("today", "Waiting · today"),
    ("older", "Waiting · older"),
    ("clear", "Ready to clear"),
    ("done", "Done"),
]

let statusName: [String: String] = [
    "running": "Running", "waiting": "Waiting for you", "blocked": "Blocked", "done": "Done",
    "finished": "Ready to clear", "stuck": "Stuck", "unsure": "Unsure",
]

func ageText(_ s: Double) -> String {
    let s = max(0, s)
    if s < 3600 { return "\(Int(s / 60))m" }
    if s < 86400 { return "\(Int(s / 3600))h" }
    return "\(Int(s / 86400))d"
}

struct PanelView: View {
    @ObservedObject var store: Store
    let open: (Chat) -> Void
    let editEmoji: (Chat) -> Void
    let togglePin: (Chat) -> Void
    let openSettings: () -> Void
    @ObservedObject private var prefs = Prefs.shared
    @FocusState private var searchFocused: Bool

    // Every word must appear somewhere in title, folder or preview.
    var filtered: [Chat] {
        let words = store.query.lowercased().split(separator: " ")
        if words.isEmpty { return store.chats }
        return store.chats.filter { c in
            let hay = "\(c.title) \(c.folder) \(c.why) \(c.emoji ?? "")".lowercased()
            return words.allSatisfy { hay.contains($0) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Claude chats").font(.system(size: 16, weight: .semibold))
                Spacer()
                if store.updating { ProgressView().controlSize(.small) }
                Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Refresh")
                    .accessibilityLabel("Refresh")
                Button { openSettings() } label: { Settings2Image() }
                    .buttonStyle(.borderless)
                    .help("Settings")
                    .accessibilityLabel("Settings")
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondary)
                TextField("Search chats or folders", text: $store.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($searchFocused)
                    .onSubmit { if let first = sections.flatMap({ s in filtered.filter { $0.section == s.key } }).first { open(first) } }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
            .padding(.horizontal, 12).padding(.bottom, 10)
            .onChange(of: store.focusTick) { searchFocused = true }
            .onAppear { searchFocused = true }
            Rectangle().fill(Theme.border).frame(height: 1)
            if let n = store.notice {
                Text(n).font(.system(size: 13)).padding(.horizontal, 16).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.15))
            }
            if let e = store.error {
                Text(e).font(.system(size: 13)).foregroundStyle(.red).padding(16)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(sections, id: \.key) { sec in
                        let items = filtered.filter { $0.section == sec.key }
                        if !items.isEmpty {
                            let collapsible = sec.key == "done"
                            HStack(spacing: 4) {
                                Text("\(sec.label) · \(items.count)")
                                if collapsible {
                                    Image(systemName: prefs.showDone ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 10, weight: .semibold))
                                }
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.secondary)
                            .padding(.horizontal, 2).padding(.top, 8)
                            .contentShape(Rectangle())
                            .onTapGesture { if collapsible { prefs.showDone.toggle() } }
                            if !collapsible || prefs.showDone || !store.query.isEmpty {
                                ForEach(items) { c in
                                    Card(chat: c)
                                        .opacity(sec.key == "done" ? 1 - prefs.doneFade / 100 : 1)
                                        .onTapGesture { open(c) }
                                        .contextMenu {
                                            Button(c.pinned == true ? "Unpin" : "Pin") { togglePin(c) }
                                            Button("Change emoji…") { editEmoji(c) }
                                        }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 12)
            }
        }
        .foregroundStyle(Theme.text)
        .background(Theme.bg)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1))
    }
}

// Notification-style card: icon tile, title with time top right, folder chip, preview.
struct Card: View {
    let chat: Chat
    @ObservedObject var prefs = Prefs.shared
    @LocalState private var hover = false

    var emoji: String? { prefs.showEmoji ? chat.emoji.flatMap { $0.isEmpty ? nil : $0 } : nil }

    // Settings › Cards › Card icon. "status": status tile with the emoji as a badge
    // (no emoji, no badge). "emoji": emoji tile (💬 if none) with the status as a badge.
    @ViewBuilder var tile: some View {
        let st = statusStyle[chat.status] ?? statusStyle["unsure"]!
        if prefs.showEmoji && prefs.cardIcon == "emoji" {
            RoundedRectangle(cornerRadius: 9).fill(Theme.cardHover)
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.border, lineWidth: 1))
                .overlay(Text(emoji ?? "💬").font(.system(size: 19)))
                .overlay(alignment: .bottomTrailing) {
                    Circle().fill(st.color)
                        .frame(width: 18, height: 18)
                        .overlay(Image(systemName: st.icon).font(.system(size: 9, weight: .bold)).foregroundStyle(.white))
                        .overlay(Circle().stroke(Theme.card, lineWidth: 2))
                        .offset(x: 6, y: 6)
                }
        } else {
            RoundedRectangle(cornerRadius: 9).fill(st.color)
                .overlay(Image(systemName: st.icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white))
                .overlay(alignment: .bottomTrailing) {
                    if let e = emoji {
                        Circle().fill(Theme.cardHover)
                            .frame(width: 20, height: 20)
                            .overlay(Text(e).font(.system(size: 11)))
                            .overlay(Circle().stroke(Theme.card, lineWidth: 2))
                            .offset(x: 6, y: 6)
                    }
                }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            tile
                .frame(width: 34, height: 34)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(statusName[chat.status] ?? "Unsure")
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(chat.title).font(.system(size: 15, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(ageText(chat.engaged)).font(.system(size: 13)).foregroundStyle(Theme.secondary)
                }
                HStack(spacing: 6) {
                    if chat.folder != prefs.homeFolder {
                        Text(chat.folder)
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(1).truncationMode(.middle)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Theme.text.opacity(0.08)))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
                    }
                }
                .padding(.top, 4)
                if !chat.why.isEmpty {
                    Text(chat.why).font(.system(size: 13)).foregroundStyle(Theme.text.opacity(0.85))
                        .lineLimit(2).padding(.top, 7)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(hover ? Theme.cardHover : Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onHover { hover = $0 }
    }
}

// MARK: - Panel + triggers

final class Panel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var panel: Panel!
    var store: Store!
    let status = SystemStatus()
    var settingsWindow: NSWindow?
    var welcomeWindow: NSWindow?
    var statusItem: NSStatusItem!
    var loginItem: NSMenuItem!
    var edgeSince: Date?
    var shown = false
    var mouseWasInside = false
    var panelTarget = NSRect.zero  // where the panel ends up; its live frame is off-screen while it slides in
    let width: CGFloat = 440
    let dwell: TimeInterval = 0.25  // how long the cursor must push the edge

    func applicationDidFinishLaunching(_ n: Notification) {
        debugLog("launched; accessibility allowed: \(AXIsProcessTrusted())")
        let script = Bundle.main.path(forResource: "recent_chats", ofType: "py")!
        store = Store(script: script)
        Prefs.shared.applyTheme()
        Prefs.shared.onScriptChange = { [weak self] in self?.store.refresh() }

        panel = Panel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless],
                      backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        // Solid background comes from PanelView (Theme.bg), so the window itself stays clear.
        panel.contentView = NSHostingView(rootView: PanelView(
            store: store, open: { [weak self] in self?.open($0) },
            editEmoji: { [weak self] in self?.editEmoji($0) },
            togglePin: { [weak self] in self?.togglePin($0) },
            openSettings: { [weak self] in self?.openSettings() }))

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "bubble.left.and.text.bubble.right",
                                           accessibilityDescription: "Claude chats")
        let menu = NSMenu()
        // Explicit targets: with a nil target the items rely on the responder chain,
        // which an accessory app with no key window may not route to the delegate.
        menu.addItem(withTitle: "Show chats (⌃⌥C)", action: #selector(menuShow), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Refresh", action: #selector(refresh), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        loginItem = menu.addItem(withTitle: "Launch at login", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.tick() }
        Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in self?.store.refresh() }
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide(reason: "click elsewhere")
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            // ⌘, opens Settings from the panel (the menu's shortcut only works while the menu is open).
            if e.modifierFlags.contains(.command) && e.charactersIgnoringModifiers == "," {
                self?.openSettings()
                return nil
            }
            if e.keyCode == UInt16(kVK_Escape) && e.window === self?.panel {
                if let s = self?.store, !s.query.isEmpty { s.query = "" } else { self?.hide() }
                return nil
            }
            return e
        }
        registerHotKey()
        // Turn launch-at-login on once; after that the menu toggle owns it.
        if !UserDefaults.standard.bool(forKey: "loginItemOffered") {
            UserDefaults.standard.set(true, forKey: "loginItemOffered")
            try? SMAppService.mainApp.register()
        }
        updateLoginItem()
        store.refresh()
        // Shown once, including for installs from before this screen existed.
        if !Prefs.shared.onboarded || CommandLine.arguments.contains("--welcome") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.showWelcome() }
        }
        if CommandLine.arguments.contains("--settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.openSettings() }
        }
        if CommandLine.arguments.contains("--show") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.toggle() }
        }
    }

    @objc func refresh() { store.refresh() }

    // Runs after the menu has closed, so menu tracking can't swallow the panel's first frames.
    @objc func menuShow() {
        debugLog("menu: show chats")
        DispatchQueue.main.async { if !self.shown { self.toggle() } }
    }

    @objc func toggleLogin() { setLogin(SMAppService.mainApp.status != .enabled) }

    func setLogin(_ on: Bool) {
        let s = SMAppService.mainApp
        do {
            if on { try s.register() } else { try s.unregister() }
        } catch {
            debugLog("login item: \(error)")
        }
        updateLoginItem()
    }

    func updateLoginItem() {
        let st = SMAppService.mainApp.status
        Prefs.shared.loginOn = st == .enabled
        loginItem.state = st == .enabled ? .on : .off
        loginItem.title = st == .requiresApproval ? "Launch at login (approve in System Settings)" : "Launch at login"
    }

    // Polls the cursor; no Accessibility permission needed.
    func tick() {
        let p = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(p, $0.frame, false) }) else { return }
        if shown {
            let zone = panelTarget.insetBy(dx: -40, dy: -40)
            if zone.contains(p) { mouseWasInside = true } else if mouseWasInside { hide(reason: "cursor left") }
            return
        }
        let f = screen.frame
        let atEdge = p.x >= f.maxX - 1 && p.y < f.maxY - 30  // skip the menu bar corner
        let screenToRight = NSScreen.screens.contains { NSMouseInRect(NSPoint(x: f.maxX + 1, y: p.y), $0.frame, false) }
        if atEdge && !screenToRight {
            if let s = edgeSince {
                if Date().timeIntervalSince(s) >= dwell { edgeSince = nil; show(on: screen) }
            } else {
                edgeSince = Date()
            }
        } else {
            edgeSince = nil
        }
    }

    @objc func toggle() {
        if shown { hide(); return }
        let p = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(p, $0.frame, false) }) ?? NSScreen.main!
        show(on: screen)
    }

    func show(on screen: NSScreen) {
        let vf = screen.visibleFrame
        let target = NSRect(x: vf.maxX - width - 8, y: vf.minY + 8, width: width, height: vf.height - 16)
        panelTarget = target
        debugLog("show")
        panel.setFrame(target.offsetBy(dx: width + 20, dy: 0), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }
        shown = true
        mouseWasInside = target.insetBy(dx: -40, dy: -40).contains(NSEvent.mouseLocation)
        store.notice = nil
        store.query = ""
        store.focusTick += 1
        if Date().timeIntervalSince(store.lastRun) > 20 { store.refresh() }
    }

    func hide(reason: String = "") {
        guard shown else { return }
        debugLog("hide \(reason)")
        shown = false
        let f = panel.frame
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.14
            panel.animator().setFrame(f.offsetBy(dx: width + 20, dy: 0), display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            if self?.shown == false { self?.panel.orderOut(nil) }
        })
    }

    func open(_ c: Chat) {
        // Settings › Windows › Minimise other Claude windows; Option flips it for one click.
        let keepOthers = Prefs.shared.minimiseOthers == NSEvent.modifierFlags.contains(.option)
        guard let d = c.desktop_id, let url = URL(string: "claude://code/continue?session=\(d)") else { return }
        hide()
        // The deep link always loads the chat in the main window, so first try to
        // raise a window already showing it (a pop-out, or the main window itself).
        if let w = raiseClaudeWindow(titled: c.title) {
            if !keepOthers { minimiseClaudeWindows(except: w) }
        } else {
            NSWorkspace.shared.open(url)
            if !keepOthers {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    guard let self, let ax = self.claudeAX(),
                          let main = self.attribute(ax.element, kAXMainWindowAttribute) else { return }
                    self.minimiseClaudeWindows(except: main as! AXUIElement)
                }
            }
        }
    }

    // The Claude desktop app as an Accessibility element. Needs Accessibility
    // permission; asks once, then returns nil until it's granted.
    func claudeAX() -> (app: NSRunningApplication, element: AXUIElement)? {
        let opts = ["AXTrustedCheckOptionPrompt": !UserDefaults.standard.bool(forKey: "axPrompted")] as CFDictionary
        guard AXIsProcessTrustedWithOptions(opts) else {
            debugLog("accessibility: not allowed")
            UserDefaults.standard.set(true, forKey: "axPrompted")
            return nil
        }
        guard let app = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.anthropic.claudefordesktop").first else { return nil }
        return (app, AXUIElementCreateApplication(app.processIdentifier))
    }

    func attribute(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
        var ref: CFTypeRef?
        return AXUIElementCopyAttributeValue(e, name as CFString, &ref) == .success ? ref : nil
    }

    func claudeWindows(_ ax: AXUIElement) -> [AXUIElement] {
        (attribute(ax, kAXWindowsAttribute) as? [AXUIElement] ?? []).filter {
            attribute($0, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole
        }
    }

    // Finds a Claude window whose title is the chat's title (pop-outs are titled
    // with the chat title; the main window is "Claude") and brings it to the front.
    func raiseClaudeWindow(titled title: String) -> AXUIElement? {
        guard let ax = claudeAX() else { return nil }
        let windows = claudeWindows(ax.element)
        let titles = windows.map { (attribute($0, kAXTitleAttribute) as? String) ?? "" }
        let want = title.lowercased()
        let match = titles.firstIndex(where: { $0.lowercased() == want })
            ?? titles.firstIndex(where: { !want.isEmpty && $0.lowercased().contains(want) })
        debugLog("looking for \(title.debugDescription) in \(titles.map { $0.debugDescription }) -> \(match.map(String.init) ?? "no match")")
        guard let i = match else { return nil }
        AXUIElementSetAttributeValue(windows[i], kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        AXUIElementPerformAction(windows[i], kAXRaiseAction as CFString)
        ax.app.activate()
        return windows[i]
    }

    // Sends every other Claude window to the Dock.
    func minimiseClaudeWindows(except keep: AXUIElement) {
        guard let ax = claudeAX() else { return }
        for w in claudeWindows(ax.element) where !CFEqual(w, keep) {
            if attribute(w, kAXMinimizedAttribute) as? Bool == true { continue }
            AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        }
    }

    // Right-click > Change emoji. Saves to chat-emoji.json "overrides", which beat Haiku's picks.
    func editEmoji(_ c: Chat) {
        hide()
        let file = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/claude-swipe/chat-emoji.json")
        var data = (try? JSONSerialization.jsonObject(with: Data(contentsOf: file))) as? [String: Any] ?? [:]
        var overrides = data["overrides"] as? [String: String] ?? [:]
        let auto = data["auto"] as? [String: String] ?? [:]

        let alert = NSAlert()
        alert.messageText = "Emoji for “\(c.title)”"
        alert.informativeText = "Type or pick one emoji. The emoji picker opens with it; Control-Command-Space reopens it."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        if overrides[c.id] != nil { alert.addButton(withTitle: "Remove my pick") }
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 28))
        field.font = .systemFont(ofSize: 18)
        field.stringValue = c.emoji ?? ""
        alert.accessoryView = field
        alert.layout()
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            alert.window.makeFirstResponder(field)
            NSApp.orderFrontCharacterPalette(nil)
        }
        let choice = alert.runModal()

        var newEmoji: String?
        switch choice {
        case .alertFirstButtonReturn:
            guard let first = field.stringValue.trimmingCharacters(in: .whitespaces).first else { return }
            newEmoji = String(first)
            overrides[c.id] = newEmoji
        case .alertThirdButtonReturn:
            overrides[c.id] = nil
            newEmoji = nil  // the refresh below fills in the AI or folder emoji
        default:
            return
        }
        data["overrides"] = overrides
        data["auto"] = auto
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let out = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted]) {
            try? out.write(to: file)
        }
        if let i = store.chats.firstIndex(where: { $0.id == c.id }) { store.chats[i].emoji = newEmoji }
        store.refresh()
    }

    // Right-click > Pin / Unpin. Saves session ids to pinned.json "pinned"; the
    // script puts those chats in the Pinned section and never in Done.
    func togglePin(_ c: Chat) {
        let file = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/claude-swipe/pinned.json")
        var data = (try? JSONSerialization.jsonObject(with: Data(contentsOf: file))) as? [String: Any] ?? [:]
        var pins = data["pinned"] as? [String] ?? []
        let pin = !pins.contains(c.id)
        if pin { pins.append(c.id) } else { pins.removeAll { $0 == c.id } }
        data["pinned"] = pins
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let out = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted]) {
            try? out.write(to: file)
        }
        // Move it now; the refresh puts an unpinned chat back in its own section.
        if let i = store.chats.firstIndex(where: { $0.id == c.id }) {
            store.chats[i].pinned = pin
            if pin { store.chats[i].section = "pinned" }
        }
        store.refresh()
    }

    // MARK: Settings and first run

    func makeWindow<V: View>(_ view: V, title: String, size: NSSize, resizable: Bool) -> NSWindow {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if resizable { style.insert(.resizable) }
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style,
                         backing: .buffered, defer: false)
        w.title = title
        w.isReleasedWhenClosed = false  // we keep it and reopen it
        w.contentMinSize = size
        w.contentView = NSHostingView(rootView: view)
        w.delegate = self
        w.center()
        return w
    }

    func bringUp(_ w: NSWindow) {
        hide()
        status.start()
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            settingsWindow = makeWindow(
                SettingsView(status: status, store: store, actions: SettingsActions(
                    showWelcome: { [weak self] in self?.showWelcome() },
                    repick: { [weak self] in self?.confirmRepick() },
                    setLogin: { [weak self] in self?.setLogin($0) })),
                title: "ClaudeSwipe Settings", size: NSSize(width: 760, height: 580), resizable: true)
        }
        updateLoginItem()
        bringUp(settingsWindow!)
    }

    func showWelcome() {
        // A fresh view each time, so it starts at step 1.
        welcomeWindow?.delegate = nil
        welcomeWindow?.close()
        welcomeWindow = makeWindow(
            WelcomeView(status: status, finish: { [weak self] in
                self?.welcomeWindow?.close()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self?.menuShow() }
            }),
            title: "Welcome to ClaudeSwipe", size: NSSize(width: 560, height: 680), resizable: false)
        bringUp(welcomeWindow!)
    }

    func windowWillClose(_ n: Notification) {
        // Closing the first-run screen at any step counts as done.
        if n.object as? NSWindow === welcomeWindow { Prefs.shared.onboarded = true }
        let others = [settingsWindow, welcomeWindow].compactMap { $0 }.filter { $0 !== n.object as? NSWindow && $0.isVisible }
        if others.isEmpty { status.stop() }
    }

    // Count comes from the last refresh: chats without your own pick, or their distinct folders.
    func confirmRepick() {
        let p = Prefs.shared
        let folder = p.emojiSource == "folder"
        let rows = store.chats.filter { $0.own_emoji != true }
        let n = folder ? Set(rows.map(\.folder)).count : rows.count
        let noun = folder ? (n == 1 ? "folder" : "folders") : (n == 1 ? "chat" : "chats")
        let alert = NSAlert()
        alert.messageText = "Re-pick all emoji?"
        alert.informativeText = folder
            ? "ClaudeSwipe will ask \(p.modelName) to pick an emoji again for \(n) \(noun) with chats from the last 7 days. This uses your Claude plan. Emoji you picked yourself will not change."
            : "ClaudeSwipe will ask \(p.modelName) to pick an emoji again for \(n) \(noun) from the last 7 days. This uses your Claude plan. Emoji you picked yourself will not change."
        alert.addButton(withTitle: "Re-pick")
        alert.addButton(withTitle: "Cancel")
        let go: (NSApplication.ModalResponse) -> Void = { [weak self] r in
            if r == .alertFirstButtonReturn { self?.store.refresh(repick: true) }
        }
        if let w = settingsWindow, w.isVisible { alert.beginSheetModal(for: w, completionHandler: go) } else { go(alert.runModal()) }
    }

    func registerHotKey() {
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x4353_5750), id: 1)  // 'CSWP'
        RegisterEventHotKey(UInt32(kVK_ANSI_C), UInt32(controlKey | optionKey), id,
                            GetApplicationEventTarget(), 0, &ref)
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { Main.delegate.toggle() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

@main
enum Main {
    static let delegate = AppDelegate()
    static func main() {
        if CommandLine.arguments.contains("--login-status") {
            // 0 notRegistered, 1 enabled, 2 requiresApproval, 3 notFound
            print(SMAppService.mainApp.status.rawValue)
            return
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}

// Non-macro stand-in for @State (Command Line Tools ship without the SwiftUIMacros plugin).
@propertyWrapper struct LocalState<Value>: DynamicProperty {
    private let s: State<Value>
    init(wrappedValue: Value) { s = State(initialValue: wrappedValue) }
    var wrappedValue: Value {
        get { s.wrappedValue }
        nonmutating set { s.wrappedValue = newValue }
    }
    var projectedValue: Binding<Value> { s.projectedValue }
}
