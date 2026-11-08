import AppKit
import PenumbraCore
import PenumbraSystem
import SwiftUI

struct MenuBarPanel: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Penumbra").font(.headline)

            if let error = model.loadError {
                Label("Couldn't read saved presets: \(error)", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Appearance", value: model.appearance == .dark ? "Dark" : "Light")
            LabeledContent("Night Shift", value: nightShiftText)

            Divider()

            if model.presets.isEmpty {
                Text("No presets yet").foregroundStyle(.secondary)
            } else {
                ForEach(model.presets) { preset in
                    Text(preset.name)
                }
            }

            Divider()

            Button("Quit Penumbra") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding()
        .frame(width: 280)
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
