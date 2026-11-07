import Foundation
import Testing
@testable import PenumbraCore

@MainActor
final class FakeSystem: ThemeSystem {
    var currentAppearance: Appearance = .light
    var modes: [AppearanceMode] = []
    var accents: [AccentColor] = []
    var highlights: [ThemeColor?] = []
    var wallpapers: [ResolvedWallpaper] = []
    var appearanceError: (any Error)?
    var wallpaperError: (any Error)?

    func setAppearanceMode(_ mode: AppearanceMode) throws {
        if let appearanceError { throw appearanceError }
        modes.append(mode)
        if case .fixed(let appearance) = mode { currentAppearance = appearance }
    }
    func setAccent(_ accent: AccentColor) { accents.append(accent) }
    func setHighlight(_ highlight: ThemeColor?) { highlights.append(highlight) }
    func setWallpaper(_ wallpaper: ResolvedWallpaper) async throws {
        if let wallpaperError { throw wallpaperError }
        wallpapers.append(wallpaper)
    }
}

struct TestFailure: Error {}

@MainActor
@Suite struct ThemeEngineTests {
    let store = PresetStore(rootDirectory: FileManager.default.temporaryDirectory.appending(path: "penumbra-tests-\(UUID())"))
    let system = FakeSystem()

    let autoPreset = Preset(name: "Auto", kind: .auto(
        light: ThemeVariant(wallpaper: .init(imageName: "l.png"), accent: .blue),
        dark: ThemeVariant(wallpaper: .init(imageName: "d.png"), accent: .purple)))
    let fixedPreset = Preset(name: "Fixed", kind: .fixed(
        appearance: .dark,
        variant: ThemeVariant(wallpaper: .init(imageName: "d.png"), accent: .red)))

    func makeEngine(with presets: Preset...) throws -> ThemeEngine {
        let engine = try ThemeEngine(system: system, store: store)
        for preset in presets { try engine.save(preset: preset) }
        return engine
    }

    @Test func applyingFixedPresetSetsEverything() async throws {
        let engine = try makeEngine(with: fixedPreset)
        let report = await engine.apply(presetID: fixedPreset.id)

        #expect(report.succeeded)
        #expect(system.modes == [.fixed(.dark)])
        #expect(system.accents == [.red])
        #expect(system.wallpapers == [.still(store.wallpaperURL(named: "d.png"))])
        #expect(engine.library.activePresetID == fixedPreset.id)
    }

    @Test func applyingAutoPresetUsesTheCurrentAppearance() async throws {
        system.currentAppearance = .dark
        let engine = try makeEngine(with: autoPreset)
        await engine.apply(presetID: autoPreset.id)

        #expect(system.modes == [.automatic])
        #expect(system.accents == [.purple])
        #expect(system.wallpapers == [.adaptive(light: store.wallpaperURL(named: "l.png"), dark: store.wallpaperURL(named: "d.png"))])
    }

    @Test func applySurvivesReloadAsTheActivePreset() async throws {
        let engine = try makeEngine(with: autoPreset)
        await engine.apply(presetID: autoPreset.id)

        let reloaded = try ThemeEngine(system: system, store: store)
        #expect(reloaded.library.activePreset == autoPreset)
        #expect(reloaded.library.lastAppliedAppearance == .light)
    }

    @Test func failedStepIsReportedAndOtherStepsStillRun() async throws {
        system.appearanceError = TestFailure()
        system.wallpaperError = TestFailure()
        let engine = try makeEngine(with: fixedPreset)
        let report = await engine.apply(presetID: fixedPreset.id)

        #expect(report.failures[.appearance] != nil)
        #expect(report.failures[.wallpaper] != nil)
        #expect(system.accents == [.red])
    }

    @Test func applyingUnknownPresetChangesNothing() async throws {
        let engine = try makeEngine()
        await engine.apply(presetID: UUID())
        #expect(system.modes.isEmpty && system.accents.isEmpty)
    }

    @Test func reconcileFollowsAnAppearanceChange() async throws {
        let engine = try makeEngine(with: autoPreset)
        await engine.apply(presetID: autoPreset.id)

        system.currentAppearance = .dark
        let report = await engine.reconcile()

        #expect(report?.succeeded == true)
        #expect(system.accents == [.blue, .purple])
        #expect(engine.library.lastAppliedAppearance == .dark)
    }

    @Test func reconcileDoesNothingWithoutAChange() async throws {
        let engine = try makeEngine(with: autoPreset)
        await engine.apply(presetID: autoPreset.id)

        #expect(await engine.reconcile() == nil)
        #expect(system.accents == [.blue])
    }

    @Test func reconcileLeavesFixedPresetsAlone() async throws {
        let engine = try makeEngine(with: fixedPreset)
        await engine.apply(presetID: fixedPreset.id)

        system.currentAppearance = .light
        #expect(await engine.reconcile() == nil)
        #expect(system.accents == [.red])
    }

    @Test func reconcileCatchesUpAfterASwitchWhileNotRunning() async throws {
        let first = try makeEngine(with: autoPreset)
        await first.apply(presetID: autoPreset.id)

        system.currentAppearance = .dark
        let relaunched = try ThemeEngine(system: system, store: store)
        await relaunched.reconcile()

        #expect(system.accents.last == .purple)
    }
}
