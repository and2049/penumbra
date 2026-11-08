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

    public var currentAppearance: Appearance {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
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
            // Imported names are unique and never change, so one build per pair is enough.
            let name = "\(light.deletingPathExtension().lastPathComponent)-\(dark.deletingPathExtension().lastPathComponent).heic"
            let output = generatedDirectory.appending(path: name)
            if !FileManager.default.fileExists(atPath: output.path) {
                try await Task.detached(priority: .userInitiated) {
                    try AdaptiveWallpaperBuilder.build(light: light, dark: dark, output: output)
                }.value
            }
            try await wallpaperApplier.apply(output)
        }
    }
}
