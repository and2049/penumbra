import Foundation

public enum Appearance: String, Codable, Sendable, CaseIterable {
    case light, dark
}

/// macOS only offers this fixed palette, so accent colours can't be arbitrary.
public enum AccentColor: String, Codable, Sendable, CaseIterable {
    case multicolor, graphite, red, orange, yellow, green, blue, purple, pink
}

public struct ThemeColor: Codable, Sendable, Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    /// Stored colours lose some precision, so exact comparison would report false changes.
    func isClose(to other: ThemeColor) -> Bool {
        abs(red - other.red) < 0.001 && abs(green - other.green) < 0.001 && abs(blue - other.blue) < 0.001
    }
}

public struct WallpaperSpec: Codable, Sendable, Equatable {
    /// File name inside the preset store's wallpaper folder.
    public var imageName: String

    public init(imageName: String) {
        self.imageName = imageName
    }
}

/// One complete look for a single appearance.
public struct ThemeVariant: Codable, Sendable, Equatable {
    /// `nil` leaves the current wallpaper alone.
    public var wallpaper: WallpaperSpec?
    public var accent: AccentColor
    /// `nil` means the highlight colour follows the accent colour.
    public var highlight: ThemeColor?

    public init(wallpaper: WallpaperSpec? = nil, accent: AccentColor = .multicolor, highlight: ThemeColor? = nil) {
        self.wallpaper = wallpaper
        self.accent = accent
        self.highlight = highlight
    }
}

public enum PresetKind: Codable, Sendable, Equatable {
    case fixed(appearance: Appearance, variant: ThemeVariant)
    /// Follows the macOS Auto appearance, which runs on the Night Shift schedule.
    case auto(light: ThemeVariant, dark: ThemeVariant)
}

public struct Preset: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var kind: PresetKind

    public init(id: UUID = UUID(), name: String, kind: PresetKind) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}

public enum AppearanceMode: Sendable, Equatable {
    case fixed(Appearance)
    case automatic
}

public enum WallpaperTarget: Sendable, Equatable {
    case still(imageName: String)
    /// A single image that macOS swaps by itself when the appearance changes.
    case adaptive(lightImageName: String, darkImageName: String)
}

extension Preset {
    public var appearanceMode: AppearanceMode {
        switch kind {
        case .fixed(let appearance, _): .fixed(appearance)
        case .auto: .automatic
        }
    }

    public func variant(for appearance: Appearance) -> ThemeVariant {
        switch kind {
        case .fixed(_, let variant): variant
        case .auto(let light, let dark): appearance == .dark ? dark : light
        }
    }

    /// An auto preset only becomes adaptive when both modes have a wallpaper. With just one,
    /// that image applies in its own mode and the other mode leaves the wallpaper alone.
    public func wallpaperTarget(for appearance: Appearance) -> WallpaperTarget? {
        if case .auto(let light, let dark) = kind,
           let lightImage = light.wallpaper?.imageName,
           let darkImage = dark.wallpaper?.imageName {
            return lightImage == darkImage
                ? .still(imageName: lightImage)
                : .adaptive(lightImageName: lightImage, darkImageName: darkImage)
        }
        return variant(for: appearance).wallpaper.map { .still(imageName: $0.imageName) }
    }
}
