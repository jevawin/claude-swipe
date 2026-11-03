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
    let section: String
    let app: String
    let desktop_id: String?
    let cwd: String?
}

final class Store: ObservableObject {
    @Published var chats: [Chat] = []
    @Published var updating = false
    @Published var error: String?
    @Published var notice: String?
    @Published var query = ""
    @Published var focusTick = 0  // bumped on each show to focus the search field
    var lastRun = Date.distantPast
    let script: String

    init(script: String) { self.script = script }

    func refresh() {
        if updating { return }
        updating = true
        DispatchQueue.global(qos: .userInitiated).async {
            // Rules + cached verdicts first (fast), then the Haiku pass for new chats.
            let fast = Store.run(self.script, ["--json", "--no-ai"])
            DispatchQueue.main.async { self.apply(fast) }
            let full = Store.run(self.script, ["--json"])
            DispatchQueue.main.async {
                self.apply(full)
                self.updating = false
                self.lastRun = Date()
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
}

// MARK: - Views

// Status sets the card's icon tile: colour and SF Symbol.
let statusStyle: [String: (color: Color, icon: String)] = [
    "waiting": (Theme.brand, "questionmark.bubble"),
    "stuck": (Color(nsColor: hsl(0, 55, 55)), "exclamationmark.triangle"),
    "unsure": (Color(nsColor: hsl(48, 4.8, 50)), "questionmark"),
    "running": (Color(nsColor: hsl(210, 50, 52)), "ellipsis"),
    "done": (Color(nsColor: hsl(120, 21, 45)), "checkmark"),
]

// Sections come from recent_chats.py: touched in the last hour, then not-done
// chats split by today vs older, then everything done.
let sections: [(key: String, label: String)] = [
    ("active", "Active"),
    ("today", "Waiting · today"),
    ("older", "Waiting · older"),
    ("done", "Done"),
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
    @State private var showDone = false
    @FocusState private var searchFocused: Bool

    // Every word must appear somewhere in title, folder or preview.
    var filtered: [Chat] {
        let words = store.query.lowercased().split(separator: " ")
        if words.isEmpty { return store.chats }
        return store.chats.filter { c in
            let hay = "\(c.title) \(c.folder) \(c.why)".lowercased()
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
                                    Image(systemName: showDone ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 10, weight: .semibold))
                                }
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.secondary)
                            .padding(.horizontal, 2).padding(.top, 8)
                            .contentShape(Rectangle())
                            .onTapGesture { if collapsible { showDone.toggle() } }
                            if !collapsible || showDone || !store.query.isEmpty {
                                ForEach(items) { c in
                                    let st = statusStyle[c.status] ?? statusStyle["unsure"]!
                                    Card(chat: c, color: st.color, icon: st.icon).onTapGesture { open(c) }
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
    let color: Color
    let icon: String
    @State private var hover = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 9).fill(color)
                .frame(width: 34, height: 34)
                .overlay(Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(chat.title).font(.system(size: 15, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(ageText(chat.engaged)).font(.system(size: 13)).foregroundStyle(Theme.secondary)
                }
                HStack(spacing: 6) {
                    Text(chat.folder)
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(1).truncationMode(.middle)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.text.opacity(0.08)))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
                    if chat.app == "cli" {
                        Text("terminal").font(.system(size: 12)).foregroundStyle(Theme.secondary)
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: Panel!
    var store: Store!
    var statusItem: NSStatusItem!
    var loginItem: NSMenuItem!
    var edgeSince: Date?
    var shown = false
    var mouseWasInside = false
    let width: CGFloat = 440
    let dwell: TimeInterval = 0.25  // how long the cursor must push the edge

    func applicationDidFinishLaunching(_ n: Notification) {
        let script = Bundle.main.path(forResource: "recent_chats", ofType: "py")!
        store = Store(script: script)

        panel = Panel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless],
                      backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        // Solid background comes from PanelView (Theme.bg), so the window itself stays clear.
        panel.contentView = NSHostingView(rootView: PanelView(store: store, open: { [weak self] in self?.open($0) }))

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "bubble.left.and.text.bubble.right",
                                           accessibilityDescription: "Claude chats")
        let menu = NSMenu()
        menu.addItem(withTitle: "Show chats (⌃⌥C)", action: #selector(toggle), keyEquivalent: "")
        menu.addItem(withTitle: "Refresh", action: #selector(refresh), keyEquivalent: "")
        loginItem = menu.addItem(withTitle: "Launch at login", action: #selector(toggleLogin), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.tick() }
        Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in self?.store.refresh() }
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == UInt16(kVK_Escape) {
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
        if CommandLine.arguments.contains("--show") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.toggle() }
        }
    }

    @objc func refresh() { store.refresh() }

    @objc func toggleLogin() {
        let s = SMAppService.mainApp
        do {
            if s.status == .enabled { try s.unregister() } else { try s.register() }
        } catch {
            NSLog("ClaudeSwipe login item: \(error)")
        }
        updateLoginItem()
    }

    func updateLoginItem() {
        let st = SMAppService.mainApp.status
        loginItem.state = st == .enabled ? .on : .off
        loginItem.title = st == .requiresApproval ? "Launch at login (approve in System Settings)" : "Launch at login"
    }

    // Polls the cursor; no Accessibility permission needed.
    func tick() {
        let p = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(p, $0.frame, false) }) else { return }
        if shown {
            let zone = panel.frame.insetBy(dx: -40, dy: -40)
            if zone.contains(p) { mouseWasInside = true } else if mouseWasInside { hide() }
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

    func hide() {
        guard shown else { return }
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
        if let d = c.desktop_id, let url = URL(string: "claude://code/continue?session=\(d)") {
            hide()
            NSWorkspace.shared.open(url)
            return
        }
        // Terminal-only chat: copy a resume command instead.
        let cmd = "cd '\(c.cwd ?? NSHomeDirectory())' && claude -r \(c.id)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cmd, forType: .string)
        store.notice = "Copied resume command for “\(c.title)”. Paste it in a terminal."
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
