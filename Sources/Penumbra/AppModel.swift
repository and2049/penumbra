import Foundation
import Observation
import PenumbraCore
import PenumbraSystem

@MainActor
@Observable
final class AppModel {
    private(set) var appearance: Appearance
    private(set) var switchesAutomatically = false
    private(set) var presets: [Preset] = []
    private(set) var activePresetID: Preset.ID?
    private(set) var isActivePresetModified = false
    private(set) var undoPresetName: String?
    private(set) var nightShift: NightShiftStatus?
    private(set) var loginItem: LoginItem.State = .disabled
    private(set) var isBusy = false
    /// The outcome of the last action, when there's something to say.
    private(set) var message: String?
    /// Set when saved presets can't be read. Penumbra then changes nothing.
    private(set) var loadError: String?

    /// Set by the menu bar controller, which owns the editor window.
    var showEditor: ((PresetDraft) -> Void)?

    private let system: any ThemeSystem
    private let store: PresetStore
    private let nightShiftClient = NightShiftClient()
    private var engine: ThemeEngine?
    private var lastOperation: Task<Void, Never>?

    init(system: any ThemeSystem, store: PresetStore) {
        self.system = system
        self.store = store
        appearance = system.currentAppearance
        do {
            engine = try ThemeEngine(system: system, store: store)
        } catch {
            loadError = error.localizedDescription
        }
        refresh()
    }

    func refresh() {
        appearance = system.currentAppearance
        switchesAutomatically = system.captureSnapshot().switchesAutomatically
        nightShift = nightShiftClient?.status()
        loginItem = LoginItem.state
        guard let engine else { return }
        presets = engine.library.presets
        activePresetID = engine.library.activePresetID
        undoPresetName = engine.library.undo?.presetName
        isActivePresetModified = engine.activePresetIsModified()
    }

    var isAutoWithoutSchedule: Bool {
        guard let active = presets.first(where: { $0.id == activePresetID }), case .auto = active.kind else { return false }
        return nightShift?.mode == .off
    }

    /// The warning to show under a name field, or `nil` if the name can be used.
    func nameWarning(for name: String, excluding id: Preset.ID? = nil) -> String? {
        guard let engine, engine.library.isNameTaken(name, excluding: id) else { return nil }
        return "There's already a preset called “\(name.trimmingCharacters(in: .whitespacesAndNewlines))”."
    }

    func preset(named name: String) -> Preset? {
        presets.first { $0.name == name }
    }

    func newPreset() {
        showEditor?(PresetDraft(preset: nil, store: store))
    }

    func edit(_ preset: Preset) {
        showEditor?(PresetDraft(preset: preset, store: store))
    }

    /// Saves an edited preset, and applies it again if it's the active one.
    func save(_ draft: PresetDraft, completion: @escaping @MainActor (Bool) -> Void) {
        draft.error = nil
        draft.isSaving = true
        enqueue { engine in
            defer { draft.isSaving = false }
            do {
                let preset = try draft.preset(importingInto: self.store)
                try engine.save(preset: preset)
                if engine.library.activePresetID == preset.id {
                    self.show(await engine.apply(presetID: preset.id))
                }
                completion(true)
            } catch {
                draft.error = "Couldn't save the preset. \(error.localizedDescription)"
                completion(false)
            }
        }
    }

    func deletePreset(id: Preset.ID) {
        guard let preset = presets.first(where: { $0.id == id }) else { return }
        delete(preset)
    }

    func setNightShift(mode: NightShiftStatus.Mode, from: Date, to: Date) {
        guard let client = nightShiftClient else { return }
        if mode == .custom {
            client.setSchedule(from: NightShiftStatus.Time(from), to: NightShiftStatus.Time(to))
        }
        client.setMode(mode)
        refresh()
    }

    func setOpenAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
        } catch {
            message = "Couldn't change Open at Login. \(error.localizedDescription)"
        }
        refresh()
    }

    func appearanceMayHaveChanged() {
        enqueue { engine in
            if let report = await engine.reconcile() { self.show(report) }
        }
    }

    func libraryChangedElsewhere() {
        enqueue { engine in
            do {
                try engine.reload()
            } catch {
                self.message = "Couldn't reload presets. \(error.localizedDescription)"
            }
        }
    }

    func apply(_ preset: Preset) {
        message = nil
        enqueue { engine in self.show(await engine.apply(presetID: preset.id)) }
    }

    func undo() {
        message = nil
        enqueue { engine in self.show(await engine.undo()) }
    }

    func saveCurrent(name: String) {
        message = nil
        enqueue { engine in
            do {
                if let problem = try engine.saveCurrent(name: name).wallpaperProblem {
                    self.message = "Saved without the wallpaper. \(problem)"
                }
            } catch {
                self.message = "Couldn't save the preset. \(error.localizedDescription)"
            }
        }
    }

    func delete(_ preset: Preset) {
        message = nil
        enqueue { engine in
            do {
                try engine.delete(presetID: preset.id)
            } catch {
                self.message = "Couldn't delete the preset. \(error.localizedDescription)"
            }
        }
    }

    /// Runs one operation at a time, because wallpaper changes wait for the agent to restart
    /// and two running together could restore a stale copy of the store.
    private func enqueue(_ operation: @escaping @MainActor (ThemeEngine) async -> Void) {
        guard let engine else { return }
        let previous = lastOperation
        isBusy = true
        let task = Task {
            await previous?.value
            await operation(engine)
            self.refresh()
        }
        lastOperation = task
        Task {
            await task.value
            if self.lastOperation == task { self.isBusy = false }
        }
    }

    private func show(_ report: ApplyReport) {
        guard !report.succeeded else { return }
        message = report.failures.map { step, reason in
            let action = switch step {
            case .appearance: "Couldn't change light and dark mode."
            case .wallpaper: "Couldn't change the wallpaper."
            case .restoring: "Couldn't undo."
            case .saving: "Couldn't save your presets."
            }
            return "\(action) \(reason)"
        }
        .sorted()
        .joined(separator: "\n")
    }
}
