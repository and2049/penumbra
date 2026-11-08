import Foundation
import PenumbraCore

extension AccentColor {
    /// `AppleAccentColor`. Multicolor is stored by removing the key.
    var preferenceValue: Int? {
        switch self {
        case .multicolor: nil
        case .graphite: -1
        case .red: 0
        case .orange: 1
        case .yellow: 2
        case .green: 3
        case .blue: 4
        case .purple: 5
        case .pink: 6
        }
    }

    /// `AppleAquaColorVariant`, which is only set for graphite.
    var aquaVariant: Int? {
        self == .graphite ? 6 : nil
    }
}

extension ThemeColor {
    /// `AppleHighlightColor` format.
    var preferenceString: String {
        String(format: "%.6f %.6f %.6f Other", red, green, blue)
    }
}

/// Reads and writes the global colour preferences, and tells running apps when they change.
enum AccentPreferences {
    private static let accentKey = "AppleAccentColor"
    private static let aquaKey = "AppleAquaColorVariant"
    private static let highlightKey = "AppleHighlightColor"

    /// Returns without notifying anything if the accent already matches.
    static func setAccent(_ accent: AccentColor) {
        let accentChanged = write(accent.preferenceValue.map { NSNumber(value: $0) }, forKey: accentKey)
        let aquaChanged = write(accent.aquaVariant.map { NSNumber(value: $0) }, forKey: aquaKey)
        if accentChanged || aquaChanged { notify() }
    }

    static func setHighlight(_ highlight: ThemeColor?) {
        if write(highlight.map { $0.preferenceString as CFString }, forKey: highlightKey) { notify() }
    }

    /// Returns whether the stored value changed.
    private static func write(_ value: CFPropertyList?, forKey key: String) -> Bool {
        let cfKey = key as CFString
        let current = CFPreferencesCopyValue(cfKey, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        switch (current, value) {
        case (nil, nil):
            return false
        case (let current?, let value?) where CFEqual(current, value):
            return false
        default:
            CFPreferencesSetValue(cfKey, value, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            return true
        }
    }

    private static func notify() {
        for name in ["AppleColorPreferencesChangedNotification", "AppleAquaColorVariantChanged"] {
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name(name), object: nil, userInfo: nil, deliverImmediately: true)
        }
    }
}
