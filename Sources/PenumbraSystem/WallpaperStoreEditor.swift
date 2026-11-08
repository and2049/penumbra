import Foundation

/// Edits the macOS wallpaper store (`Index.plist`). Its format is private, so anything that
/// doesn't match the shape checked on macOS 27.2 is rejected and the caller falls back.
///
/// This is used because `NSWorkspace.setDesktopImageURL` splits a linked "all Spaces and
/// displays" store into per-display and per-Space entries, and can't undo that.
enum WallpaperStoreEditor {
    enum EditError: Error, Equatable {
        case unsupportedShape(String)
    }

    private static let imageProvider = "com.apple.wallpaper.choice.image"

    /// The image a linked store points at.
    static func imageURL(in data: Data) throws -> URL {
        let store = try decode(data)
        let linked = try linkedSection(of: store)
        let configuration = try imageConfiguration(in: linked)
        guard let url = configuration.url else { throw EditError.unsupportedShape("no image URL") }
        return url
    }

    /// Returns the store with the linked image replaced, leaving everything else as it was.
    static func settingImage(_ url: URL, in data: Data) throws -> Data {
        var store = try decode(data)
        store["AllSpacesAndDisplays"] = try replacingImage(in: linkedSection(of: store), with: url)

        // The fallback for new Spaces and displays. Keep it in step when it has the same shape.
        if let fallback = store["SystemDefault"] as? [String: Any],
           let updated = try? replacingImage(in: fallback, with: url) {
            store["SystemDefault"] = updated
        }
        return try PropertyListSerialization.data(fromPropertyList: store, format: .binary, options: 0)
    }

    private static func decode(_ data: Data) throws -> [String: Any] {
        guard let store = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw EditError.unsupportedShape("root isn't a dictionary")
        }
        return store
    }

    private static func linkedSection(of store: [String: Any]) throws -> [String: Any] {
        // Per-display or per-Space entries would override the linked one.
        guard (store["Spaces"] as? [String: Any])?.isEmpty == true,
              (store["Displays"] as? [String: Any])?.isEmpty == true else {
            throw EditError.unsupportedShape("store has per-display or per-Space entries")
        }
        guard let section = store["AllSpacesAndDisplays"] as? [String: Any] else {
            throw EditError.unsupportedShape("missing AllSpacesAndDisplays")
        }
        return section
    }

    private static func imageConfiguration(in section: [String: Any]) throws -> (url: URL?, choice: [String: Any], configuration: [String: Any]) {
        guard section["Type"] as? String == "linked",
              let linked = section["Linked"] as? [String: Any],
              let content = linked["Content"] as? [String: Any],
              let choices = content["Choices"] as? [[String: Any]],
              choices.count == 1,
              choices[0]["Provider"] as? String == imageProvider,
              let encoded = choices[0]["Configuration"] as? Data,
              let configuration = try PropertyListSerialization.propertyList(from: encoded, format: nil) as? [String: Any],
              let urlEntry = configuration["url"] as? [String: Any],
              let relative = urlEntry["relative"] as? String
        else {
            throw EditError.unsupportedShape("linked section isn't a single image")
        }
        return (URL(string: relative), choices[0], configuration)
    }

    private static func replacingImage(in section: [String: Any], with url: URL) throws -> [String: Any] {
        var (_, choice, configuration) = try imageConfiguration(in: section)
        var urlEntry = configuration["url"] as? [String: Any] ?? [:]
        urlEntry["relative"] = url.absoluteString
        configuration["url"] = urlEntry
        choice["Configuration"] = try PropertyListSerialization.data(fromPropertyList: configuration, format: .binary, options: 0)

        var updated = section
        var linked = section["Linked"] as? [String: Any] ?? [:]
        var content = linked["Content"] as? [String: Any] ?? [:]
        content["Choices"] = [choice]
        linked["Content"] = content
        updated["Linked"] = linked
        return updated
    }
}
