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
    var draggedPresetID: Preset.ID?
    var dragTranslation: CGFloat = 0
    var presetRowHeight: CGFloat = 0
    var isEditingSchedule = false
    var scheduleMode: NightShiftStatus.Mode = .custom
    var scheduleFrom = Date()
    var scheduleTo = Date()
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
            if model.isAutoWithoutSchedule {
                notice("The active preset is Auto, but the Night Shift schedule is off, so the appearance won't switch.")
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
            row("Appearance", (model.appearance == .dark ? "Dark" : "Light") + (model.switchesAutomatically ? ", Auto" : ""))
            if state.isEditingSchedule {
                scheduleEditor
            } else {
                HStack {
                    Text("Night Shift").foregroundStyle(.secondary)
                    Spacer()
                    Button(nightShiftText, action: beginEditingSchedule)
                        .buttonStyle(.link)
                        .disabled(model.nightShift == nil)
                        .help("Change the schedule that Auto follows")
                }
                .font(.callout)
            }
        }
    }

    private var scheduleEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Night Shift schedule").font(.callout).foregroundStyle(.secondary)
            Picker("Schedule", selection: Binding(get: { state.scheduleMode }, set: { state.scheduleMode = $0 })) {
                Text("Off").tag(NightShiftStatus.Mode.off)
                Text("Sun").tag(NightShiftStatus.Mode.sunsetToSunrise)
                Text("Custom").tag(NightShiftStatus.Mode.custom)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if state.scheduleMode == .sunsetToSunrise, model.nightShift?.isSunSchedulePermitted == false {
                Text("Sunset to sunrise needs Location Services.").font(.caption).foregroundStyle(.secondary)
            }
            if state.scheduleMode == .custom {
                timeRow("Dark from", Binding(get: { state.scheduleFrom }, set: { state.scheduleFrom = $0 }))
                timeRow("Light from", Binding(get: { state.scheduleTo }, set: { state.scheduleTo = $0 }))
            }

            HStack {
                Spacer()
                Button("Cancel") { state.isEditingSchedule = false }
                Button("Set") {
                    model.setNightShift(mode: state.scheduleMode, from: state.scheduleFrom, to: state.scheduleTo)
                    state.isEditingSchedule = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .font(.callout)
    }

    private func timeRow(_ label: String, _ time: Binding<Date>) -> some View {
        HStack {
            Text(label)
            Spacer()
            DatePicker(label, selection: time, displayedComponents: .hourAndMinute)
                .labelsHidden()
        }
    }

    private func beginEditingSchedule() {
        guard let status = model.nightShift else { return }
        state.scheduleMode = status.mode
        state.scheduleFrom = status.from.date
        state.scheduleTo = status.to.date
        state.isEditingSchedule = true
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
            let dragSource = dragSourceIndex
            let dragTarget = dragSource.map { dragTargetIndex(from: $0) }
            VStack(spacing: Self.presetRowSpacing) {
                ForEach(Array(model.presets.enumerated()), id: \.element.id) { index, preset in
                    let isDragged = index == dragSource
                    let shift = isDragged ? 0 : rowShift(at: index, source: dragSource, target: dragTarget)
                    PresetRow(
                        preset: preset,
                        isActive: preset.id == model.activePresetID,
                        isModified: preset.id == model.activePresetID && model.isActivePresetModified,
                        // Rows sliding under the pointer during a drag shouldn't light up.
                        isHovered: dragSource == nil ? state.hoveredPresetID == preset.id : isDragged,
                        canReorder: model.presets.count > 1,
                        appearance: model.appearance,
                        apply: { model.apply(preset) },
                        hover: { state.hoveredPresetID = $0 ? preset.id : nil },
                        edit: { model.edit(preset) },
                        delete: { state.presetToDelete = preset },
                        dragChanged: {
                            state.draggedPresetID = preset.id
                            state.dragTranslation = $0
                        },
                        dragEnded: { endDrag(of: preset, translation: $0) })
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { state.presetRowHeight = $0 }
                    .offset(y: shift)
                    .animation(isDragged ? nil : Self.reorderAnimation, value: shift)
                    .offset(y: isDragged ? draggedRowOffset(from: index) : 0)
                    .zIndex(isDragged ? 1 : 0)
                }
            }
            .disabled(model.isBusy || model.loadError != nil)
        }
    }

    private static let presetRowSpacing: CGFloat = 2
    private static let reorderAnimation = Animation.snappy(duration: 0.2)

    private var rowStride: CGFloat {
        max(state.presetRowHeight + Self.presetRowSpacing, 1)
    }

    /// Where the dragged preset started. A drag is dropped if the list goes busy under it.
    private var dragSourceIndex: Int? {
        guard !model.isBusy, let id = state.draggedPresetID else { return nil }
        return model.presets.firstIndex { $0.id == id }
    }

    private func dragTargetIndex(from source: Int, translation: CGFloat? = nil) -> Int {
        let steps = Int(((translation ?? state.dragTranslation) / rowStride).rounded())
        return min(max(source + steps, 0), model.presets.count - 1)
    }

    /// Keeps the dragged row inside the list.
    private func draggedRowOffset(from source: Int) -> CGFloat {
        let up = -CGFloat(source) * rowStride
        let down = CGFloat(model.presets.count - 1 - source) * rowStride
        return min(max(state.dragTranslation, up), down)
    }

    /// Rows between the dragged row's start and its target step aside to make room.
    private func rowShift(at index: Int, source: Int?, target: Int?) -> CGFloat {
        guard let source, let target else { return 0 }
        if source < index, index <= target { return -rowStride }
        if target <= index, index < source { return rowStride }
        return 0
    }

    private func endDrag(of preset: Preset, translation: CGFloat) {
        let source = model.presets.firstIndex { $0.id == preset.id }
        withAnimation(Self.reorderAnimation) {
            if let source, state.draggedPresetID == preset.id {
                model.move(preset, to: dragTargetIndex(from: source, translation: translation))
            }
            state.draggedPresetID = nil
            state.dragTranslation = 0
        }
    }

    @ViewBuilder
    private var actions: some View {
        if state.isNaming {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    TextField("Preset name", text: Binding(get: { state.newName }, set: { state.newName = $0 }))
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(save)
                    Button("Save", action: save)
                        .disabled(trimmedName.isEmpty || nameWarning != nil)
                    Button("Cancel") { state.isNaming = false }
                }
                if let nameWarning {
                    NameWarning(text: nameWarning)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Group {
                    Button("New Preset…") { model.newPreset() }
                    Button("Save Current Look…") {
                        state.newName = ""
                        state.isNaming = true
                    }
                    if let name = model.undoPresetName {
                        Button("Undo “\(name)”") { model.undo() }
                    }
                }
                .disabled(model.loadError != nil)
                Divider()
                Toggle("Open at Login", isOn: Binding(
                    get: { model.loginItem == .enabled }, set: { model.setOpenAtLogin($0) }))
                    .toggleStyle(.checkbox)
                if model.loginItem == .needsApproval {
                    Button("Allow in System Settings…") { LoginItem.openSystemSettings() }
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

    private var nameWarning: String? {
        trimmedName.isEmpty ? nil : model.nameWarning(for: trimmedName)
    }

    private func save() {
        guard !trimmedName.isEmpty, nameWarning == nil else { return }
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
            return "\(status.from.text) to \(status.to.text)"
        }
    }
}

extension NightShiftStatus.Time {
    var date: Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    init(_ date: Date) {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        self.init(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }
}

private struct PresetRow: View {
    let preset: Preset
    let isActive: Bool
    let isModified: Bool
    let isHovered: Bool
    let canReorder: Bool
    let appearance: Appearance
    let apply: () -> Void
    let hover: (Bool) -> Void
    let edit: () -> Void
    let delete: () -> Void
    let dragChanged: (CGFloat) -> Void
    let dragEnded: (CGFloat) -> Void

    var body: some View {
        HStack(spacing: 0) {
            applyButton
            if canReorder {
                dragHandle
            }
        }
        .background(isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 6))
        .onHover(perform: hover)
        .contextMenu {
            Button("Edit…", action: edit)
            Button("Delete…", role: .destructive, action: delete)
        }
    }

    /// Measured in global coordinates, because the row itself moves during the drag.
    private var dragHandle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 6)
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { dragChanged($0.translation.height) }
                    .onEnded { dragEnded($0.translation.height) })
            .help("Drag to reorder")
            .accessibilityLabel("Reorder")
    }

    private var applyButton: some View {
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
            .padding(.leading, 6)
            .padding(.trailing, canReorder ? 2 : 6)
            .padding(.vertical, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(isModified ? "Changed since it was applied. Click to apply it again." : "Apply \(preset.name)")
    }

    private var kindSymbol: String {
        switch preset.kind {
        case .fixed(.light, _): "sun.max"
        case .fixed(.dark, _): "moon"
        case .auto: "circle.lefthalf.filled"
        }
    }
}
