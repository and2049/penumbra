import AppKit
import ImageIO
import Observation
import PenumbraCore
import SwiftUI

/// One appearance of a preset being edited.
@MainActor
@Observable
final class VariantDraft {
    var accent: AccentColor
    var usesCustomHighlight: Bool
    var highlight: Color
    /// An image already in the preset store.
    var imageName: String?
    /// A newly chosen image, copied into the store on save.
    var pickedImage: URL?
    var thumbnail: NSImage?

    init(_ variant: ThemeVariant, store: PresetStore) {
        accent = variant.accent
        usesCustomHighlight = variant.highlight != nil
        highlight = variant.highlight.map(\.color) ?? .yellow
        imageName = variant.wallpaper?.imageName
        thumbnail = imageName.flatMap { Self.thumbnail(for: store.wallpaperURL(named: $0)) }
    }

    var hasWallpaper: Bool { imageName != nil || pickedImage != nil }

    func pick(_ url: URL) {
        pickedImage = url
        imageName = nil
        thumbnail = Self.thumbnail(for: url)
    }

    func removeWallpaper() {
        pickedImage = nil
        imageName = nil
        thumbnail = nil
    }

    func variant(importingInto store: PresetStore) throws -> ThemeVariant {
        var wallpaper = imageName.map(WallpaperSpec.init(imageName:))
        if let pickedImage {
            wallpaper = try store.importWallpaper(from: pickedImage)
        }
        return ThemeVariant(
            wallpaper: wallpaper,
            accent: accent,
            highlight: usesCustomHighlight ? ThemeColor(highlight) : nil)
    }

    /// A small copy, so large wallpapers don't slow the editor down.
    static func thumbnail(for url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 600,
              ] as CFDictionary)
        else { return nil }
        return NSImage(cgImage: image, size: .zero)
    }
}

@MainActor
@Observable
final class PresetDraft {
    enum Kind: String, CaseIterable {
        case light, dark, auto

        var title: String {
            switch self {
            case .light: "Light"
            case .dark: "Dark"
            case .auto: "Auto"
            }
        }
    }

    let id: UUID
    let isNew: Bool
    var name: String
    var kind: Kind
    /// Fixed light presets use `light`, and fixed dark presets use `dark`.
    let light: VariantDraft
    let dark: VariantDraft
    var error: String?
    var isConfirmingDelete = false
    var isSaving = false

    init(preset: Preset?, store: PresetStore) {
        id = preset?.id ?? UUID()
        isNew = preset == nil
        name = preset?.name ?? ""
        switch preset?.kind {
        case .fixed(let appearance, let variant)?:
            kind = appearance == .dark ? .dark : .light
            light = VariantDraft(variant, store: store)
            dark = VariantDraft(variant, store: store)
        case .auto(let lightVariant, let darkVariant)?:
            kind = .auto
            light = VariantDraft(lightVariant, store: store)
            dark = VariantDraft(darkVariant, store: store)
        case nil:
            kind = .auto
            light = VariantDraft(ThemeVariant(accent: .blue), store: store)
            dark = VariantDraft(ThemeVariant(accent: .purple), store: store)
        }
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    func preset(importingInto store: PresetStore) throws -> Preset {
        let kind: PresetKind = switch self.kind {
        case .light: .fixed(appearance: .light, variant: try light.variant(importingInto: store))
        case .dark: .fixed(appearance: .dark, variant: try dark.variant(importingInto: store))
        case .auto: .auto(light: try light.variant(importingInto: store), dark: try dark.variant(importingInto: store))
        }
        return Preset(id: id, name: trimmedName, kind: kind)
    }
}

extension ThemeColor {
    init(_ color: Color) {
        let srgb = NSColor(color).usingColorSpace(.sRGB) ?? .systemYellow
        self.init(red: Double(srgb.redComponent), green: Double(srgb.greenComponent), blue: Double(srgb.blueComponent))
    }

    var color: Color {
        Color(nsColor: NSColor(srgbRed: red, green: green, blue: blue, alpha: 1))
    }
}

extension AccentColor {
    var title: String { rawValue.capitalized }

    /// The colour macOS uses for each accent, measured from `controlAccentColor` on macOS 27.2.
    var displayColor: Color {
        let (red, green, blue): (Double, Double, Double) = switch self {
        case .multicolor, .blue: (0.000, 0.478, 1.000)
        case .graphite: (0.596, 0.596, 0.596)
        case .red: (0.878, 0.220, 0.243)
        case .orange: (0.969, 0.510, 0.106)
        case .yellow: (1.000, 0.780, 0.149)
        case .green: (0.384, 0.729, 0.275)
        case .purple: (0.584, 0.239, 0.588)
        case .pink: (0.969, 0.310, 0.620)
        }
        return Color(.sRGB, red: red, green: green, blue: blue)
    }

    var swatch: AnyShapeStyle {
        guard self == .multicolor else { return AnyShapeStyle(displayColor) }
        let wheel: [AccentColor] = [.red, .orange, .yellow, .green, .blue, .purple, .pink, .red]
        return AnyShapeStyle(AngularGradient(colors: wheel.map(\.displayColor), center: .center))
    }
}
