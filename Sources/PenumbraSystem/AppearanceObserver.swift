import AppKit

/// Posted by `penumbractl` after it changes saved presets, so a running app reloads them.
public enum PenumbraNotifications {
    public static let libraryChanged = Notification.Name("io.github.and2049.penumbra.libraryChanged")

    public static func postLibraryChanged() {
        DistributedNotificationCenter.default().postNotificationName(
            libraryChanged, object: nil, userInfo: nil, deliverImmediately: true)
    }
}

/// Reports when the appearance may have changed. Needs a running AppKit event loop.
///
/// The distributed notification must use `.deliverImmediately`, because AppKit otherwise holds
/// these back while an app is inactive, and a menu bar app almost always is.
@MainActor
public final class AppearanceObserver: NSObject {
    private let onChange: @MainActor () -> Void
    private var appearanceObservation: NSKeyValueObservation?

    public init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    public func start() {
        guard appearanceObservation == nil else { return }

        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.onChange() }
        }
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(changed),
            name: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        // Catches anything missed while asleep or locked.
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(changed), name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(changed), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
    }

    @objc private func changed() {
        onChange()
    }
}
