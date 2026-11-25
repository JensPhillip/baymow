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
        case .screenText: return "Træk en firkant om tekst, du ikke kan markere, for eksempel i et billede."
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
    /// Musen kom over en knap (nil: væk igen).
    var onHover: (ActionBarButton?) -> Void = { _ in }
    /// Vises øverst i stedet for mærket (fx logoet, der kan trækkes).
    var header: AnyView?

    var body: some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 6))
        layout {
            if let header {
                header.padding(vertical ? .bottom : .trailing, 2)
                Divider().frame(width: vertical ? 44 : nil, height: vertical ? nil : 44)
            } else if showMark {
                BaymowMark(size: 30).padding(vertical ? .bottom : .trailing, 2)
                Divider().frame(width: vertical ? 44 : nil, height: vertical ? nil : 44)
            }
            ForEach(buttons) { button in
                Button { action(button) } label: { tile(button) }
                    .buttonStyle(.plain)
                    .onHover { inside in onHover(inside ? button : nil) }
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
        .animation(.easeOut(duration: 0.12), value: highlighted)
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

// MARK: Velkomsten: med eller uden knapper?

/// Valget i velkomsten. Tasterne virker i begge tilfælde; de kan slås fra senere under Indstillinger.
enum ControlPreference: String, CaseIterable, Identifiable {
    case withButtons, withoutButtons

    var id: String { rawValue }

    var title: String {
        switch self {
        case .withButtons: return "Med knapper"
        case .withoutButtons: return "Uden knapper"
        }
    }

    var detail: String {
        switch self {
        case .withButtons: return "Et lille Baymow-logo på skærmen. Hold musen over det, og tryk på en knap. Tasterne virker også."
        case .withoutButtons: return "Kun tasterne på tastaturet. Der er intet ekstra på skærmen."
        }
    }
}

/// De to kort i velkomsten.
struct ControlPreferenceCards: View {
    let choice: ControlPreference?
    let choose: (ControlPreference) -> Void

    var body: some View {
        HStack(spacing: 14) {
            ForEach(ControlPreference.allCases) { option in
                Button { choose(option) } label: { card(option) }.buttonStyle(.plain)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func card(_ option: ControlPreference) -> some View {
        let selected = choice == option
        return VStack(spacing: 10) {
            picture(option).frame(height: 70)
            Text(option.title).font(.headline)
            Text(option.detail).font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.title2).foregroundStyle(selected ? Color.accentColor : .secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.primary.opacity(selected ? 0.08 : 0.03), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 2 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private func picture(_ option: ControlPreference) -> some View {
        switch option {
        case .withButtons:
            HStack(spacing: 8) {
                ActionBarView(buttons: [.read, .spelling], vertical: false, showLabels: false, showMark: false)
                    .scaleEffect(0.75)
                BaymowMark(size: 34)
            }
        case .withoutButtons:
            KeyCaps(shortcut: .standard, size: 26)
        }
    }
}
