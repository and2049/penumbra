import AppKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private let model: AppModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let editor = EditorWindowController()

    init(model: AppModel) {
        self.model = model
        super.init()

        popover.behavior = .transient
        let host = NSHostingController(rootView: MenuBarPanel(model: model, state: PanelState()))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        model.showEditor = { [weak self] draft in
            guard let self else { return }
            popover.performClose(nil)
            editor.show(draft, model: model)
        }

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "circle.lefthalf.filled", accessibilityDescription: "Penumbra")
            button.target = self
            button.action = #selector(togglePopover)
        }
    }

    func showPopover() {
        guard let button = statusItem.button else { return }
        model.refresh()
        NSApp.activate()
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        popover.contentViewController?.view.window?.makeKey()
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }
}
