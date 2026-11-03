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
    let app: String
    let desktop_id: String?
    let cwd: String?
}

final class Store: ObservableObject {
    @Published var chats: [Chat] = []
    @Published var updating = false
    @Published var error: String?
    @Published var notice: String?
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

// MARK: - Views

let groupOrder: [(key: String, label: String, color: Color)] = [
    ("waiting", "Waiting on you", .orange),
    ("stuck", "Stuck or needs permission", .red),
    ("unsure", "Unclear", .gray),
    ("running", "Working", .blue),
    ("done", "Done", .green),
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Claude chats").font(.system(size: 15, weight: .semibold))
                Spacer()
                if store.updating { ProgressView().controlSize(.small) }
                Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Refresh")
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            Divider()
            if let n = store.notice {
                Text(n).font(.caption).padding(.horizontal, 16).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.15))
            }
            if let e = store.error {
                Text(e).font(.caption).foregroundStyle(.red).padding(16)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(groupOrder, id: \.key) { g in
                        let items = store.chats.filter { $0.status == g.key }
                        if !items.isEmpty {
                            Text("\(g.label) · \(items.count)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 2)
                            ForEach(items) { c in Row(chat: c, color: g.color).onTapGesture { open(c) } }
                        }
                    }
                }
                .padding(.horizontal, 6).padding(.bottom, 12)
            }
        }
    }
}

struct Row: View {
    let chat: Chat
    let color: Color
    @State private var hover = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(color).frame(width: 8, height: 8).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(chat.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(ageText(chat.age)).font(.caption).foregroundStyle(.secondary)
                }
                Text(chat.folder + (chat.app == "cli" ? " · terminal" : ""))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if !chat.why.isEmpty {
                    Text(chat.why).font(.caption).foregroundStyle(.primary.opacity(0.8)).lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(hover ? 0.08 : 0)))
        .contentShape(Rectangle())
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
    let width: CGFloat = 400
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

        let fx = NSVisualEffectView()
        fx.material = .hudWindow
        fx.blendingMode = .behindWindow
        fx.state = .active
        fx.wantsLayer = true
        fx.layer?.cornerRadius = 14
        fx.layer?.masksToBounds = true
        let host = NSHostingView(rootView: PanelView(store: store, open: { [weak self] in self?.open($0) }))
        host.autoresizingMask = [.width, .height]
        fx.addSubview(host)
        panel.contentView = fx

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
            if e.keyCode == UInt16(kVK_Escape) { self?.hide(); return nil }
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
