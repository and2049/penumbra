import Foundation
import Observation
import PenumbraCore
import PenumbraSystem

@MainActor
@Observable
final class AppModel {
    private(set) var appearance: Appearance
    private(set) var presets: [Preset] = []
    private(set) var activePresetID: Preset.ID?
    private(set) var isActivePresetModified = false
    private(set) var undoPresetName: String?
    private(set) var nightShift: NightShiftStatus?
    private(set) var isBusy = false
    /// The outcome of the last action, when there's something to say.
    private(set) var message: String?
    /// Set when saved presets can't be read. Penumbra then changes nothing.
    private(set) var loadError: String?

    private let system: any ThemeSystem
    private let nightShiftClient = NightShiftClient()
    private var engine: ThemeEngine?
    private var lastOperation: Task<Void, Never>?

    init(system: any ThemeSystem, store: PresetStore) {
        self.system = system
        appearance = system.currentAppearance
        do {
            engine = try ThemeEngine(system: system, store: store)
        } catch {
            loadError = String(describing: error)
        }
        refresh()
    }

    func refresh() {
        appearance = system.currentAppearance
        nightShift = nightShiftClient?.status()
        guard let engine else { return }
        presets = engine.library.presets
        activePresetID = engine.library.activePresetID
        undoPresetName = engine.library.undo?.presetName
        isActivePresetModified = engine.activePresetIsModified()
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
                self.message = "Couldn't reload presets: \(error)"
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
                    self.message = "Saved without the wallpaper: \(problem)"
                }
            } catch {
                self.message = "Couldn't save the preset: \(error)"
            }
        }
    }

    func delete(_ preset: Preset) {
        message = nil
        enqueue { engine in
            do {
                try engine.delete(presetID: preset.id)
            } catch {
                self.message = "Couldn't delete the preset: \(error)"
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
        let details = report.failures.map { "\($0.key.rawValue): \($0.value)" }.sorted().joined(separator: "\n")
        message = "Some changes failed.\n\(details)"
    }
}
