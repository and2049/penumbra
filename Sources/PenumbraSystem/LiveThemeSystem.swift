import AppKit
import PenumbraCore

public enum ThemeSystemError: Error {
    case appearanceControlUnavailable
}

/// The real `ThemeSystem`, which changes settings on this Mac.
@MainActor
public final class LiveThemeSystem: ThemeSystem {
    private let skyLight = SkyLightAppearance()
    private let wallpaperApplier: WallpaperApplier
    private let generatedDirectory: URL

    /// - Parameter supportDirectory: Where generated wallpapers and the store backup are kept.
    public init(supportDirectory: URL) {
        generatedDirectory = supportDirectory.appending(path: "Generated", directoryHint: .isDirectory)
        wallpaperApplier = WallpaperApplier(environment: .init(
            storeURL: FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library/Application Support/com.apple.wallpaper/Store/Index.plist"),
            backupURL: supportDirectory.appending(path: "Backups/Index.plist"),
            restartAgent: {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
                process.arguments = ["WallpaperAgent"]
                try? process.run()
                process.waitUntilExit()
            },
            currentImageURL: {
                NSScreen.main.flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }
            },
            setWithPublicAPI: { url in
                for screen in NSScreen.screens {
                    try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
                }
            }
        ))
    }

    /// The location Penumbra keeps its data, shared by the app and the command-line tool.
    public static var defaultSupportDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Penumbra", directoryHint: .isDirectory)
    }

    /// Asks SkyLight first, because `effectiveAppearance` lags behind a change just made.
    public var currentAppearance: Appearance {
        if let skyLight { return skyLight.isDark ? .dark : .light }
        return NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }

    public func setAppearanceMode(_ mode: AppearanceMode) throws {
        guard let skyLight else { throw ThemeSystemError.appearanceControlUnavailable }
        switch mode {
        case .automatic:
            if !skyLight.switchesAutomatically { skyLight.switchesAutomatically = true }
        case .fixed(let appearance):
            if skyLight.switchesAutomatically { skyLight.switchesAutomatically = false }
            let dark = appearance == .dark
            if skyLight.isDark != dark { skyLight.isDark = dark }
        }
    }

    public func setAccent(_ accent: AccentColor) {
        AccentPreferences.setAccent(accent)
    }

    public func setHighlight(_ highlight: ThemeColor?) {
        AccentPreferences.setHighlight(highlight)
    }

    public func setWallpaper(_ wallpaper: ResolvedWallpaper) async throws {
        switch wallpaper {
        case .still(let url):
            try await wallpaperApplier.apply(url)
        case .adaptive(let light, let dark):
            let output = generatedDirectory.appending(path: ResolvedWallpaper.generatedFileName(light: light, dark: dark))
            if !FileManager.default.fileExists(atPath: output.path) {
                try await Task.detached(priority: .userInitiated) {
                    try AdaptiveWallpaperBuilder.build(light: light, dark: dark, output: output)
                }.value
            }
            try await wallpaperApplier.apply(output)
        }
    }

    public func captureSnapshot() -> SystemSnapshot {
        let accentValue = AccentPreferences.accentValue
        let highlightValue = AccentPreferences.highlightValue
        return SystemSnapshot(
            switchesAutomatically: skyLight?.switchesAutomatically ?? false,
            appearance: currentAppearance,
            accent: AccentColor(preferenceValue: accentValue),
            highlight: highlightValue.flatMap { ThemeColor(preferenceString: $0) },
            wallpaperURL: NSScreen.main.flatMap { NSWorkspace.shared.desktopImageURL(for: $0) },
            accentPreference: accentValue,
            aquaVariantPreference: AccentPreferences.aquaVariantValue,
            highlightPreference: highlightValue,
            wallpaperStore: wallpaperApplier.currentStore)
    }

    public func restore(_ snapshot: SystemSnapshot) async throws {
        AccentPreferences.restore(
            accent: snapshot.accentPreference,
            aquaVariant: snapshot.aquaVariantPreference,
            highlight: snapshot.highlightPreference)

        guard let skyLight else { throw ThemeSystemError.appearanceControlUnavailable }
        // Auto goes last, so it can take over from the restored appearance.
        skyLight.switchesAutomatically = false
        skyLight.isDark = snapshot.appearance == .dark
        skyLight.switchesAutomatically = snapshot.switchesAutomatically

        if let store = snapshot.wallpaperStore {
            try await wallpaperApplier.restoreStore(store, expecting: snapshot.wallpaperURL)
        } else if let url = snapshot.wallpaperURL {
            try await wallpaperApplier.apply(url)
        }
    }
}
