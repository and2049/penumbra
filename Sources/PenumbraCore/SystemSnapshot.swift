import Foundation

/// The theme-related state of the system at one moment.
public struct SystemSnapshot: Codable, Sendable, Equatable {
    public var switchesAutomatically: Bool
    public var appearance: Appearance
    public var accent: AccentColor
    public var highlight: ThemeColor?
    public var wallpaperURL: URL?

    // Exact stored values, so undo can put back things a preset can't express.
    public var accentPreference: Int?
    public var aquaVariantPreference: Int?
    public var highlightPreference: String?
    public var wallpaperStore: Data?

    public init(
        switchesAutomatically: Bool,
        appearance: Appearance,
        accent: AccentColor,
        highlight: ThemeColor? = nil,
        wallpaperURL: URL? = nil,
        accentPreference: Int? = nil,
        aquaVariantPreference: Int? = nil,
        highlightPreference: String? = nil,
        wallpaperStore: Data? = nil
    ) {
        self.switchesAutomatically = switchesAutomatically
        self.appearance = appearance
        self.accent = accent
        self.highlight = highlight
        self.wallpaperURL = wallpaperURL
        self.accentPreference = accentPreference
        self.aquaVariantPreference = aquaVariantPreference
        self.highlightPreference = highlightPreference
        self.wallpaperStore = wallpaperStore
    }
}

public struct UndoRecord: Codable, Sendable, Equatable {
    public var snapshot: SystemSnapshot
    /// The preset that was applied, for labelling the undo action.
    public var presetName: String
    public var previousActivePresetID: UUID?
    public var previousLastAppliedAppearance: Appearance?
}
