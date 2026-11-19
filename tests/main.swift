// Plain checks for Sources/Appearance.swift. Run with tests/run.sh.
import CoreGraphics
import Foundation

var failures = 0
func check(_ name: String, _ cond: Bool) {
    print("\(cond ? "PASS" : "FAIL") \(name)")
    if !cond { failures += 1 }
}

check("presetsMatchSpec",
  StylePreset.solid.values == AppearanceValues(opacity: 100, blur: .off, fade: 0, glass: .off) &&
  StylePreset.frosted.values == AppearanceValues(opacity: 66, blur: .light, fade: 40, glass: .regular) &&
  StylePreset.clear.values == AppearanceValues(opacity: opacityFloor, blur: .heavy, fade: 70, glass: .clear))
check("defaultIsFrosted", matchedPreset(defaultAppearance) == .frosted)
check("customWhenTouched", matchedPreset(AppearanceValues(opacity: 67, blur: .light, fade: 40, glass: .regular)) == nil)
check("clampedToFloor", clampedToFloor(AppearanceValues(opacity: 20, blur: .light, fade: 140, glass: .off)).opacity == 60
  && clampedToFloor(AppearanceValues(opacity: 20, blur: .light, fade: 140, glass: .off)).fade == 100)
let custom = AppearanceValues(opacity: 70, blur: .heavy, fade: 55, glass: .clear)
check("effectiveSolidKeepsInput", effective(custom, solidRequired: true, glassAvailable: true)
  == AppearanceValues(opacity: 100, blur: .off, fade: 0, glass: .off) && custom.opacity == 70)
check("glassOffBelow26", effective(custom, solidRequired: false, glassAvailable: false).glass == .off)
check("fadeZeroNoStops", fadeStops(0).isEmpty)
check("fadeStops40", fadeStops(40).map(\.location) == [0, 0.2, 0.4] && fadeStops(40).map(\.alpha) == [0, 0.5, 1])
let vis = CGRect(x: 0, y: 0, width: 1512, height: 944)
let panel = CGRect(x: 1072, y: 0, width: 440, height: 944)
check("settingsOriginCentredWhenClear", settingsOrigin(window: CGSize(width: 600, height: 580), panel: panel, visible: vis).x == 456)
check("settingsOriginShiftsLeft", settingsOrigin(window: CGSize(width: 760, height: 580), panel: panel, visible: vis).x == 312)
let narrow = CGRect(x: 0, y: 0, width: 1000, height: 700)
check("settingsOriginNarrowScreen", settingsOrigin(window: CGSize(width: 760, height: 580), panel: CGRect(x: 560, y: 0, width: 440, height: 700), visible: narrow).x == 0)

if failures > 0 { print("\(failures) failed"); exit(1) }
print("all passed")
