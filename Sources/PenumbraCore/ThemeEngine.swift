import Foundation

public enum ResolvedWallpaper: Sendable, Equatable {
    case still(URL)
    case adaptive(light: URL, dark: URL)

    /// Name of the HEIC generated for an adaptive pair. Imported names are unique and never
    /// change, so one file per pair is enough.
    public static func generatedFileName(light: URL, dark: URL) -> String {
        "\(light.deletingPathExtension().lastPathComponent)-\(dark.deletingPathExtension().lastPathComponent).heic"
    }
}

/// The system settings a preset controls. Setters should do nothing when the value already
/// matches, because changing some of them is visible or disruptive.
@MainActor
public protocol ThemeSystem: AnyObject {
    var currentAppearance: Appearance { get }
    func setAppearanceMode(_ mode: AppearanceMode) throws
    func setAccent(_ accent: AccentColor)
    func setHighlight(_ highlight: ThemeColor?)
    func setWallpaper(_ wallpaper: ResolvedWallpaper) async throws
    func captureSnapshot() -> SystemSnapshot
    func restore(_ snapshot: SystemSnapshot) async throws
}

public struct ApplyReport: Sendable {
    public enum Step: String, Sendable {
        case appearance, wallpaper, restoring, saving
    }

    public var failures: [Step: String] = [:]

    public init() {}

    public var succeeded: Bool { failures.isEmpty }
}

public enum ThemeEngineError: Error, Equatable, LocalizedError {
    case duplicateName(String)

    public var errorDescription: String? {
        switch self {
        case .duplicateName(let name): "There's already a preset called “\(name)”."
        }
    }
}

public struct SaveCurrentResult: Sendable {
    public var preset: Preset
    /// Why the wallpaper was left out, if it was.
    public var wallpaperProblem: String?
}

@MainActor
public final class ThemeEngine {
    public private(set) var library: PresetLibrary

    private let system: any ThemeSystem
    private let store: PresetStore

    public init(system: any ThemeSystem, store: PresetStore) throws {
        self.system = system
        self.store = store
        self.library = try store.load()
    }

    /// Picks up changes saved by another process.
    public func reload() throws {
        library = try store.load()
    }

    /// Applies a preset. A failed step is reported but doesn't stop the remaining steps.
    @discardableResult
    public func apply(presetID: Preset.ID) async -> ApplyReport {
        var report = ApplyReport()
        guard let preset = library.presets.first(where: { $0.id == presetID }) else { return report }

        library.undo = UndoRecord(
            snapshot: system.captureSnapshot(),
            presetName: preset.name,
            previousActivePresetID: library.activePresetID,
            previousLastAppliedAppearance: library.lastAppliedAppearance)

        do {
            try system.setAppearanceMode(preset.appearanceMode)
        } catch {
            report.failures[.appearance] = error.localizedDescription
        }

        let appearance = system.currentAppearance
        library.activePresetID = preset.id
        library.lastAppliedAppearance = appearance
        await applyVariant(of: preset, for: appearance, report: &report)
        save(&report)
        return report
    }

    /// Returns the system to how it was before the last apply. Undo is kept if this fails,
    /// so it can be tried again.
    @discardableResult
    public func undo() async -> ApplyReport {
        var report = ApplyReport()
        guard let record = library.undo else { return report }

        do {
            try await system.restore(record.snapshot)
            library.activePresetID = record.previousActivePresetID
            library.lastAppliedAppearance = record.previousLastAppliedAppearance
            library.undo = nil
        } catch {
            report.failures[.restoring] = error.localizedDescription
        }
        save(&report)
        return report
    }

    /// Call whenever the appearance may have changed, including at launch and after waking.
    /// Only auto presets respond. Anything else would undo changes made by hand in System Settings.
    @discardableResult
    public func reconcile() async -> ApplyReport? {
        guard let preset = library.activePreset, case .auto = preset.kind else { return nil }
        let appearance = system.currentAppearance
        guard appearance != library.lastAppliedAppearance else { return nil }

        var report = ApplyReport()
        library.lastAppliedAppearance = appearance
        await applyVariant(of: preset, for: appearance, report: &report)
        save(&report)
        return report
    }

