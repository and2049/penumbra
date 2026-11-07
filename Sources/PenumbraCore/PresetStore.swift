import Foundation

/// Everything Penumbra saves between launches.
public struct PresetLibrary: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion = PresetLibrary.currentSchemaVersion
    public var presets: [Preset] = []
    public var activePresetID: UUID?
    /// The appearance the active preset was last applied for, used to catch up after a
    /// switch that happened while Penumbra wasn't running.
    public var lastAppliedAppearance: Appearance?

    public init() {}

    public var activePreset: Preset? {
        presets.first { $0.id == activePresetID }
    }
}

public enum PresetStoreError: Error, Equatable {
    /// Saved by a newer build. Refusing to load it means it can't be overwritten by accident.
    case unsupportedSchema(Int)
}

public struct PresetStore: Sendable {
    public let rootDirectory: URL

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    public var libraryURL: URL { rootDirectory.appending(path: "presets.json") }
    public var wallpaperDirectory: URL { rootDirectory.appending(path: "Wallpapers", directoryHint: .isDirectory) }

    public func load() throws -> PresetLibrary {
        guard FileManager.default.fileExists(atPath: libraryURL.path) else { return PresetLibrary() }
        let library = try JSONDecoder().decode(PresetLibrary.self, from: Data(contentsOf: libraryURL))
        guard library.schemaVersion <= PresetLibrary.currentSchemaVersion else {
            throw PresetStoreError.unsupportedSchema(library.schemaVersion)
        }
        return library
    }

    public func save(_ library: PresetLibrary) throws {
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(library).write(to: libraryURL, options: .atomic)
    }

    /// Copies an image into the store so presets keep working if the original moves.
    public func importWallpaper(from source: URL) throws -> WallpaperSpec {
        try FileManager.default.createDirectory(at: wallpaperDirectory, withIntermediateDirectories: true)
        let name = UUID().uuidString + "." + source.pathExtension.lowercased()
        try FileManager.default.copyItem(at: source, to: wallpaperDirectory.appending(path: name))
        return WallpaperSpec(imageName: name)
    }

    public func wallpaperURL(named name: String) -> URL {
        wallpaperDirectory.appending(path: name)
    }
}
