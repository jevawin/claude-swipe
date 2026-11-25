// Plain checks for Sources/Appearance.swift and Sources/LinkedChats.swift. Run with tests/run.sh.
import CoreGraphics
import Foundation

var failures = 0
func check(_ name: String, _ cond: Bool) {
    print("\(cond ? "PASS" : "FAIL") \(name)")
    if !cond { failures += 1 }
}

check("defaultIsFrosted66", defaultAppearance == AppearanceValues(background: .frosted, opacity: 66))
check("clampedToFloor", clampedToFloor(AppearanceValues(background: .frosted, opacity: -20)).opacity == opacityFloor
  && clampedToFloor(AppearanceValues(background: .frosted, opacity: 140)).opacity == 100)
let custom = AppearanceValues(background: .glass, opacity: 30)
check("effectiveSolidRequired", effective(custom, solidRequired: true, glassAvailable: true)
  == AppearanceValues(background: .solid, opacity: 100))
check("effectiveSolidIsOpaque", effective(AppearanceValues(background: .solid, opacity: 20), solidRequired: false, glassAvailable: true).opacity == 100)
check("glassFallsBackToFrostedBelow26", effective(custom, solidRequired: false, glassAvailable: false)
  == AppearanceValues(background: .frosted, opacity: 30))
check("effectiveKeepsGlass", effective(custom, solidRequired: false, glassAvailable: true) == custom)
check("groupFillFollowsOpacity", groupFillAlpha(opacity: 100, background: .solid) == 0.85
  && groupFillAlpha(opacity: 50, background: .glass) == 0.16)
check("frostedGroupsStaySolid", groupFillAlpha(opacity: 0, background: .frosted) == 1
  && groupFillAlpha(opacity: 100, background: .frosted) == 1)
let vis = CGRect(x: 0, y: 0, width: 1512, height: 944)
let panel = CGRect(x: 1072, y: 0, width: 440, height: 944)
check("settingsOriginCentredWhenClear", settingsOrigin(window: CGSize(width: 600, height: 580), panel: panel, visible: vis).x == 456)
check("settingsOriginShiftsLeft", settingsOrigin(window: CGSize(width: 760, height: 580), panel: panel, visible: vis).x == 312)
let narrow = CGRect(x: 0, y: 0, width: 1000, height: 700)
check("settingsOriginNarrowScreen", settingsOrigin(window: CGSize(width: 760, height: 580), panel: CGRect(x: 560, y: 0, width: 440, height: 700), visible: narrow).x == 0)

let d = UserDefaults(suiteName: "test.\(UUID())")!
d.set("folder", forKey: "emojiSource"); d.set(true, forKey: "aiEmoji"); d.set("emoji", forKey: "cardIcon")
migrateIconPrefs(d)
check("migrationCopies", d.string(forKey: "iconSource") == "folder" && d.bool(forKey: "aiIcon") && d.object(forKey: "cardIcon") == nil)
d.set("subject", forKey: "iconSource"); migrateIconPrefs(d)
check("migrationRunsOnce", d.string(forKey: "iconSource") == "subject")

check("topicSymbolListed", topicSymbol("key", status: "waiting", allow: ["key"]) == "key")
check("topicSymbolFallback", topicSymbol("🔑", status: "waiting", allow: ["key"]) == "questionmark")
check("topicSymbolNil", topicSymbol(nil, status: "done", allow: ["key"]) == "checkmark")

let d2 = UserDefaults(suiteName: "test.\(UUID())")!
d2.set(true, forKey: "aiEmoji"); d2.set(false, forKey: "showEmoji")
migrateIconPrefs(d2)
check("migrationKeepsEmojiOffAsAIOff", d2.bool(forKey: "aiIcon") == false)
let d3 = UserDefaults(suiteName: "test.\(UUID())")!
d3.set(true, forKey: "aiEmoji")  // showEmoji never set: it defaulted to on
migrateIconPrefs(d3)
check("migrationShowEmojiDefaultOn", d3.bool(forKey: "aiIcon") == true)
check("hideBlockedWhileSettingsOpen", !panelMayHide(settingsOpen: true, explicit: false))
check("explicitHideWhileSettingsOpen", panelMayHide(settingsOpen: true, explicit: true))
check("hideWhenSettingsClosed", panelMayHide(settingsOpen: false, explicit: false))