    /// Saves the current system state as a new active preset. With Auto on, both modes start
    /// with the current look, since only one of them can be seen.
    public func saveCurrent(name: String) throws -> SaveCurrentResult {
        try checkNameIsFree(name, for: nil)
        let snapshot = system.captureSnapshot()

        var wallpaper: WallpaperSpec?
        var problem: String?
        if let url = snapshot.wallpaperURL {
            do {
                wallpaper = try store.importWallpaper(from: url)
            } catch {
                problem = error.localizedDescription
            }
        } else {
            problem = "macOS didn't report a wallpaper file"
        }

        let variant = ThemeVariant(wallpaper: wallpaper, accent: snapshot.accent, highlight: snapshot.highlight)
        let preset = Preset(name: name, kind: snapshot.switchesAutomatically
            ? .auto(light: variant, dark: variant)
            : .fixed(appearance: snapshot.appearance, variant: variant))

        library.presets.append(preset)
        library.activePresetID = preset.id
        library.lastAppliedAppearance = snapshot.appearance
        try store.save(library)
        return SaveCurrentResult(preset: preset, wallpaperProblem: problem)
    }

    /// Adds or replaces a preset by ID.
    public func save(preset: Preset) throws {
        try checkNameIsFree(preset.name, for: preset.id)
        if let index = library.presets.firstIndex(where: { $0.id == preset.id }) {
            library.presets[index] = preset
        } else {
            library.presets.append(preset)
        }
        try store.save(library)
        removeUnusedFiles()
    }

    /// Removes a preset. System settings stay as they are.
    public func delete(presetID: Preset.ID) throws {
        library.presets.removeAll { $0.id == presetID }
        if library.activePresetID == presetID {
            library.activePresetID = nil
            library.lastAppliedAppearance = nil
        }
        try store.save(library)
        removeUnusedFiles()
    }

    /// Names are how the command-line tool and URL scheme find presets, so they must be unique.
    private func checkNameIsFree(_ name: String, for id: Preset.ID?) throws {
        let taken = library.presets.contains {
            $0.id != id && $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        if taken { throw ThemeEngineError.duplicateName(name) }
    }

    /// Deletes copied and generated wallpapers that nothing uses any more. Files still shown
    /// as the wallpaper, or needed by undo, are kept even without a preset.
    func removeUnusedFiles() {
        var keep = Set([system.captureSnapshot().wallpaperURL, library.undo?.snapshot.wallpaperURL]
            .compactMap { $0?.lastPathComponent })
        for preset in library.presets {
            keep.formUnion(preset.variants.compactMap { $0.wallpaper?.imageName })
            if case .adaptive(let light, let dark)? = preset.wallpaperTarget(for: .light) {
                keep.insert(ResolvedWallpaper.generatedFileName(
                    light: store.wallpaperURL(named: light), dark: store.wallpaperURL(named: dark)))
            }
        }
        store.removeFiles(in: store.wallpaperDirectory, keeping: keep)
        store.removeFiles(in: store.generatedDirectory, keeping: keep)
    }

    /// Whether the system has drifted from the active preset, for example through System Settings.
    public func activePresetIsModified() -> Bool {
        guard let preset = library.activePreset else { return false }
        let snapshot = system.captureSnapshot()

        switch preset.appearanceMode {
        case .automatic:
            if !snapshot.switchesAutomatically { return true }
        case .fixed(let appearance):
            if snapshot.switchesAutomatically || snapshot.appearance != appearance { return true }
        }

        let variant = preset.variant(for: snapshot.appearance)
        if variant.accent != snapshot.accent { return true }
        switch (variant.highlight, snapshot.highlight) {
        case (nil, nil): break
        case (let expected?, let actual?) where expected.isClose(to: actual): break
        default: return true
        }

        guard let target = preset.wallpaperTarget(for: snapshot.appearance) else { return false }
        switch resolve(target) {
        case .still(let url):
            guard let current = snapshot.wallpaperURL else { return true }
            // Save Current copies the wallpaper, so the original file counts as a match too.
            return current.standardizedFileURL != url.standardizedFileURL
                && !FileManager.default.contentsEqual(atPath: current.path, andPath: url.path)
        case .adaptive(let light, let dark):
            return snapshot.wallpaperURL?.lastPathComponent != ResolvedWallpaper.generatedFileName(light: light, dark: dark)
        }
    }

    private func applyVariant(of preset: Preset, for appearance: Appearance, report: inout ApplyReport) async {
        let variant = preset.variant(for: appearance)
        system.setAccent(variant.accent)
        system.setHighlight(variant.highlight)

        guard let target = preset.wallpaperTarget(for: appearance) else { return }
        do {
            try await system.setWallpaper(resolve(target))
        } catch {
            report.failures[.wallpaper] = error.localizedDescription
        }
    }

    private func resolve(_ target: WallpaperTarget) -> ResolvedWallpaper {
        switch target {
        case .still(let name):
            .still(store.wallpaperURL(named: name))
        case .adaptive(let light, let dark):
            .adaptive(light: store.wallpaperURL(named: light), dark: store.wallpaperURL(named: dark))
        }
    }

    private func save(_ report: inout ApplyReport) {
        do {
            try store.save(library)
        } catch {
            report.failures[.saving] = error.localizedDescription
        }
    }
}
