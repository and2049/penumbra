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

    /// Unknown values read as multicolor, the system default.
    init(preferenceValue: Int?) {
        self = Self.allCases.first { $0.preferenceValue == preferenceValue } ?? .multicolor
    }
}

extension ThemeColor {
    /// `AppleHighlightColor` format.
    var preferenceString: String {
        String(format: "%.6f %.6f %.6f Other", red, green, blue)
    }

    /// Reads custom values and named ones, such as `"0.968627 0.831373 1.000000 Purple"`.
    init?(preferenceString: String) {
        let parts = preferenceString.split(separator: " ").prefix(3).compactMap { Double($0) }
        guard parts.count == 3 else { return nil }
        self.init(red: parts[0], green: parts[1], blue: parts[2])
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

    static var accentValue: Int? { (read(accentKey) as? NSNumber)?.intValue }
    static var aquaVariantValue: Int? { (read(aquaKey) as? NSNumber)?.intValue }
    static var highlightValue: String? { read(highlightKey) as? String }

    /// Puts back exact stored values, including ones Penumbra wouldn't write itself.
    static func restore(accent: Int?, aquaVariant: Int?, highlight: String?) {
        let changes = [
            write(accent.map { NSNumber(value: $0) }, forKey: accentKey),
            write(aquaVariant.map { NSNumber(value: $0) }, forKey: aquaKey),
            write(highlight.map { $0 as CFString }, forKey: highlightKey),
        ]
        if changes.contains(true) { notify() }
    }

    private static func read(_ key: String) -> CFPropertyList? {
        // Another process may have changed it, and the local cache wouldn't know.
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return CFPreferencesCopyValue(key as CFString, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    /// Returns whether the stored value changed.
    private static func write(_ value: CFPropertyList?, forKey key: String) -> Bool {
        let cfKey = key as CFString
        let current = read(key)
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