let one = shortFolders(["clients/funky-pigeon", "~", "(no folder)", "?", "personal/claude-swipe @claude/panel-redesign"])
check("shortFoldersSingles", one["clients/funky-pigeon"] == "funky-pigeon" && one["~"] == "~" && one["(no folder)"] == "(no folder)"
  && one["?"] == "?" && one["personal/claude-swipe @claude/panel-redesign"] == "claude-swipe @claude/panel-redesign")
let sf = shortFolders(["personal/acme", "clients/acme", "clients/bookmygarage", "clients", "~/Developer", "a/x/acme", "personal/claude-swipe @main", "personal/claude-swipe"])
check("shortFoldersUnique", sf["personal/acme"] == "personal/acme" && sf["clients/acme"] == "clients/acme"
  && sf["clients/bookmygarage"] == "bookmygarage" && sf["clients"] == "clients" && sf["~/Developer"] == "Developer")
check("shortFoldersDeeper", sf["a/x/acme"] == "x/acme")
check("shortFoldersWorktree", sf["personal/claude-swipe @main"] == "claude-swipe @main" && sf["personal/claude-swipe"] == "claude-swipe")
// Linked chats, Indent layout. Items are (id, parent), newest first.
typealias L = (id: String, parent: String?)
func tree(_ xs: [L]) -> [(String, TreeSpot)] { treeOrder(xs, id: { $0.id }, node: { $0.id }, parent: { $0.parent }).map { ($0.item.id, $0.spot) } }
let t1 = tree([("kid", "mum"), ("x", nil), ("mum", nil)])
check("treeChildUnderParent", t1.map(\.0) == ["mum", "kid", "x"])  // the busy child pulls its parent up
check("treeSpots", t1[0].1 == TreeSpot(depth: 0, guides: [], last: true, hasKids: true) && t1[1].1 == TreeSpot(depth: 1, guides: [], last: true, hasKids: false))
check("treeParentNotListedStaysTop", tree([("kid", "gone"), ("x", nil)]).map { $0.1.depth } == [0, 0])
let t2 = tree([("a", nil), ("b", "a"), ("b1", "b"), ("c", "a")])
check("treeGrandchild", t2.map(\.0) == ["a", "b", "b1", "c"] && t2.map { $0.1.depth } == [0, 1, 2, 1])
check("treeGuideRunsPastGrandchild", t2[2].1.guides == [true] && !t2[1].1.last && t2[3].1.last)
check("treeLoopShowsEachOnce", Set(tree([("p", "q"), ("q", "p")]).map(\.0)) == ["p", "q"])
check("treeSelfParent", tree([("s", "s")]).map { $0.1.depth } == [0])

// Group by Day. Fixed calendar so the checks don't depend on this Mac's settings.
var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "Europe/London")!
cal.locale = Locale(identifier: "en_GB")
func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: mi))!
}
let wedEarly = at(2026, 11, 25, 0, 30)  // Wednesday, just past midnight
check("dayToday", dayKey(activeAt: at(2026, 11, 25, 0, 5), pinned: false, now: wedEarly, calendar: cal) == "d0")
check("dayMidnightSplits", dayKey(activeAt: at(2026, 11, 24, 23, 55), pinned: false, now: wedEarly, calendar: cal) == "d1")
check("daySixBack", dayKey(activeAt: at(2026, 11, 19, 0, 1), pinned: false, now: wedEarly, calendar: cal) == "d6")
check("daySevenIsOlder", dayKey(activeAt: at(2026, 11, 18, 23, 59), pinned: false, now: wedEarly, calendar: cal) == "older")
check("dayFutureIsToday", dayKey(activeAt: at(2026, 11, 26, 9), pinned: false, now: wedEarly, calendar: cal) == "d0")
check("dayPinnedWins", dayKey(activeAt: at(2026, 1, 1, 9), pinned: true, now: wedEarly, calendar: cal) == "pinned")
// Clocks went back on 25 Oct 2026: still whole days, not 24-hour blocks.
check("dayAcrossClockChange", dayKey(activeAt: at(2026, 10, 24, 23, 59), pinned: false, now: at(2026, 10, 28, 0, 1), calendar: cal) == "d4")
let labels = dayGroups(now: wedEarly, calendar: cal).map(\.label)
check("dayLabels", labels == ["Pinned", "Today", "Yesterday", "Monday", "Sunday", "Saturday", "Friday", "Thursday", "Older"])

if failures > 0 { print("\(failures) failed"); exit(1) }
print("all passed")
