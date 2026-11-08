import Foundation

/// Sets the wallpaper by editing the store, checks it took effect, and falls back to the
/// public API if the store can't be used.
@MainActor
public final class WallpaperApplier {
    public struct Environment {
        public var storeURL: URL
        public var backupURL: URL
        public var restartAgent: @MainActor () -> Void
        /// The wallpaper macOS reports for the main display.
        public var currentImageURL: @MainActor () -> URL?
        public var setWithPublicAPI: @MainActor (URL) throws -> Void
        public var checkAttempts = 20
        public var checkInterval: Duration = .milliseconds(250)

        public init(
            storeURL: URL,
            backupURL: URL,
            restartAgent: @escaping @MainActor () -> Void,
            currentImageURL: @escaping @MainActor () -> URL?,
            setWithPublicAPI: @escaping @MainActor (URL) throws -> Void
        ) {
            self.storeURL = storeURL
            self.backupURL = backupURL
            self.restartAgent = restartAgent
            self.currentImageURL = currentImageURL
            self.setWithPublicAPI = setWithPublicAPI
        }
    }

    private let environment: Environment

    public init(environment: Environment) {
        self.environment = environment
    }

    public func apply(_ url: URL) async throws {
        let original: Data
        let edited: Data?
        do {
            original = try Data(contentsOf: environment.storeURL)
            edited = try edit(original, url: url)
        } catch {
            try environment.setWithPublicAPI(url)
            return
        }
        // Already set, so skip the restart.
        guard let edited else { return }

        try backUpOnce(original)
        try edited.write(to: environment.storeURL, options: .atomic)
        environment.restartAgent()
        if await tookEffect(url) { return }

        try original.write(to: environment.storeURL, options: .atomic)
        environment.restartAgent()
        try environment.setWithPublicAPI(url)
    }

    /// Returns `nil` when the store already points at this image.
    private func edit(_ data: Data, url: URL) throws -> Data? {
        if try WallpaperStoreEditor.imageURL(in: data).standardizedFileURL == url.standardizedFileURL {
            return nil
        }
        return try WallpaperStoreEditor.settingImage(url, in: data)
    }

    /// Keeps the store as it was before Penumbra's first write. Later writes never replace it.
    private func backUpOnce(_ data: Data) throws {
        guard !FileManager.default.fileExists(atPath: environment.backupURL.path) else { return }
        try FileManager.default.createDirectory(at: environment.backupURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: environment.backupURL, options: .atomic)
    }

    private func tookEffect(_ url: URL) async -> Bool {
        for _ in 0..<environment.checkAttempts {
            if environment.currentImageURL()?.standardizedFileURL == url.standardizedFileURL { return true }
            try? await Task.sleep(for: environment.checkInterval)
        }
        return false
    }
}
