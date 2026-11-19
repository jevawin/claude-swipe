// Plain checks for Sources/Appearance.swift. Run with tests/run.sh.
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
check("groupFillFollowsOpacity", groupFillAlpha(opacity: 100, background: .frosted) == 0.55
  && groupFillAlpha(opacity: 0, background: .frosted) == 0 && groupFillAlpha(opacity: 50, background: .glass) == 0.16)
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

check("shortFolderLast", shortFolder("clients/funky-pigeon") == "funky-pigeon" && shortFolder("clients") == "clients")
check("shortFolderHome", shortFolder("~/Developer") == "Developer" && shortFolder("~") == "~")
check("shortFolderWorktree", shortFolder("personal/claude-swipe @claude/panel-redesign") == "claude-swipe @claude/panel-redesign")
check("shortFolderSpecial", shortFolder("(no folder)") == "(no folder)" && shortFolder("?") == "?")
if failures > 0 { print("\(failures) failed"); exit(1) }
print("all passed")
