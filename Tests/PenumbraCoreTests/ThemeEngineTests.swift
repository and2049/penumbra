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
    var restoreError: (any Error)?
    var restored: [SystemSnapshot] = []
    var snapshot = SystemSnapshot(switchesAutomatically: false, appearance: .light, accent: .blue, wallpaperURL: URL(fileURLWithPath: "/tmp/start.png"))

    func captureSnapshot() -> SystemSnapshot { snapshot }
    func restore(_ snapshot: SystemSnapshot) async throws {
        if let restoreError { throw restoreError }
        restored.append(snapshot)
    }

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

    @Test func undoRestoresTheSnapshotFromBeforeApply() async throws {
        let engine = try makeEngine(with: fixedPreset)
        let before = system.snapshot
        await engine.apply(presetID: fixedPreset.id)
        #expect(engine.library.undo?.presetName == "Fixed")

        let report = await engine.undo()

        #expect(report.succeeded)
        #expect(system.restored == [before])
        #expect(engine.library.undo == nil)
        #expect(engine.library.activePresetID == nil)
    }

    @Test func undoGoesBackToThePreviousPreset() async throws {
        let engine = try makeEngine(with: autoPreset, fixedPreset)
        await engine.apply(presetID: autoPreset.id)
        await engine.apply(presetID: fixedPreset.id)

        await engine.undo()

        #expect(engine.library.activePresetID == autoPreset.id)
    }

    @Test func undoSurvivesARelaunch() async throws {
        let engine = try makeEngine(with: fixedPreset)
        await engine.apply(presetID: fixedPreset.id)

        let relaunched = try ThemeEngine(system: system, store: store)
        await relaunched.undo()

        #expect(system.restored.count == 1)
    }

    @Test func failedUndoIsKeptForAnotherTry() async throws {
        let engine = try makeEngine(with: fixedPreset)
        await engine.apply(presetID: fixedPreset.id)
        system.restoreError = TestFailure()

        let report = await engine.undo()

        #expect(report.failures[.restoring] != nil)
        #expect(engine.library.undo != nil)
        #expect(engine.library.activePresetID == fixedPreset.id)
    }

    @Test func undoWithNothingToUndoChangesNothing() async throws {
        let engine = try makeEngine()
        await engine.undo()
        #expect(system.restored.isEmpty)
    }

    @Test func saveCurrentCopiesTheWallpaperAndBecomesActive() throws {
        let image = FileManager.default.temporaryDirectory.appending(path: "penumbra-\(UUID()).png")
        try Data("image".utf8).write(to: image)
        defer { try? FileManager.default.removeItem(at: image) }
        system.snapshot = SystemSnapshot(switchesAutomatically: false, appearance: .dark, accent: .green, wallpaperURL: image)
        let engine = try makeEngine()

        let result = try engine.saveCurrent(name: "Mine")

        guard case .fixed(let appearance, let variant) = result.preset.kind else {
            Issue.record("expected a fixed preset")
            return
        }
        #expect(appearance == .dark)
        #expect(variant.accent == .green)
        #expect(result.wallpaperProblem == nil)
        #expect(try Data(contentsOf: store.wallpaperURL(named: variant.wallpaper!.imageName)) == Data("image".utf8))
        #expect(engine.library.activePresetID == result.preset.id)
    }

    @Test func saveCurrentWithAutoOnMakesAnAutoPreset() throws {
        system.snapshot = SystemSnapshot(switchesAutomatically: true, appearance: .light, accent: .red)
        let engine = try makeEngine()

        let preset = try engine.saveCurrent(name: "Mine").preset

        #expect(preset.appearanceMode == .automatic)
        #expect(preset.variant(for: .dark).accent == .red)
    }

    @Test func saveCurrentStillSavesWhenTheWallpaperCantBeCopied() throws {
        system.snapshot = SystemSnapshot(switchesAutomatically: false, appearance: .light, accent: .red, wallpaperURL: URL(fileURLWithPath: "/nonexistent/x.png"))
        let engine = try makeEngine()

        let result = try engine.saveCurrent(name: "Mine")

        #expect(result.wallpaperProblem != nil)
        #expect(result.preset.variant(for: .light).wallpaper == nil)
    }

    @Test func duplicateNamesAreRefusedIgnoringCase() throws {
        let engine = try makeEngine(with: fixedPreset)
        let clash = Preset(name: "fixed", kind: fixedPreset.kind)

        #expect(throws: ThemeEngineError.duplicateName("fixed")) { try engine.save(preset: clash) }
        #expect(throws: ThemeEngineError.duplicateName("FIXED")) { try engine.saveCurrent(name: "FIXED") }
        #expect(engine.library.presets.count == 1)
    }

    @Test func savingAPresetUnderItsOwnNameIsAllowed() throws {
        let engine = try makeEngine(with: fixedPreset)
        var edited = fixedPreset
        edited.kind = autoPreset.kind
        try engine.save(preset: edited)
        #expect(engine.library.presets == [edited])
    }

    @Test func movingReordersAndSurvivesReload() throws {
        let third = Preset(name: "Third", kind: fixedPreset.kind)
        let engine = try makeEngine(with: autoPreset, fixedPreset, third)

        try engine.move(presetID: autoPreset.id, to: 2)
        #expect(engine.library.presets == [fixedPreset, third, autoPreset])

        try engine.move(presetID: third.id, to: -5)
        #expect(engine.library.presets == [third, fixedPreset, autoPreset])

        try engine.move(presetID: third.id, to: 99)
        try engine.reload()
        #expect(engine.library.presets == [fixedPreset, autoPreset, third])
    }

    @Test func deletingTheActivePresetClearsIt() async throws {
        let engine = try makeEngine(with: fixedPreset)
        await engine.apply(presetID: fixedPreset.id)

        try engine.delete(presetID: fixedPreset.id)

        #expect(engine.library.presets.isEmpty)
        #expect(engine.library.activePresetID == nil)
    }

    @Test func deletingRemovesFilesNothingUses() throws {
        let engine = try makeEngine()
        try FileManager.default.createDirectory(at: store.wallpaperDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: store.generatedDirectory, withIntermediateDirectories: true)
        for name in ["kept.png", "unused.png", "shown.png"] {
            try Data(name.utf8).write(to: store.wallpaperURL(named: name))
        }
        try Data().write(to: store.generatedDirectory.appending(path: "old-pair.heic"))
        system.snapshot.wallpaperURL = store.wallpaperURL(named: "shown.png")

        let keeper = Preset(name: "K", kind: .fixed(appearance: .light, variant: ThemeVariant(wallpaper: .init(imageName: "kept.png"))))
        let doomed = Preset(name: "D", kind: .fixed(appearance: .light, variant: ThemeVariant(wallpaper: .init(imageName: "unused.png"))))
        try engine.save(preset: keeper)
        try engine.save(preset: doomed)
        try engine.delete(presetID: doomed.id)

        let left = try FileManager.default.contentsOfDirectory(atPath: store.wallpaperDirectory.path).sorted()
        #expect(left == ["kept.png", "shown.png"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.generatedDirectory.path).isEmpty)
    }

    @Test func generatedWallpaperForAnAutoPresetIsKept() throws {
        let engine = try makeEngine()
        try FileManager.default.createDirectory(at: store.generatedDirectory, withIntermediateDirectories: true)
        try Data().write(to: store.generatedDirectory.appending(path: "l-d.heic"))

        try engine.save(preset: autoPreset)

        #expect(try FileManager.default.contentsOfDirectory(atPath: store.generatedDirectory.path) == ["l-d.heic"])
    }

    @Test func modifiedComparesAgainstTheActivePreset() async throws {
        let engine = try makeEngine(with: fixedPreset)
        #expect(!engine.activePresetIsModified())

        await engine.apply(presetID: fixedPreset.id)
        let image = store.wallpaperURL(named: "d.png")
        system.snapshot = SystemSnapshot(switchesAutomatically: false, appearance: .dark, accent: .red, wallpaperURL: image)
        #expect(!engine.activePresetIsModified())

        system.snapshot.accent = .green
        #expect(engine.activePresetIsModified())
        system.snapshot.accent = .red

        system.snapshot.switchesAutomatically = true
        #expect(engine.activePresetIsModified())
        system.snapshot.switchesAutomatically = false

        system.snapshot.wallpaperURL = URL(fileURLWithPath: "/tmp/other.png")
        #expect(engine.activePresetIsModified())
        system.snapshot.wallpaperURL = image

        system.snapshot.highlight = ThemeColor(red: 1, green: 0, blue: 0)
        #expect(engine.activePresetIsModified())
    }

    @Test func savedCopyOfTheWallpaperStillMatchesTheOriginal() throws {
        let image = FileManager.default.temporaryDirectory.appending(path: "penumbra-\(UUID()).png")
        try Data("image".utf8).write(to: image)
        defer { try? FileManager.default.removeItem(at: image) }
        system.snapshot = SystemSnapshot(switchesAutomatically: false, appearance: .light, accent: .blue, wallpaperURL: image)
        let engine = try makeEngine()

        _ = try engine.saveCurrent(name: "Mine")
        #expect(!engine.activePresetIsModified())

        try Data("changed".utf8).write(to: image)
        #expect(engine.activePresetIsModified())
    }

    @Test func modifiedRecognisesTheGeneratedAdaptiveWallpaper() async throws {
        let engine = try makeEngine(with: autoPreset)
        await engine.apply(presetID: autoPreset.id)
        system.snapshot = SystemSnapshot(switchesAutomatically: true, appearance: .light, accent: .blue,
                                         wallpaperURL: URL(fileURLWithPath: "/any/Generated/l-d.heic"))
        #expect(!engine.activePresetIsModified())
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
