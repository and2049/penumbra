import AppKit
import SwiftUI

/// Shows one preset editor at a time.
@MainActor
final class EditorWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(_ draft: PresetDraft, model: AppModel) {
        window?.close()

        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        // Each action closes the window it belongs to. A save can finish after another
        // editor has opened, and must not close that one.
        let view = PresetEditorView(
            draft: draft,
            save: { [weak window] in
                model.save(draft) { saved in if saved { window?.close() } }
            },
            cancel: { [weak window] in window?.close() },
            delete: { [weak window] in
                model.deletePreset(id: draft.id)
                window?.close()
            })

        // A hosting view, unlike a hosting controller, resizes the window when switching
        // between one and two columns.
        window.contentView = NSHostingView(rootView: view)
        window.title = draft.isNew ? "New Preset" : "Edit \(draft.name)"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window

        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === window { window = nil }
    }
}
