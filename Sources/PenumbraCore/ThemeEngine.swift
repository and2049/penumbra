import Foundation

public enum ResolvedWallpaper: Sendable, Equatable {
    case still(URL)
    case adaptive(light: URL, dark: URL)
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
}

public struct ApplyReport: Sendable {
    public enum Step: String, Sendable {
        case appearance, wallpaper, saving
    }

    public var failures: [Step: String] = [:]

    public init() {}

    public var succeeded: Bool { failures.isEmpty }
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

    /// Applies a preset. A failed step is reported but doesn't stop the remaining steps.
    @discardableResult
    public func apply(presetID: Preset.ID) async -> ApplyReport {
        var report = ApplyReport()
        guard let preset = library.presets.first(where: { $0.id == presetID }) else { return report }

        do {
            try system.setAppearanceMode(preset.appearanceMode)
        } catch {
            report.failures[.appearance] = String(describing: error)
        }

        let appearance = system.currentAppearance
        library.activePresetID = preset.id
        library.lastAppliedAppearance = appearance
        await applyVariant(of: preset, for: appearance, report: &report)
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

    /// Adds or replaces a preset by ID.
    public func save(preset: Preset) throws {
        if let index = library.presets.firstIndex(where: { $0.id == preset.id }) {
            library.presets[index] = preset
        } else {
            library.presets.append(preset)
        }
        try store.save(library)
    }

    private func applyVariant(of preset: Preset, for appearance: Appearance, report: inout ApplyReport) async {
        let variant = preset.variant(for: appearance)
        system.setAccent(variant.accent)
        system.setHighlight(variant.highlight)

        guard let target = preset.wallpaperTarget(for: appearance) else { return }
        do {
            try await system.setWallpaper(resolve(target))
        } catch {
            report.failures[.wallpaper] = String(describing: error)
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
            report.failures[.saving] = String(describing: error)
        }
    }
}
