import AppKit
import PenumbraCore
import PenumbraSystem

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var observer: AppearanceObserver?
    private var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let support = LiveThemeSystem.defaultSupportDirectory
        let model = AppModel(
            system: LiveThemeSystem(supportDirectory: support),
            store: PresetStore(rootDirectory: support))
        self.model = model
        menuBar = MenuBarController(model: model)

        let observer = AppearanceObserver { model.appearanceMayHaveChanged() }
        observer.start()
        self.observer = observer

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(libraryChanged),
            name: PenumbraNotifications.libraryChanged,
            object: nil,
            suspensionBehavior: .deliverImmediately)

        // Catches a switch that happened while Penumbra wasn't running.
        model.appearanceMayHaveChanged()
    }

    /// Opening the app again while it's running shows the panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        menuBar?.showPopover()
        return false
    }

    @objc private func libraryChanged() {
        model?.libraryChangedElsewhere()
    }
}
