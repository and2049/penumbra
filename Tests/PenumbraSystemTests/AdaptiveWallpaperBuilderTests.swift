import AppKit
import Foundation
import ImageIO
import Testing
@testable import PenumbraSystem

@Suite struct AdaptiveWallpaperBuilderTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "penumbra-heic-\(UUID())")

    func writePNG(_ name: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let url = directory.appending(path: name)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
        return url
    }

    @Test func producesTwoImagesWithLightDarkMetadata() throws {
        let output = directory.appending(path: "Generated/out.heic")
        try AdaptiveWallpaperBuilder.build(light: writePNG("l.png"), dark: writePNG("d.png"), output: output)

        let source = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 2)

        let metadata = try #require(CGImageSourceCopyMetadataAtIndex(source, 0, nil))
        let tag = try #require(CGImageMetadataCopyTagWithPath(metadata, nil, "apple_desktop:apr" as CFString))
        let value = try #require(CGImageMetadataTagCopyValue(tag) as? String)
        let plist = try #require(Data(base64Encoded: value))
        let mapping = try #require(PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Int])
        #expect(mapping == ["l": 0, "d": 1])
    }

    @Test func unreadableInputThrowsAndLeavesNoOutput() throws {
        let output = directory.appending(path: "out.heic")
        let good = try writePNG("l.png")
        let bad = directory.appending(path: "missing.png")

        #expect(throws: AdaptiveWallpaperBuilder.BuildError.unreadableImage(bad)) {
            try AdaptiveWallpaperBuilder.build(light: good, dark: bad, output: output)
        }
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }
}
