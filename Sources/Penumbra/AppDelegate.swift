import AppKit
import PenumbraCore
import PenumbraSystem

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var observer: AppearanceObserver?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let support = URL.applicationSupportDirectory.appending(path: "Penumbra", directoryHint: .isDirectory)
        let system = LiveThemeSystem(supportDirectory: support)
        let store = PresetStore(rootDirectory: support)
        let model = AppModel(system: system, store: store)
        menuBar = MenuBarController(model: model)

        let observer = AppearanceObserver { model.appearanceMayHaveChanged() }
        observer.start()
        self.observer = observer
        model.appearanceMayHaveChanged()
    }

    /// Opening the app again while it's running shows the panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        menuBar?.showPopover()
        return false
    }
}
