import Foundation
import Testing
@testable import PenumbraSystem

/// Builds a store with the shape seen on macOS 27.2.
func makeStoreData(url: String = "file:///old.png", spaces: [String: Any] = [:], displays: [String: Any] = [:], type: String = "linked", provider: String = "com.apple.wallpaper.choice.image") throws -> Data {
    func section() throws -> [String: Any] {
        let configuration = try PropertyListSerialization.data(
            fromPropertyList: ["type": "imageFile", "url": ["relative": url]], format: .binary, options: 0)
        return [
            "Type": type,
            "Linked": [
                "LastSet": Date(timeIntervalSince1970: 1000),
                "Content": [
                    "Choices": [["Provider": provider, "Files": [String](), "Configuration": configuration]],
                    "Shuffle": "$null",
                    "EncodedOptionValues": Data([1, 2, 3]),
                ] as [String: Any],
            ] as [String: Any],
        ]
    }
    let store: [String: Any] = ["AllSpacesAndDisplays": try section(), "SystemDefault": try section(), "Spaces": spaces, "Displays": displays]
    return try PropertyListSerialization.data(fromPropertyList: store, format: .binary, options: 0)
}

@Suite struct WallpaperStoreEditorTests {
    let newURL = URL(fileURLWithPath: "/tmp/new image.heic")

    @Test func readsTheLinkedImage() throws {
        #expect(try WallpaperStoreEditor.imageURL(in: makeStoreData()) == URL(string: "file:///old.png"))
    }

    @Test func replacesTheImageAndStaysLinked() throws {
        let edited = try WallpaperStoreEditor.settingImage(newURL, in: makeStoreData())
        #expect(try WallpaperStoreEditor.imageURL(in: edited) == newURL)

        let store = try #require(PropertyListSerialization.propertyList(from: edited, format: nil) as? [String: Any])
        let section = try #require(store["AllSpacesAndDisplays"] as? [String: Any])
        #expect(section["Type"] as? String == "linked")
    }

    @Test func updatesSystemDefaultToo() throws {
        let edited = try WallpaperStoreEditor.settingImage(newURL, in: makeStoreData())
        let store = try #require(PropertyListSerialization.propertyList(from: edited, format: nil) as? [String: Any])
        let fallback = try #require(store["SystemDefault"] as? [String: Any])
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["AllSpacesAndDisplays": fallback, "Spaces": [String: Any](), "Displays": [String: Any]()],
            format: .binary, options: 0)
        #expect(try WallpaperStoreEditor.imageURL(in: data) == newURL)
    }

    @Test func keepsOtherFieldsIntact() throws {
        let edited = try WallpaperStoreEditor.settingImage(newURL, in: makeStoreData())
        let store = try #require(PropertyListSerialization.propertyList(from: edited, format: nil) as? [String: Any])
        let section = try #require(store["AllSpacesAndDisplays"] as? [String: Any])
        let linked = try #require(section["Linked"] as? [String: Any])
        let content = try #require(linked["Content"] as? [String: Any])
        #expect(linked["LastSet"] as? Date == Date(timeIntervalSince1970: 1000))
        #expect(content["EncodedOptionValues"] as? Data == Data([1, 2, 3]))
        #expect(content["Shuffle"] as? String == "$null")
    }

    @Test func rejectsPerSpaceEntries() throws {
        let data = try makeStoreData(spaces: ["abc": ["Default": "x"]])
        #expect(throws: WallpaperStoreEditor.EditError.self) { try WallpaperStoreEditor.settingImage(newURL, in: data) }
    }

    @Test func rejectsPerDisplayEntries() throws {
        let data = try makeStoreData(displays: ["abc": ["Type": "x"]])
        #expect(throws: WallpaperStoreEditor.EditError.self) { try WallpaperStoreEditor.settingImage(newURL, in: data) }
    }

    @Test func rejectsNonLinkedStores() throws {
        let data = try makeStoreData(type: "individual")
        #expect(throws: WallpaperStoreEditor.EditError.self) { try WallpaperStoreEditor.settingImage(newURL, in: data) }
    }

    @Test func rejectsVideoAndOtherProviders() throws {
        let data = try makeStoreData(provider: "com.apple.wallpaper.choice.aerials")
        #expect(throws: WallpaperStoreEditor.EditError.self) { try WallpaperStoreEditor.settingImage(newURL, in: data) }
    }

    @Test func rejectsGarbage() {
        #expect(throws: (any Error).self) { try WallpaperStoreEditor.settingImage(newURL, in: Data("nope".utf8)) }
    }
}
