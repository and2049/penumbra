import AppKit
import SwiftUI

/// Shows one preset editor at a time.
@MainActor
final class EditorWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(_ draft: PresetDraft, model: AppModel) {
        window?.close()

        let view = PresetEditorView(
            draft: draft,
            save: { [weak self] in
                model.save(draft) { saved in if saved { self?.window?.close() } }
            },
            cancel: { [weak self] in self?.window?.close() },
            delete: { [weak self] in
                model.deletePreset(id: draft.id)
                self?.window?.close()
            })

        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
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
        window = nil
    }
}
