import Foundation

// Settings › Cards › Group by. Status is the smart sections from recent_chats.py;
// Day groups chats by the day of their last message. AppKit-free, so tests/run.sh can check it.
enum GroupBy: String, CaseIterable, Identifiable {
    case status, day
    var id: String { rawValue }
    var name: String { self == .status ? "Status" : "Day" }
}

// Day groups in panel order. Pinned first, then today back to 6 days ago, then Older.
// Keys are stable ("d0" is today); labels are worked out against `now`.
func dayGroups(now: Date, calendar: Calendar = .current) -> [(key: String, label: String)] {
    var out: [(key: String, label: String)] = [("pinned", "Pinned"), ("d0", "Today"), ("d1", "Yesterday")]
    let f = DateFormatter()
    f.calendar = calendar
    f.timeZone = calendar.timeZone
    f.locale = calendar.locale ?? .current
    f.setLocalizedDateFormatFromTemplate("EEEE")
    let today = calendar.startOfDay(for: now)
    for n in 2...6 {
        let day = calendar.date(byAdding: .day, value: -n, to: today)!
        out.append(("d\(n)", f.string(from: day)))
    }
    out.append(("older", "Older"))
    return out
}

// Which day group a chat goes in. Days start at local midnight. A time in the future
// (a clock change) counts as today.
func dayKey(activeAt: Date, pinned: Bool, now: Date, calendar: Calendar = .current) -> String {
    if pinned { return "pinned" }
    let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: activeAt),
                                       to: calendar.startOfDay(for: now)).day ?? 0
    if days <= 0 { return "d0" }
    return days <= 6 ? "d\(days)" : "older"
}

// In the Indent layout a linked family stays together: every member is placed by the
// newest message in its family, so a new side session pulls yesterday's parent into
// Today. Pinned members sit in Pinned and don't pull the rest. Rows without a family
// keep their own time.
func familyTimes<T>(_ items: [T], time: (T) -> Double, family: (T) -> String?, pinned: (T) -> Bool) -> [Double] {
    var newest: [String: Double] = [:]
    for t in items where !pinned(t) {
        if let f = family(t) { newest[f] = max(newest[f] ?? -.infinity, time(t)) }
    }
    return items.map { t in family(t).flatMap { newest[$0] }.map { max($0, time(t)) } ?? time(t) }
}
