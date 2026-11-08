import AppKit
import PenumbraCore
import PenumbraSystem
import SwiftUI

/// View-local state. SwiftUI's `@State` is a macro whose plugin only ships with Xcode, so
/// this uses Observation instead, which works with just the Command Line Tools.
@MainActor
@Observable
final class PanelState {
    var isNaming = false
    var newName = ""
    var presetToDelete: Preset?
    var hoveredPresetID: Preset.ID?
}

struct MenuBarPanel: View {
    let model: AppModel
    let state: PanelState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            status

            if let error = model.loadError {
                notice("Couldn't read saved presets, so Penumbra won't change anything: \(error)")
            }
            if let message = model.message {
                notice(message)
            }

            Divider()
            presetList
            Divider()
            actions
        }
        .padding(14)
        .frame(width: 300)
        .confirmationDialog(
            "Delete \(state.presetToDelete?.name ?? "preset")?",
            isPresented: Binding(get: { state.presetToDelete != nil }, set: { if !$0 { state.presetToDelete = nil } })
        ) {
            Button("Delete", role: .destructive) {
                if let preset = state.presetToDelete { model.delete(preset) }
            }
        } message: {
            Text("Your current settings and wallpaper won't change.")
        }
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Penumbra").font(.headline)
            row("Appearance", model.appearance == .dark ? "Dark" : "Light")
            row("Night Shift", nightShiftText)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.callout)
    }

    private func notice(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    @ViewBuilder
    private var presetList: some View {
        if model.presets.isEmpty {
            Text("No presets yet. Save your current look to create one.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(spacing: 2) {
                ForEach(model.presets) { preset in
                    PresetRow(
                        preset: preset,
                        isActive: preset.id == model.activePresetID,
                        isModified: preset.id == model.activePresetID && model.isActivePresetModified,
                        isHovered: state.hoveredPresetID == preset.id,
                        appearance: model.appearance,
                        apply: { model.apply(preset) },
                        hover: { state.hoveredPresetID = $0 ? preset.id : nil },
                        delete: { state.presetToDelete = preset })
                }
            }
            .disabled(model.isBusy)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if state.isNaming {
            HStack {
                TextField("Preset name", text: Binding(get: { state.newName }, set: { state.newName = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                Button("Save", action: save)
                    .disabled(trimmedName.isEmpty)
                Button("Cancel") { state.isNaming = false }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Button("Save Current Look…") {
                    state.newName = ""
                    state.isNaming = true
                }
                if let name = model.undoPresetName {
                    Button("Undo “\(name)”") { model.undo() }
                }
                Button("Quit Penumbra") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .buttonStyle(.plain)
            .font(.callout)
            .disabled(model.isBusy)
        }
    }

    private var trimmedName: String {
        state.newName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        model.saveCurrent(name: trimmedName)
        state.isNaming = false
    }

    private var nightShiftText: String {
        guard let status = model.nightShift else { return "Unavailable" }
        switch status.mode {
        case .off:
            return "Off"
        case .sunsetToSunrise:
            return "Sunset to sunrise"
        case .custom:
            return "\(format(status.from)) to \(format(status.to))"
        }
    }

    private func format(_ time: NightShiftStatus.Time) -> String {
        String(format: "%02d:%02d", time.hour, time.minute)
    }
}

private struct PresetRow: View {
    let preset: Preset
    let isActive: Bool
    let isModified: Bool
    let isHovered: Bool
    let appearance: Appearance
    let apply: () -> Void
    let hover: (Bool) -> Void
    let delete: () -> Void

    var body: some View {
        Button(action: apply) {
            HStack(spacing: 8) {
                Image(systemName: kindSymbol)
                    .frame(width: 16)
                    .foregroundStyle(.secondary)
                Circle()
                    .fill(preset.variant(for: appearance).accent.swatch)
                    .frame(width: 10, height: 10)
                Text(preset.name)
                    .lineLimit(1)
                Spacer()
                if isModified {
                    Text("Modified")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if isActive {
                    Image(systemName: "checkmark")
                        .accessibilityLabel("Active")
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(.rect)
            .background(isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover(perform: hover)
        .help(isModified ? "Changed since it was applied. Click to apply it again." : "Apply \(preset.name)")
        .contextMenu {
            Button("Delete…", role: .destructive, action: delete)
        }
    }

    private var kindSymbol: String {
        switch preset.kind {
        case .fixed(.light, _): "sun.max"
        case .fixed(.dark, _): "moon"
        case .auto: "circle.lefthalf.filled"
        }
    }
}

private extension AccentColor {
    var swatch: AnyShapeStyle {
        switch self {
        case .multicolor: AnyShapeStyle(AngularGradient(colors: [.red, .yellow, .green, .blue, .purple, .red], center: .center))
        case .graphite: AnyShapeStyle(Color.gray)
        case .red: AnyShapeStyle(Color.red)
        case .orange: AnyShapeStyle(Color.orange)
        case .yellow: AnyShapeStyle(Color.yellow)
        case .green: AnyShapeStyle(Color.green)
        case .blue: AnyShapeStyle(Color.blue)
        case .purple: AnyShapeStyle(Color.purple)
        case .pink: AnyShapeStyle(Color.pink)
        }
    }
}
