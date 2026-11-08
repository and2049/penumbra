import AppKit
import Foundation
import PenumbraCore
import PenumbraSystem

let usage = """
usage: penumbractl <command>

  list                                          Show presets
  status                                        Show the current system state
  apply <name>                                  Apply a preset
  undo                                          Undo the last apply
  save-current <name>                           Save the current state as a preset
  add-fixed <name> <light|dark> <accent> [image]
  add-auto <name> <light-accent> <dark-accent> [light-image dark-image]
  delete <name>
  schedule [off | sun | HH:MM-HH:MM]            Show or set the Night Shift schedule
  login-item [on | off]                         Show or set opening the app at login

accents: \(AccentColor.allCases.map(\.rawValue).joined(separator: " "))
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func accent(_ text: String) -> AccentColor {
    guard let accent = AccentColor(rawValue: text) else { fail("unknown accent: \(text)") }
    return accent
}

// The desktop APIs used by the system module need an app object.
_ = NSApplication.shared

let store = PresetStore(rootDirectory: LiveThemeSystem.defaultSupportDirectory)
let system = LiveThemeSystem(supportDirectory: LiveThemeSystem.defaultSupportDirectory)

@MainActor func preset(named name: String, in engine: ThemeEngine) -> Preset {
    guard let preset = engine.library.presets.first(where: { $0.name == name }) else { fail("no preset named \(name)") }
    return preset
}

func finish(_ report: ApplyReport) -> Never {
    PenumbraNotifications.postLibraryChanged()
    for (step, reason) in report.failures { print("failed \(step.rawValue): \(reason)") }
    exit(report.succeeded ? 0 : 1)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { fail(usage) }
let parameters = Array(arguments.dropFirst())

do {
    let engine = try ThemeEngine(system: system, store: store)
    switch (command, parameters.count) {
    case ("list", 0):
        for preset in engine.library.presets {
            let active = preset.id == engine.library.activePresetID
            let kind: String
            switch preset.kind {
            case .fixed(let appearance, let variant): kind = "\(appearance.rawValue), \(variant.accent.rawValue)"
            case .auto(let light, let dark): kind = "auto, \(light.accent.rawValue)/\(dark.accent.rawValue)"
            }
            print("\(active ? "*" : " ") \(preset.name) (\(kind))")
        }
    case ("status", 0):
        let snapshot = system.captureSnapshot()
        print("appearance: \(snapshot.appearance.rawValue)\(snapshot.switchesAutomatically ? " (auto)" : "")")
        print("accent: \(snapshot.accent.rawValue)")
        print("wallpaper: \(snapshot.wallpaperURL?.path ?? "unknown")")
        print("active: \(engine.library.activePreset?.name ?? "none")\(engine.activePresetIsModified() ? " (modified)" : "")")
        print("undo: \(engine.library.undo?.presetName ?? "none")")
    case ("apply", 1):
        finish(await engine.apply(presetID: preset(named: parameters[0], in: engine).id))
    case ("undo", 0):
        guard engine.library.undo != nil else { fail("nothing to undo") }
        finish(await engine.undo())
    case ("save-current", 1):
        let result = try engine.saveCurrent(name: parameters[0])
        if let problem = result.wallpaperProblem { print("saved without wallpaper: \(problem)") }
        PenumbraNotifications.postLibraryChanged()
    case ("add-fixed", 3), ("add-fixed", 4):
        guard let appearance = Appearance(rawValue: parameters[1]) else { fail("expected light or dark") }
        let wallpaper = try parameters.count == 4 ? store.importWallpaper(from: URL(fileURLWithPath: parameters[3])) : nil
        try engine.save(preset: Preset(name: parameters[0], kind: .fixed(
            appearance: appearance,
            variant: ThemeVariant(wallpaper: wallpaper, accent: accent(parameters[2])))))
        PenumbraNotifications.postLibraryChanged()
    case ("add-auto", 3), ("add-auto", 5):
        let images = try parameters.count == 5
            ? (store.importWallpaper(from: URL(fileURLWithPath: parameters[3])), store.importWallpaper(from: URL(fileURLWithPath: parameters[4])))
            : nil
        try engine.save(preset: Preset(name: parameters[0], kind: .auto(
            light: ThemeVariant(wallpaper: images?.0, accent: accent(parameters[1])),
            dark: ThemeVariant(wallpaper: images?.1, accent: accent(parameters[2])))))
        PenumbraNotifications.postLibraryChanged()
    case ("schedule", 0):
        guard let status = NightShiftClient()?.status() else { fail("Night Shift is unavailable") }
        switch status.mode {
        case .off: print("off")
        case .sunsetToSunrise: print("sun")
        case .custom: print("\(status.from.text)-\(status.to.text)")
        }
        if !status.isSunSchedulePermitted { print("sunset to sunrise needs location access") }
    case ("schedule", 1):
        guard let client = NightShiftClient() else { fail("Night Shift is unavailable") }
        switch parameters[0] {
        case "off": client.setMode(.off)
        case "sun": client.setMode(.sunsetToSunrise)
        default:
            let times = parameters[0].split(separator: "-").compactMap { NightShiftStatus.Time(String($0)) }
            guard times.count == 2 else { fail("expected HH:MM-HH:MM") }
            client.setSchedule(from: times[0], to: times[1])
            client.setMode(.custom)
        }
    case ("login-item", 0):
        print(LoginItem.state)
    case ("login-item", 1):
        guard ["on", "off"].contains(parameters[0]) else { fail("expected on or off") }
        try LoginItem.setEnabled(parameters[0] == "on")
        print(LoginItem.state)
    case ("delete", 1):
        try engine.delete(presetID: preset(named: parameters[0], in: engine).id)
        PenumbraNotifications.postLibraryChanged()
    default:
        fail(usage)
    }
} catch {
    fail("error: \(error.localizedDescription)")
}
