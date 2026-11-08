import Observation
import PenumbraCore
import PenumbraSystem

@MainActor
@Observable
final class AppModel {
    private(set) var appearance: Appearance
    private(set) var presets: [Preset] = []
    private(set) var nightShift: NightShiftStatus?
    /// Set when saved presets can't be read. Penumbra then changes nothing.
    private(set) var loadError: String?

    private let system: any ThemeSystem
    private let nightShiftClient = NightShiftClient()
    private var engine: ThemeEngine?

    init(system: any ThemeSystem, store: PresetStore) {
        self.system = system
        appearance = system.currentAppearance
        do {
            let engine = try ThemeEngine(system: system, store: store)
            self.engine = engine
            presets = engine.library.presets
        } catch {
            loadError = String(describing: error)
        }
        refresh()
    }

    func refresh() {
        appearance = system.currentAppearance
        nightShift = nightShiftClient?.status()
    }

    func appearanceMayHaveChanged() {
        refresh()
        Task { await engine?.reconcile() }
    }
}
