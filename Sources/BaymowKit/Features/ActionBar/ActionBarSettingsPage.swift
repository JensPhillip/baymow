import SwiftUI
import BaymowCore

/// Siden "Knapper" under Indstillinger (AP-77): knapper på skærmen til og fra, hvordan de ligger, og hvilke der er med.
struct ActionBarSettingsPage: View {
    @ObservedObject var controls: ActionBarSettings
    /// Funktionerne, der er slået til (kun de kan vælges som knapper).
    let available: Set<ActionBarButton>
    var openShortcuts: () -> Void = {}

    var body: some View {
        Section {
            OptionRow(symbol: "hand.tap.fill", color: .blue, title: "Knapper på skærmen",
                      subtitle: "Brug Baymow med musen i stedet for tasterne.",
                      help: "Et lille Baymow-logo på skærmen med knapper til det, du har slået til. Et tryk på en knap gør det samme som tasterne.",
                      isOn: $controls.isEnabled)
        }
        if controls.isEnabled {
            Section("Hvordan skal knapperne ligge?") {
                ForEach(ActionBarStyle.allCases) { style in styleRow(style) }
            }
            Section("Hvilke knapper?") {
                ForEach(ActionBarButton.allCases) { button in buttonRow(button) }
            }
        }
        Section {
            Toggle(isOn: Binding(get: { controls.keysActive }, set: { controls.keysEnabled = $0 })) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tasterne på tastaturet virker også")
                        Text(controls.isEnabled ? "Slå fra, hvis du kun vil bruge knapperne."
                                                : "Slå knapperne til, før tasterne kan slås fra.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                } icon: { Image(systemName: "keyboard") }
            }
            .disabled(!controls.isEnabled)
            Button { openShortcuts() } label: { Label("Se og skift tasterne", systemImage: "keyboard") }
        }
    }

    private func styleRow(_ style: ActionBarStyle) -> some View {
        Button { controls.style = style } label: {
            HStack(spacing: 12) {
                IconTile(symbol: style.symbol, color: controls.style == style ? .blue : .gray, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(style.title).font(.headline)
                        if style == .hover { Text("Standard").font(.caption).foregroundStyle(.secondary) }
                    }
                    Text(style.detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: controls.style == style ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(controls.style == style ? Color.accentColor : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(controls.style == style ? .isSelected : [])
    }

    @ViewBuilder private func buttonRow(_ button: ActionBarButton) -> some View {
        let isAvailable = available.contains(button)
        Toggle(isOn: Binding(get: { isAvailable && !controls.hiddenButtons.contains(button) },
                             set: { on in
                                 if on { controls.hiddenButtons.remove(button) } else { controls.hiddenButtons.insert(button) }
                             })) {
            HStack(spacing: 10) {
                IconTile(symbol: button.symbol, color: button.color, size: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(button.title)
                    if !isAvailable {
                        Text("Slå \(button.featureName) til først.").font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .disabled(!isAvailable)
    }
}

extension ActionBarButton {
    /// Navnet på funktionen, som den hedder på dens egen side.
    var featureName: String {
        switch self {
        case .read: return "oplæsning"
        case .screenText: return "Læs tekst fra skærmen (siden Oplæsning)"
        case .spelling: return "stavehjælpen (siden Stavning)"
        case .mailReply: return "Mail-svar (siden Mail)"
        case .sparring: return "Sparring om mailen (siden Mail)"
        }
    }
}
