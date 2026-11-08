import Foundation
import ImageIO

/// Combines two images into one HEIC that macOS swaps by itself when the appearance changes,
/// so the wallpaper still follows Auto when Penumbra isn't running.
public enum AdaptiveWallpaperBuilder {
    public enum BuildError: Error, Equatable {
        case unreadableImage(URL)
        case encodingFailed
    }

    /// Image indexes in the file. macOS reads these from the `apple_desktop:apr` metadata.
    static let lightIndex = 0
    static let darkIndex = 1
    static let namespace = "http://ns.apple.com/namespace/1.0/"
    static let prefix = "apple_desktop"

    public static func build(light: URL, dark: URL, output: URL) throws {
        let lightImage = try loadImage(light)
        let darkImage = try loadImage(dark)

        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Written next to the output and moved into place, so a failed build leaves nothing behind.
        let temporary = output.deletingLastPathComponent().appending(path: UUID().uuidString + ".heic")
        defer { try? FileManager.default.removeItem(at: temporary) }

        guard let destination = CGImageDestinationCreateWithURL(temporary as CFURL, "public.heic" as CFString, 2, nil) else {
            throw BuildError.encodingFailed
        }
        CGImageDestinationAddImageAndMetadata(destination, lightImage, try metadata(), nil)
        CGImageDestinationAddImage(destination, darkImage, nil)
        guard CGImageDestinationFinalize(destination) else { throw BuildError.encodingFailed }

        if FileManager.default.fileExists(atPath: output.path) {
            try FileManager.default.removeItem(at: output)
        }
        try FileManager.default.moveItem(at: temporary, to: output)
    }

    private static func loadImage(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw BuildError.unreadableImage(url)
        }
        return image
    }

    private static func metadata() throws -> CGImageMetadata {
        let mapping = try PropertyListSerialization.data(
            fromPropertyList: ["l": lightIndex, "d": darkIndex], format: .binary, options: 0)
        let metadata = CGImageMetadataCreateMutable()
        guard CGImageMetadataRegisterNamespaceForPrefix(metadata, namespace as CFString, prefix as CFString, nil),
              let tag = CGImageMetadataTagCreate(
                  namespace as CFString, prefix as CFString, "apr" as CFString, .string,
                  mapping.base64EncodedString() as CFString),
              CGImageMetadataSetTagWithPath(metadata, nil, "\(prefix):apr" as CFString, tag)
        else { throw BuildError.encodingFailed }
        return metadata
    }
}
