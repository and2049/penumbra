import AppKit
import PenumbraCore
import SwiftUI
import UniformTypeIdentifiers

struct PresetEditorView: View {
    let draft: PresetDraft
    let save: () -> Void
    let cancel: () -> Void
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Name")
                TextField("Preset name", text: Binding(get: { draft.name }, set: { draft.name = $0 }))
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Picker("Appearance", selection: Binding(get: { draft.kind }, set: { draft.kind = $0 })) {
                    ForEach(PresetDraft.Kind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if draft.kind == .auto {
                    Text("Switches between light and dark on your Night Shift schedule.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .top, spacing: 20) {
                if draft.kind != .dark {
                    VariantEditor(title: draft.kind == .auto ? "Light" : nil, variant: draft.light)
                }
                if draft.kind != .light {
                    VariantEditor(title: draft.kind == .auto ? "Dark" : nil, variant: draft.dark)
                }
            }

            if let error = draft.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            HStack {
                if !draft.isNew {
                    Button("Delete…", role: .destructive) { draft.isConfirmingDelete = true }
                }
                Spacer()
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.trimmedName.isEmpty || draft.isSaving)
            }
        }
        .padding(20)
        .frame(width: draft.kind == .auto ? 620 : 320)
        .fixedSize(horizontal: false, vertical: true)
        .confirmationDialog(
            "Delete \(draft.name)?",
            isPresented: Binding(get: { draft.isConfirmingDelete }, set: { draft.isConfirmingDelete = $0 })
        ) {
            Button("Delete", role: .destructive, action: delete)
        } message: {
            Text("Your current settings and wallpaper won't change.")
        }
    }
}

private struct VariantEditor: View {
    let title: String?
    let variant: VariantDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title).font(.headline)
            }

            wallpaper

            VStack(alignment: .leading, spacing: 6) {
                Text("Accent colour").font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(AccentColor.allCases, id: \.self) { accent in
                        Button { variant.accent = accent } label: {
                            Circle()
                                .fill(accent.swatch)
                                .frame(width: 18, height: 18)
                                .padding(3)
                                .overlay(Circle().strokeBorder(.primary, lineWidth: variant.accent == accent ? 2 : 0))
                        }
                        .buttonStyle(.plain)
                        .help(accent.title)
                        .accessibilityLabel(accent.title)
                        .accessibilityAddTraits(variant.accent == accent ? .isSelected : [])
                    }
                }
            }

            HStack {
                Toggle("Custom highlight colour", isOn: Binding(
                    get: { variant.usesCustomHighlight }, set: { variant.usesCustomHighlight = $0 }))
                if variant.usesCustomHighlight {
                    ColorPicker("Highlight colour", selection: Binding(
                        get: { variant.highlight }, set: { variant.highlight = $0 }), supportsOpacity: false)
                        .labelsHidden()
                }
            }
            .font(.callout)
        }
        .frame(width: 280, alignment: .leading)
    }

    private var wallpaper: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
                .aspectRatio(16 / 10, contentMode: .fit)
                .overlay {
                    if let thumbnail = variant.thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Text(variant.hasWallpaper ? "No preview" : "Wallpaper unchanged")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .clipShape(.rect(cornerRadius: 8))

            HStack {
                Button("Choose Image…", action: chooseImage)
                if variant.hasWallpaper {
                    Button("Remove") { variant.removeWallpaper() }
                }
            }
            .font(.callout)
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a wallpaper"
        if panel.runModal() == .OK, let url = panel.url {
            variant.pick(url)
        }
    }
}
