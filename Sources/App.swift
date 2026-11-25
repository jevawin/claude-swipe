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
    var active_at: Double?  // epoch time of the last message, for Group by Day
    var section: String
    let app: String
    let desktop_id: String?
    let cwd: String?
    var icon: String?     // topic SF Symbol name; only names in icons.json are shown
    var own_icon: Bool?   // your own pick decides the icon (counted for Re-pick)
    var pinned: Bool?
    var parent: String?   // desktop id of the chat this one was started from
    var family: String?   // top of its side-session chain; set only when 2+ listed chats share it
    var familyColour: Int?  // index into ChatRow.familyPalette, set by Store.assignFamilyColours
    var parent_title: String?  // the parent's title, for "from <parent>" when it isn't listed above
}

// The Indent layout of linked chats (treeOrder) lives in Sources/LinkedChats.swift.
func treeOrder(_ items: [Chat]) -> [(chat: Chat, spot: TreeSpot)] {
    treeOrder(items, id: \.id, node: \.desktop_id, parent: \.parent).map { ($0.item, $0.spot) }
}

// The SF Symbol names topic icons may use (icons.json in Resources, shared with recent_chats.py).
let iconAllowlist: Set<String> = {
    guard let url = Bundle.main.url(forResource: "icons", withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let d = try? JSONDecoder().decode([String: [String]].self, from: data) else { return [] }
    return Set(d["symbols"] ?? [])
}()

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
        case .success(var c): Store.assignFamilyColours(&c); chats = c; error = nil
        case .failure(let e): error = "\(e)"
        }
    }

    // Linked-chat families take colours in palette order, so the first few on screen never look
    // alike. A family keeps its colour while it's listed (remembered across launches); a new
    // family takes the first colour no listed family has. Past the palette's end, colours repeat.
    static func assignFamilyColours(_ chats: inout [Chat]) {
        let key = "familyColours", n = ChatRow.familyPalette.count
        var families: [String] = []
        for c in chats { if let f = c.family, !families.contains(f) { families.append(f) } }
        let saved = UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
        var colour: [String: Int] = [:], used = Set<Int>()
        for f in families { if let i = saved[f], i < n, !used.contains(i) { colour[f] = i; used.insert(i) } }
        for f in families where colour[f] == nil {
            let i = (0..<n).first { !used.contains($0) } ?? colour.count % n
            colour[f] = i; used.insert(i)
        }
        UserDefaults.standard.set(colour, forKey: key)
        for i in chats.indices { chats[i].familyColour = chats[i].family.flatMap { colour[$0] } }
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
    // The panel behind the groups: a few steps darker than bg in light mode, so white
    // groups stand out. Dark mode unchanged.
    static let panelBg = themed(hsl(45, 22, 92.5), hsl(60, 2.7, 14.5))
    static let text = themed(hsl(60, 2.6, 7.6), hsl(48, 33.3, 97.1))        // --text-100
    static let secondary = themed(hsl(51, 3.1, 43.7), hsl(48, 4.8, 59.2))   // --text-400
    static let border = themed(hsl(51, 16.5, 84.5), hsl(50, 9, 73.7).withAlphaComponent(0.15))
    static let brand = Color(nsColor: hsl(15, 63.1, 59.6))                  // --accent-brand
    static let card = themed(.white, hsl(60, 2.1, 18.4))                    // --bg-000
    static let cardHover = themed(hsl(53, 28.6, 94.5), hsl(60, 2.1, 21))
    static let sidebar = themed(hsl(50, 25, 92), hsl(60, 2.5, 12.5))
    // The redesigned panel's secondary text, brightened in dark to stay readable see-through.
    static let panelSecondary = themed(NSColor(srgbRed: 0x57 / 255.0, green: 0x56 / 255.0, blue: 0x4F / 255.0, alpha: 1),
                                       NSColor(srgbRed: 0xC4 / 255.0, green: 0xC2 / 255.0, blue: 0xBA / 255.0, alpha: 1))
    // Group outlines and row dividers: 5% black in light, 6% white in dark.
    static let hairline = themed(NSColor(white: 0, alpha: 0.05), NSColor(white: 1, alpha: 0.06))
}

// MARK: - Views

