import Foundation
import Testing
@testable import PenumbraCore

@Suite struct PresetStoreTests {
    let store = PresetStore(rootDirectory: FileManager.default.temporaryDirectory.appending(path: "penumbra-tests-\(UUID())"))

    @Test func missingFileLoadsAnEmptyLibrary() throws {
        #expect(try store.load() == PresetLibrary())
    }

    @Test func libraryRoundTrips() throws {
        var library = PresetLibrary()
        let preset = Preset(name: "A", kind: .auto(
            light: ThemeVariant(accent: .blue, highlight: ThemeColor(red: 1, green: 0.5, blue: 0)),
            dark: ThemeVariant(wallpaper: .init(imageName: "d.png"), accent: .graphite)))
        library.presets = [preset]
        library.activePresetID = preset.id
        library.lastAppliedAppearance = .dark

        try store.save(library)
        #expect(try store.load() == library)
    }

    @Test func newerSchemaIsRefusedAndLeftUntouched() throws {
        try FileManager.default.createDirectory(at: store.rootDirectory, withIntermediateDirectories: true)
        let contents = Data(#"{"schemaVersion":99,"presets":[]}"#.utf8)
        try contents.write(to: store.libraryURL)

        #expect(throws: PresetStoreError.unsupportedSchema(99)) { try store.load() }
        #expect(try Data(contentsOf: store.libraryURL) == contents)
    }

    @Test func corruptFileThrowsRatherThanLoadingEmpty() throws {
        try FileManager.default.createDirectory(at: store.rootDirectory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.libraryURL)
        #expect(throws: (any Error).self) { try store.load() }
    }

    @Test func importingAnImageAlreadyInTheStoreReusesIt() throws {
        try FileManager.default.createDirectory(at: store.wallpaperDirectory, withIntermediateDirectories: true)
        let existing = store.wallpaperURL(named: "abc.png")
        try Data("image".utf8).write(to: existing)

        #expect(try store.importWallpaper(from: existing).imageName == "abc.png")
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.wallpaperDirectory.path) == ["abc.png"])
    }

    @Test func importCopiesTheWallpaperIntoTheStore() throws {
        let source = FileManager.default.temporaryDirectory.appending(path: "penumbra-source-\(UUID()).PNG")
        try Data("image".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let spec = try store.importWallpaper(from: source)
        #expect(spec.imageName.hasSuffix(".png"))
        #expect(try Data(contentsOf: store.wallpaperURL(named: spec.imageName)) == Data("image".utf8))
    }
}
