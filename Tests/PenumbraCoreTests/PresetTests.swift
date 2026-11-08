import Foundation
import Testing
@testable import PenumbraCore

@Suite struct PresetTests {
    let light = ThemeVariant(wallpaper: .init(imageName: "l.png"), accent: .blue)
    let dark = ThemeVariant(wallpaper: .init(imageName: "d.png"), accent: .purple)

    @Test func fixedPresetUsesItsVariantForBothAppearances() {
        let preset = Preset(name: "F", kind: .fixed(appearance: .dark, variant: dark))
        #expect(preset.appearanceMode == .fixed(.dark))
        #expect(preset.variant(for: .light) == dark)
        #expect(preset.wallpaperTarget(for: .light) == .still(imageName: "d.png"))
    }

    @Test func autoPresetPicksVariantByAppearance() {
        let preset = Preset(name: "A", kind: .auto(light: light, dark: dark))
        #expect(preset.appearanceMode == .automatic)
        #expect(preset.variant(for: .light).accent == .blue)
        #expect(preset.variant(for: .dark).accent == .purple)
    }

    @Test func autoPresetWithTwoWallpapersIsAdaptive() {
        let preset = Preset(name: "A", kind: .auto(light: light, dark: dark))
        #expect(preset.wallpaperTarget(for: .light) == .adaptive(lightImageName: "l.png", darkImageName: "d.png"))
    }

    @Test func autoPresetWithTheSameImageTwiceIsStill() {
        let preset = Preset(name: "A", kind: .auto(light: light, dark: light))
        #expect(preset.wallpaperTarget(for: .dark) == .still(imageName: "l.png"))
    }

    @Test func autoPresetWithOneWallpaperOnlySetsItInThatMode() {
        let preset = Preset(name: "A", kind: .auto(light: light, dark: ThemeVariant(accent: .red)))
        #expect(preset.wallpaperTarget(for: .light) == .still(imageName: "l.png"))
        #expect(preset.wallpaperTarget(for: .dark) == nil)
    }

    @Test func colourComponentsAreClamped() {
        let color = ThemeColor(red: 2, green: -1, blue: 0.5)
        #expect(color == ThemeColor(red: 1, green: 0, blue: 0.5))
    }
}