// Status sets the card's tile (or its badge): colour, SF Symbol and a spoken name.
// Symbol names live in statusSymbol (Appearance.swift).
func hex(_ v: Int) -> NSColor {
    NSColor(srgbRed: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}

// State colours: one set, with a light and a dark version of each state (Jamie, 23 Nov 2026,
// folding Kris's two dark sets into one). The dark versions are lighter and brighter so the
// tinted icon shows on a dark or see-through panel. The solid icon always uses the light
// version, so its white symbol stays readable in both modes.
// Ready to clear is a guess that a done chat is finished with, so it's a quieter
// version of Done's green rather than a colour of its own.
private let stateColours: [String: (light: NSColor, dark: NSColor)] = [
    "running": (hsl(210, 60, 52), hex(0x7DB5F2)),
    "waiting": (hsl(38, 92, 50), hex(0xFFC04D)),
    "blocked": (hsl(0, 72, 52), hex(0xFF7A7A)),
    "done": (hsl(120, 35, 42), hex(0x6FD87A)),
    "finished": (hsl(120, 18, 55), hex(0x9DBF8F)),
    "stuck": (hsl(48, 4.8, 50), hex(0xBAB8AD)),
    "unsure": (hsl(48, 4.8, 50), hex(0xBAB8AD)),
]

// Tinted icons (and anything else that shows a state colour) use statusStyle.
let statusStyle: [String: (color: Color, icon: String)] = stateColours.reduce(into: [:]) { out, e in
    out[e.key] = (themed(e.value.light, e.value.dark), statusSymbol[e.key]!)
}
// For a solid icon style: a full fill with a white symbol, the light version in both modes.
let statusSolid: [String: Color] = stateColours.mapValues { Color(nsColor: $0.light) }

// Sections come from recent_chats.py: pinned chats, then touched in the last
// hour, then not-done chats split by today vs older, then everything done.
let sections: [(key: String, label: String)] = [
    ("pinned", "Pinned"),
    ("active", "Active"),
    ("today", "Waiting · today"),
    ("older", "Waiting · older"),
    ("done", "Done"),
    ("clear", "Ready to clear"),
]

// One line on each state, for the icon tooltip and Settings › Guide.
let statusMeaning: [String: String] = [
    "running": "Claude is working on it.",
    "waiting": "Claude asked you something or wants a reply.",
    "blocked": "Needs a click from you to carry on, often a permission prompt.",
    "done": "Claude finished its turn. There may still be more to do.",
    "finished": "The AI thinks the whole job is finished, so you can archive it. A guess, so check first.",
    "stuck": "A prompt went in, but no reply has come back for a while.",
    "unsure": "ClaudeSwipe couldn't tell what state this chat is in.",
]
let statusOrder = ["running", "waiting", "blocked", "done", "finished", "stuck", "unsure"]

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
    let editIcon: (Chat) -> Void
    let togglePin: (Chat) -> Void
    let openSettings: () -> Void
    @ObservedObject private var prefs = Prefs.shared
    @FocusState private var searchFocused: Bool
    @LocalState private var hovered: String? = nil

    // Every word must appear somewhere in title, folder or preview.
    var filtered: [Chat] {
        let words = store.query.lowercased().split(separator: " ")
        if words.isEmpty { return store.chats }
        return store.chats.filter { c in
            let hay = "\(c.title) \(c.folder) \(c.why)".lowercased()  // not symbol names
            return words.allSatisfy { hay.contains($0) }
        }
    }

    // What Return opens: the first match in section order.
    var firstMatch: Chat? { grouped().flatMap { arranged($0.items) }.first?.chat }

    // The groups the panel shows, each with its chats in order. Status uses the sections
    // from recent_chats.py as sorted there. Day puts each chat under the day of its last
    // message (DayGroups.swift), newest first; labels follow the clock at draw time.
    func grouped() -> [(sec: (key: String, label: String), items: [Chat])] {
        let chats = filtered
        guard prefs.groupBy == .day else {
            return sections.map { s in (s, chats.filter { $0.section == s.key }) }.filter { !$0.items.isEmpty }
        }
        let now = Date()
        func when(_ c: Chat) -> Double { c.active_at ?? now.timeIntervalSince1970 - c.age }
        let byKey = Dictionary(grouping: chats) {
            dayKey(activeAt: Date(timeIntervalSince1970: when($0)), pinned: $0.pinned == true, now: now)
        }
        return dayGroups(now: now).compactMap { s in
            guard let items = byKey[s.key] else { return nil }
            return (s, items.sorted { when($0) > when($1) })
        }
    }

    // A section's rows in display order: as listed, or as a tree in the Indent layout.
    func arranged(_ items: [Chat]) -> [(chat: Chat, spot: TreeSpot?)] {
        prefs.linkStyle == .indent ? treeOrder(items).map { ($0.chat, $0.spot) } : items.map { ($0, nil) }
    }

    // Short folder names, worked out across every chat so they don't change while searching.
    var folderNames: [String: String] { shortFolders(store.chats.map(\.folder)) }

    // What the panel draws: the saved values, forced solid by Reduce transparency.
    var look: AppearanceValues {
        effective(prefs.appearance, solidRequired: prefs.systemSolid, glassAvailable: glassAvailable)
    }

    // Search as the title: a 40pt pill with Refresh and Settings inside.
    var searchPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(Theme.panelSecondary)
                .accessibilityHidden(true)
            TextField("Search Claude chats", text: $store.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .medium))
                .focused($searchFocused)
                .onSubmit { if let first = firstMatch { open(first) } }
            if store.updating { ProgressView().controlSize(.small) }
            Button { store.refresh() } label: { Image(systemName: "arrow.clockwise").font(.system(size: 13)) }
                .buttonStyle(.borderless)
                .help("Refresh")
                .accessibilityLabel("Refresh")
            Button { openSettings() } label: { Settings2Image() }
                .buttonStyle(.borderless)
                .help("Settings")
                .accessibilityLabel("Settings")
        }
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(GroupBackground(look: look))
        .modifier(GlassLift(on: look.background == .glass))
        .onChange(of: store.focusTick) { searchFocused = true }
        .onAppear { searchFocused = true }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchPill.padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 4)
            if let n = store.notice {
                Text(n).font(.system(size: 13)).padding(.horizontal, 16).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.15))
            }
            if let e = store.error {
                Text(e).font(.system(size: 13)).foregroundStyle(.red).padding(16)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(grouped(), id: \.sec.key) { g in section(g.sec, g.items) }
                }
                .padding(.horizontal, 12).padding(.bottom, 12)
            }
        }
        .foregroundStyle(Theme.text)
        .background(ZStack {
            PanelMaterial(visible: look.background == .frosted)
            PanelTint(opacity: look.opacity, sheen: look.background == .frosted ? look.opacity / 100 : 1)
        })
    }

    // Settings › Cards › Fade: which of Done and Ready to clear fade, by the fade amount.
    // With both, Ready to clear fades a step further, so the most settled chats look quietest.
    // Grouped by Day there are no such sections, so each row fades by its own state.
    func rowOpacity(_ c: Chat, section key: String) -> Double {
        if prefs.groupBy == .day {
            return sectionOpacity(c.status == "done" ? "done" : c.status == "finished" ? "clear" : "")
        }
        return sectionOpacity(key)
    }

    func sectionOpacity(_ key: String) -> Double {
        let w = prefs.fadeWhich
        switch key {
        case "done" where w == "both" || w == "done": return 1 - prefs.doneFade / 100
        case "clear" where w == "both": return 1 - min(80, prefs.doneFade + 15) / 100
        case "clear" where w == "clear": return 1 - prefs.doneFade / 100
        default: return 1
        }
    }

    @ViewBuilder func section(_ sec: (key: String, label: String), _ items: [Chat]) -> some View {
        let collapsible = sec.key == "done"
        let names = folderNames
        let open_ = !collapsible || prefs.showDone || !store.query.isEmpty
        HStack(spacing: 0) {
            Text(sec.label).font(.system(size: 12.5, weight: .semibold))
            Text(" \(items.count)").font(.system(size: 12.5)).opacity(0.8)
            Spacer()
            // Only Done collapses for now, so only Done gets a chevron.
            if collapsible {
                Image(systemName: open_ ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(Theme.text)
        .modifier(HeaderGlow(on: look.opacity < 100))
        .padding(.horizontal, 4).padding(.top, 12).padding(.bottom, 2)
        .contentShape(Rectangle())
        .onTapGesture { if collapsible { prefs.showDone.toggle() } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        if open_ {
            VStack(spacing: 0) {
                ForEach(Array(arranged(items).enumerated()), id: \.element.chat.id) { i, row in
                    let c = row.chat
                    ChatRow(chat: c, selected: hovered == c.id || (hovered == nil && !store.query.isEmpty && c.id == firstMatch?.id),
                            density: prefs.density, divider: i > 0, folderName: names[c.folder], spot: row.spot)
                        .opacity(rowOpacity(c, section: sec.key))
                        .contentShape(Rectangle())
                        .onHover { if $0 { hovered = c.id } else if hovered == c.id { hovered = nil } }
                        .onTapGesture { open(c) }
                        .contextMenu {
                            Button(c.pinned == true ? "Unpin" : "Pin") { togglePin(c) }
                            Button("Change topic icon…") { editIcon(c) }
                        }
                }
            }
            .background(GroupBackground(look: look))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .modifier(GlassLift(on: look.background == .glass))
        }
    }
}

// When the panel is see-through, section headers get a soft glow in the panel colour to stay readable.
struct HeaderGlow: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on {
            content.shadow(color: Theme.bg.opacity(0.95), radius: 6).shadow(color: Theme.bg.opacity(0.8), radius: 12)
        } else {
            content
        }
    }
}

// A circle in the state's colour holding the topic symbol. Tinted (Settings › Appearance ›
// Icons): a pale tint with the symbol in the colour. Solid: the full colour with a white symbol.
struct StateIcon: View {
    let symbol: String
    let color: Color
    let size: CGFloat
    var solidColor: Color? = nil  // the Solid style's fill (statusSolid); falls back to color
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var prefs = Prefs.shared

    var body: some View {
        let solid = prefs.solidIcons
        // Tint strength: Kris raised dark to 0.44 (22 Nov 2026); Jamie found both too faint
        // (23 Nov 2026), so 0.55 dark and 0.20 light. Picked by eye on an offscreen render.
        Circle().fill(solid ? (solidColor ?? color) : color.opacity(scheme == .dark ? 0.55 : 0.20))
            .overlay(Image(systemName: symbol).font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(solid ? .white : color))
            .frame(width: size, height: size)
    }
}

// One chat in a section group. Cozy: icon, title over summary, age over folder.
// Compact: one line, no summary, and it doesn't grow on hover (Jamie, 19 Nov 2026).
struct ChatRow: View {
    let chat: Chat
    let selected: Bool
    let density: Density
    let divider: Bool
    var folderName: String? = nil  // shortFolders' name for chat.folder; nil shows the last folder
    var spot: TreeSpot? = nil      // set in the Indent layout of linked chats
    @ObservedObject var prefs = Prefs.shared

    var iconSize: CGFloat { m.icon }
    var indentStep: CGFloat { iconSize / 2 + 12 }
    var ring: Bool { prefs.linkStyle == .ring }
    // Indent layout, top level, but started from another chat: say which one.
    var fromTitle: String? {
        guard let s = spot, s.depth == 0, chat.parent != nil else { return nil }
        return chat.parent_title
    }

    var folder: String? { prefs.hidesLabel(chat.folder) ? nil : chat.folder }

    var icon: some View {
        let st = statusStyle[chat.status] ?? statusStyle["unsure"]!
        return StateIcon(symbol: topicSymbol(chat.icon, status: chat.status, allow: iconAllowlist),
                         color: st.color, size: m.icon, solidColor: statusSolid[chat.status])
            .overlay { if ring, let c = familyColor { Circle().strokeBorder(c, lineWidth: 2.5) } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel((statusName[chat.status] ?? "Unsure") + linkLabel)
            .help("\(statusName[chat.status] ?? "Unsure"): \(statusMeaning[chat.status] ?? "")")
    }

    var linkLabel: String {
        if ring { return chat.family == nil ? "" : ", linked chat" }
        if let s = spot, s.depth > 0 { return ", started from the chat above" }
        if let t = fromTitle { return ", started from \(t)" }
        return ""
    }

    // "↳ from <parent>", one line, under the title.
    func fromLine(_ t: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.turn.down.right").font(.system(size: 9.5, weight: .semibold)).accessibilityHidden(true)
            Text("from \(t)").lineLimit(1).truncationMode(.tail)
        }
        .font(.system(size: m.meta - 0.5)).foregroundStyle(Theme.panelSecondary)
        .help("Started from \(t)")
    }

    // The lines joining a child to its parent: an elbow from the parent's icon, plus
    // straight lines for any ancestor whose later children are still to come.
    func treeLines(_ s: TreeSpot, _ size: CGSize) -> Path {
        let mid = size.height / 2
        func x(_ level: Int) -> CGFloat { 12 + CGFloat(level) * indentStep + iconSize / 2 }
        var p = Path()
        for (k, on) in s.guides.enumerated() where on {
            p.move(to: CGPoint(x: x(k), y: 0)); p.addLine(to: CGPoint(x: x(k), y: size.height))
        }
        if s.depth > 0 {
            let px = x(s.depth - 1), r: CGFloat = 6
            p.move(to: CGPoint(x: px, y: 0))
            if !s.last { p.addLine(to: CGPoint(x: px, y: size.height)); p.move(to: CGPoint(x: px, y: 0)) }
            p.addLine(to: CGPoint(x: px, y: mid - r))
            p.addQuadCurve(to: CGPoint(x: px + r, y: mid), control: CGPoint(x: px, y: mid))
            p.addLine(to: CGPoint(x: x(s.depth) - iconSize / 2 - 4, y: mid))
        }
        if s.hasKids {  // a stub from under this row's icon down to its first child
            p.move(to: CGPoint(x: x(s.depth), y: mid + iconSize / 2 + 3)); p.addLine(to: CGPoint(x: x(s.depth), y: size.height))
        }
        return p
    }

    var m: RowMetrics { RowMetrics.of(density, scale: prefs.textScale) }

    var summary: some View {
        Text(chat.why).font(.system(size: m.summary)).foregroundStyle(Theme.panelSecondary).lineLimit(prefs.summaryLines(density))
    }

    // Linked chats (a chat and the side sessions started from it) share a border
    // ring round the state icon. Store.assignFamilyColours picks which one. Ordered so
    // neighbours contrast, and kept away from the status colours (blue, amber, red, green, purple).
    static let familyPalette: [NSColor] = [
        0xEE1D52,  // raspberry
        0x0FA37F,  // jade (greener than sky, so the two don't blur)
        0xF9DC1C,  // lemon (clear of the amber "waiting" colour)
        0x2E3F9E,  // navy
        0x8CC63F,  // lime
        0x5CC8F5,  // sky
    ].map { NSColor(srgbRed: CGFloat($0 >> 16 & 0xFF) / 255, green: CGFloat($0 >> 8 & 0xFF) / 255, blue: CGFloat($0 & 0xFF) / 255, alpha: 1) }
    var familyColor: Color? {
        chat.familyColour.map { Color(nsColor: ChatRow.familyPalette[$0 % ChatRow.familyPalette.count]) }
    }

    var body: some View {
        Group {
            if density != .compact {
                HStack(alignment: .center, spacing: m.spacing) {
                    icon
                    VStack(alignment: .leading, spacing: m.gap) {
                        Text(chat.title).font(.system(size: m.title, weight: .semibold)).lineLimit(1)
                        if let t = fromTitle { fromLine(t) }
                        if !chat.why.isEmpty { summary }
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: m.gap) {
                        Text(ageText(chat.engaged))
                        if let f = folder { Text(folderName ?? shortFolders([f])[f] ?? f).lineLimit(1).truncationMode(.middle).frame(maxWidth: 120, alignment: .trailing).help(f) }
                    }
                    .font(.system(size: m.meta)).foregroundStyle(Theme.panelSecondary)
                }
                .padding(.vertical, m.vpad)
            } else {
                HStack(alignment: .center, spacing: m.spacing) {
                    icon
                    HStack(spacing: 8) {
                        Text(chat.title).font(.system(size: m.title, weight: .semibold)).lineLimit(1)
                        if let t = fromTitle { fromLine(t).layoutPriority(-1) }  // gives way before title, folder and age
                        Spacer(minLength: 8)
                        Group {
                            if let f = folder { Text(folderName ?? shortFolders([f])[f] ?? f).lineLimit(1).truncationMode(.middle).frame(maxWidth: 120, alignment: .trailing).help(f) }
                            Text(ageText(chat.engaged))
                        }
                        .font(.system(size: m.meta)).foregroundStyle(Theme.panelSecondary)
                    }
                }
                .padding(.vertical, m.vpad)
            }
        }
        .padding(.horizontal, 12)
        .padding(.leading, CGFloat(spot?.depth ?? 0) * indentStep)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Theme.text.opacity(0.06) : .clear)
        .overlay {
            if let s = spot, s.depth > 0 || s.hasKids {
                GeometryReader { g in treeLines(s, g.size).stroke(Theme.panelSecondary.opacity(0.45), lineWidth: 1.5) }
                    .accessibilityHidden(true)
            }
        }
        // A child's divider starts at its own indent, so the branch reads as one block.
        .overlay(alignment: .top) {
            if divider {
                Rectangle().fill(Theme.hairline).frame(height: 1)
                    .padding(.leading, CGFloat(spot?.depth ?? 0) * indentStep)
            }
        }
    }
}

