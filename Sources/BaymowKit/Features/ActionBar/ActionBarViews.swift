import SwiftUI
import BaymowCore

// Knapbjælken (AP-77, brugerens idé 25. november 2026): knapper på skærmen som alternativ til tastaturgenvejene.
// Genvejene bliver; bjælken er for dem, der hellere vil trykke. Her er kun udseendet – skitser til brugerens valg.

/// En knap på bjælken. Gør det samme som funktionens genvej.
enum ActionBarButton: String, CaseIterable, Identifiable {
    case read, screenText, spelling, mailReply, sparring

    var id: String { rawValue }

    var title: String {
        switch self {
        case .read: return "Læs op"
        case .screenText: return "Fra skærmen"
        case .spelling: return "Ret stavning"
        case .mailReply: return "Svar på mail"
        case .sparring: return "Spørg om mail"
        }
    }

    var symbol: String {
        switch self {
        case .read: return "speaker.wave.2.fill"
        case .screenText: return "text.viewfinder"
        case .spelling: return "textformat.abc.dottedunderline"
        case .mailReply: return "envelope.fill"
        case .sparring: return "bubble.left.and.text.bubble.right.fill"
        }
    }

    var color: Color {
        switch self {
        case .read: return .orange
        case .screenText: return .cyan
        case .spelling: return .teal
        case .mailReply, .sparring: return .indigo
        }
    }

    /// Forklaringen, der vises (og kan høres), når musen holdes over knappen.
    var help: String {
        switch self {
        case .read: return "Markér tekst, og tryk her for at få den læst op."
        case .screenText: return "Træk en firkant om tekst, du ikke kan markere, fx i et billede."
        case .spelling: return "Markér din egen tekst, og tryk her for at få stavningen rettet."
        case .mailReply: return "Skriv stikord øverst i dit svar i Apple Mail, og tryk her."
        case .sparring: return "Åbn en mail i Apple Mail, og tryk her for at stille spørgsmål til den."
        }
    }
}

/// Baymows mærke. Pladsholder, til der er et rigtigt logo.
struct BaymowMark: View {
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: "waveform")
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            .accessibilityLabel("Baymow")
    }
}

/// Selve bjælken: store knapper med ikon og (valgfrit) tekst under.
struct ActionBarView: View {
    let buttons: [ActionBarButton]
    var vertical = true
    var showLabels = true
    /// Knappen, musen står over (kun til skitserne; i appen styrer musen det selv).
    var highlighted: ActionBarButton?
    var showMark = true
    var action: (ActionBarButton) -> Void = { _ in }

    var body: some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 6))
        layout {
            if showMark {
                BaymowMark(size: 30).padding(vertical ? .bottom : .trailing, 2)
                Divider().frame(width: vertical ? 44 : nil, height: vertical ? nil : 44)
            }
            ForEach(buttons) { button in
                Button { action(button) } label: { tile(button) }
                    .buttonStyle(.plain)
                    .help(button.help)
                    .accessibilityLabel(button.title)
                    .accessibilityHint(button.help)
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
    }

    private func tile(_ button: ActionBarButton) -> some View {
        VStack(spacing: 4) {
            IconTile(symbol: button.symbol, color: button.color, size: 34)
            if showLabels {
                Text(button.title).font(.system(size: 11, weight: .medium)).lineLimit(1).fixedSize()
            }
        }
        .frame(minWidth: showLabels ? 72 : 44, minHeight: 44)
        .padding(.vertical, 4)
        .background(highlighted == button ? Color.primary.opacity(0.1) : .clear,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
    }
}

/// Forklaringen ved musen: tekst og en lille "Hør"-knap.
struct ActionBarTip: View {
    let button: ActionBarButton

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(button.help).fixedSize(horizontal: false, vertical: true)
            ListenButton(isPlaying: false, help: "Læs forklaringen højt", controlSize: .small) {}
        }
        .padding(10)
        .frame(width: 250, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
    }
}

/// Den lille Baymow-prik, når bjælken er foldet sammen.
struct ActionBarDot: View {
    var hint: String?

    var body: some View {
        HStack(spacing: 8) {
            BaymowMark(size: 42)
            if let hint {
                Text(hint).font(.callout.weight(.medium))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
            }
        }
    }
}

/// Fanen, der stikker lidt ud fra skærmens kant, når bjælken sidder fast i siden.
struct ActionBarEdgeTab: View {
    var body: some View {
        VStack(spacing: 6) {
            BaymowMark(size: 26)
            Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
        }
        .padding(.vertical, 10).padding(.leading, 6).padding(.trailing, 10)
        .background(.regularMaterial, in: UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12,
                                                                 bottomTrailingRadius: 0, topTrailingRadius: 0))
        .shadow(color: .black.opacity(0.2), radius: 6, x: -2)
    }
}

// MARK: Velkomsten: hvordan vil du helst bruge Baymow?

/// Valget i velkomsten. Kan ændres bagefter under Indstillinger.
enum ControlPreference: String, CaseIterable, Identifiable {
    case buttons, keys, both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .buttons: return "Knapper på skærmen"
        case .keys: return "Taster på tastaturet"
        case .both: return "Begge dele"
        }
    }

    var detail: String {
        switch self {
        case .buttons: return "Tryk på en knap med musen."
        case .keys: return "Tryk for eksempel ⌃⌥S. Hurtigt, når man kender tasterne."
        case .both: return "Knapperne er der, og tasterne virker også."
        }
    }
}

struct ControlPreferenceStep: View {
    @Binding var choice: ControlPreference?
    var onListen: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                IconTile(symbol: "hand.tap.fill", color: .blue, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hvordan vil du helst bruge Baymow?").font(.title2.weight(.semibold))
                    Text("Du kan altid skifte under Indstillinger.").foregroundStyle(.secondary)
                }
                Spacer()
                ListenButton(isPlaying: false, help: "Læs trinnet højt", controlSize: .regular, action: onListen)
            }
            HStack(spacing: 14) {
                ForEach(ControlPreference.allCases) { option in
                    Button { choice = option } label: { card(option) }.buttonStyle(.plain)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
    }

    private func card(_ option: ControlPreference) -> some View {
        let selected = choice == option
        return VStack(spacing: 12) {
            picture(option).frame(height: 120)
            Text(option.title).font(.headline)
            Text(option.detail).font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.title2).foregroundStyle(selected ? Color.accentColor : .secondary)
        }
        .padding(16)
        .frame(width: 200)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.primary.opacity(selected ? 0.08 : 0.03), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 2 : 1))
    }

    @ViewBuilder private func picture(_ option: ControlPreference) -> some View {
        let small = ActionBarView(buttons: [.read, .spelling], vertical: false, showLabels: false, showMark: false)
            .scaleEffect(0.8)
        let keys = KeyCaps(shortcut: .standard, size: 26)
        switch option {
        case .buttons: small
        case .keys: keys
        case .both: VStack(spacing: 4) { small; keys.scaleEffect(0.8) }.scaleEffect(0.9)
        }
    }
}