// The edge shadow: clear on the left, darkest where it meets the panel.
struct EdgeShadow: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        // Faint and wide like a macOS window shadow: most of it is a long, light tail.
        let peak = scheme == .dark ? 0.28 : 0.12
        LinearGradient(stops: [
            .init(color: .black.opacity(0), location: 0),
            .init(color: .black.opacity(peak * 0.12), location: 0.4),
            .init(color: .black.opacity(peak * 0.35), location: 0.7),
            .init(color: .black.opacity(peak * 0.7), location: 0.9),
            .init(color: .black.opacity(peak), location: 1),
        ], startPoint: .leading, endPoint: .trailing)
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
        NotificationCenter.default.addObserver(forName: .edgeShadowChanged, object: nil, queue: .main) { [weak self] _ in
            self?.updateEdgeShadow()
        }
        Prefs.shared.onScriptChange = { [weak self] in self?.store.refresh() }

        panel = Panel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless],
                      backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false  // flush to the edge; the optional edge shadow is its own window (edgeShadowWindow)
        // Glass has no panel material, so with See-through above 0 the gaps between groups are
        // part-transparent and scrolls there went to the window behind (Jamie, 19 Nov 2026).
        // Setting this explicitly is meant to make the whole frame take mouse and scroll
        // events. Checked by Jamie on screen, 19 Nov 2026 (harness scroll events were dropped).
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        // The see-through background comes from PanelView (PanelBackground.swift), so the window stays clear.
        panel.contentView = NSHostingView(rootView: PanelView(
            store: store, open: { [weak self] in self?.open($0) },
            editIcon: { [weak self] in self?.editIcon($0) },
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
                if let s = self?.store, !s.query.isEmpty { s.query = "" } else { self?.hide(reason: "esc", explicit: true) }
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
        if shown { hide(reason: "toggle", explicit: true); return }
        let p = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(p, $0.frame, false) }) ?? NSScreen.main!
        show(on: screen)
    }

    func show(on screen: NSScreen) {
        let vf = screen.visibleFrame
        let target = NSRect(x: vf.maxX - width, y: vf.minY, width: width, height: vf.height)
        panelTarget = target
        debugLog("show")
        panel.setFrame(target.offsetBy(dx: width + 20, dy: 0), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }, completionHandler: { [weak self] in self?.updateEdgeShadow() })
        shown = true
        mouseWasInside = target.insetBy(dx: -40, dy: -40).contains(NSEvent.mouseLocation)
        store.notice = nil
        store.query = ""
        store.focusTick += 1
        if Date().timeIntervalSince(store.lastRun) > 20 { store.refresh() }
    }

    // Settings › Appearance › Edge shadow. The panel's own window shadow barely shows (its
    // content is see-through and it's flush to the screen edge), so a separate click-through
    // window draws a soft gradient just left of the panel.
    var edgeShadowWindow: NSWindow?
    let edgeShadowWidth: CGFloat = 40  // click-through, so the width costs nothing

    func updateEdgeShadow() {
        guard shown, Prefs.shared.edgeShadow else { edgeShadowWindow?.orderOut(nil); return }
        let f = panelTarget
        let frame = NSRect(x: f.minX - edgeShadowWidth, y: f.minY, width: edgeShadowWidth, height: f.height)
        if edgeShadowWindow == nil {
            let w = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.level = panel.level
            w.collectionBehavior = panel.collectionBehavior
            w.contentView = NSHostingView(rootView: EdgeShadow())
            edgeShadowWindow = w
        }
        edgeShadowWindow?.setFrame(frame, display: true)
        edgeShadowWindow?.orderFront(nil)
    }

    // The panel stays up the whole time Settings is open, so changes show live.
    var settingsOpen: Bool { settingsWindow?.isVisible == true }

    // explicit: you asked for it (opened a chat, Esc, the hotkey), so it hides even with Settings open.
    func hide(reason: String = "", explicit: Bool = false) {
        guard shown, panelMayHide(settingsOpen: settingsOpen, explicit: explicit) else { return }
        debugLog("hide \(reason)")
        shown = false
        edgeShadowWindow?.orderOut(nil)
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
        // Settings › Windows › Minimise other Claude windows; Command or Option flips it for one click.
        let keepOthers = Prefs.shared.minimiseOthers == !NSEvent.modifierFlags.intersection([.command, .option]).isEmpty
        guard let d = c.desktop_id, let url = URL(string: "claude://code/continue?session=\(d)") else { return }
        hide(reason: "open chat", explicit: true)
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

    // Right-click > Change topic icon. Saves to chat-icons.json "overrides", which beat the AI's picks.
    func editIcon(_ c: Chat) {
        hide()
        let file = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/claude-swipe/chat-icons.json")
        var data = (try? JSONSerialization.jsonObject(with: Data(contentsOf: file))) as? [String: Any] ?? [:]
        var overrides = data["overrides"] as? [String: String] ?? [:]
        let auto = data["auto"] as? [String: String] ?? [:]

        let alert = NSAlert()
        alert.messageText = "Topic icon for “\(c.title)”"
        alert.informativeText = "Pick an icon, or use automatic to let the AI or the folder decide."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 240, height: 28), pullsDown: false)
        popup.addItem(withTitle: "Use automatic")
        popup.menu?.addItem(.separator())
        for name in iconAllowlist.sorted() {
            popup.addItem(withTitle: name)
            popup.lastItem?.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        }
        if let mine = overrides[c.id], iconAllowlist.contains(mine) { popup.selectItem(withTitle: mine) }
        alert.accessoryView = popup
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let pick = popup.indexOfSelectedItem == 0 ? nil : popup.titleOfSelectedItem
        overrides[c.id] = pick  // nil removes your pick; the refresh fills in the AI or folder icon
        data["overrides"] = overrides
        data["auto"] = auto
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let out = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted]) {
            try? out.write(to: file)
        }
        if let i = store.chats.firstIndex(where: { $0.id == c.id }), let p = pick { store.chats[i].icon = p }
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
        if w !== settingsWindow { hide() }  // Settings keeps the panel up; Welcome doesn't
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
        let w = settingsWindow!
        if !w.isVisible {
            // Panel on the Settings window's screen (the mouse's on first open), then the
            // window centred, moved left just enough to clear the panel.
            let p = NSEvent.mouseLocation
            let screen = w.screen ?? NSScreen.screens.first(where: { NSMouseInRect(p, $0.frame, false) }) ?? NSScreen.main!
            showPanel(on: screen)
            w.setFrameOrigin(settingsOrigin(window: w.frame.size, panel: panelTarget, visible: screen.visibleFrame))
        } else if let screen = w.screen {
            showPanel(on: screen)
        }
        bringUp(w)
    }

    // Shows the panel on a screen unless it's already up there.
    func showPanel(on screen: NSScreen) {
        if shown && screen.visibleFrame.contains(NSPoint(x: panelTarget.midX, y: panelTarget.midY)) { return }
        show(on: screen)
    }

    // Settings dragged to another screen: the panel follows it.
    func windowDidChangeScreen(_ n: Notification) {
        guard let w = n.object as? NSWindow, w === settingsWindow, w.isVisible, let screen = w.screen else { return }
        showPanel(on: screen)
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
        let folder = p.iconSource == "folder"
        let rows = store.chats.filter { $0.own_icon != true }
        let n = folder ? Set(rows.map(\.folder)).count : rows.count
        let noun = folder ? (n == 1 ? "folder" : "folders") : (n == 1 ? "chat" : "chats")
        let alert = NSAlert()
        alert.messageText = "Re-pick all topic icons?"
        alert.informativeText = folder
            ? "ClaudeSwipe will ask \(p.modelName) to pick a topic icon again for \(n) \(noun) with chats from the last 7 days. This uses your Claude plan. Icons you picked yourself will not change."
            : "ClaudeSwipe will ask \(p.modelName) to pick a topic icon again for \(n) \(noun) from the last 7 days. This uses your Claude plan. Icons you picked yourself will not change."
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
