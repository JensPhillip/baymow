import AppKit
import SwiftUI
import BaymowCore

// Fælles byggeklodser til brugerfladen (AP-62). Følger designprincipperne i planens afsnit 3:
// billede før ord, flag ved sprog, og alt kan læses op.

extension Language {
    /// Flaget, der vises overalt, hvor sproget vises eller vælges.
    var flag: String {
        switch self {
        case .danish: return "🇩🇰"
        case .english: return "🇬🇧"
        }
    }

    /// "🇩🇰 Dansk"
    var flagAndName: String { "\(flag) \(displayName)" }
}

/// Hastighed skrevet på dansk: "1,5×", "2×".
func rateLabel(_ rate: Double) -> String {
    let rounded = (rate * 10).rounded() / 10
    let text = rounded == rounded.rounded() ? String(format: "%.0f", rounded) : String(format: "%.1f", rounded)
    return text.replacingOccurrences(of: ".", with: ",") + "×"
}

extension Shortcut {
    /// Tasterne én for én, fx ["⌃", "⌥", "S"], til at tegne dem som taster.
    var keys: [String] {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var keys: [String] = []
        if flags.contains(.control) { keys.append("⌃") }
        if flags.contains(.option) { keys.append("⌥") }
        if flags.contains(.shift) { keys.append("⇧") }
        if flags.contains(.command) { keys.append("⌘") }
        keys.append(keyLabel)
        return keys
    }

    /// Genvejen med ord, til skærmlæsere og hjælpetekst: "Control, Option og S".
    var spokenKeys: String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var keys: [String] = []
        if flags.contains(.control) { keys.append("Control") }
        if flags.contains(.option) { keys.append("Option") }
        if flags.contains(.shift) { keys.append("Skift") }
        if flags.contains(.command) { keys.append("Kommando") }
        keys.append(keyLabel)
        return keys.dropLast().joined(separator: ", ") + " og " + keys.last!
    }
}

/// Hvidt symbol på en farvet, afrundet firkant – som ikonerne i Systemindstillinger.
struct IconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 26

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.52, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Genvejen tegnet som taster på et tastatur.
struct KeyCaps: View {
    let shortcut: Shortcut
    var size: CGFloat = 30

    var body: some View {
        HStack(spacing: size * 0.2) {
            ForEach(Array(shortcut.keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(size: size * 0.5, weight: .medium, design: .rounded))
                    .frame(minWidth: size, minHeight: size)
                    .padding(.horizontal, size * 0.12)
                    .background(.background, in: RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous).strokeBorder(.secondary.opacity(0.35)))
                    .shadow(color: .black.opacity(0.12), radius: 0, y: 1.5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shortcut.spokenKeys)
    }
}

/// "Hør"-knappen: læser en forklaring op, så den ikke skal læses.
struct ListenButton: View {
    /// Bliver der læst op lige nu? Så er knappen en stopknap.
    var isPlaying = false
    var help = "Læs forklaringen højt"
    var controlSize: ControlSize = .large
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(isPlaying ? "Stop" : "Hør", systemImage: isPlaying ? "stop.fill" : "speaker.wave.2.fill")
        }
        .buttonStyle(.bordered)
        .controlSize(controlSize)
        .help(isPlaying ? "Stop oplæsningen" : help)
    }
}

/// Lille farvet mærke, fx "Anbefalet" – altid med ikon, så farven ikke står alene.
struct Badge: View {
    let text: String
    let symbol: String
    let color: Color

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
    }
}

/// Lille knap, der kan stå valgt (fx hastighederne 1×, 1,5× …): valgt er udfyldt med systemets farve.
struct ChipStyle: ButtonStyle {
    let chosen: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: chosen ? .semibold : .regular).monospacedDigit())
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .foregroundStyle(chosen ? Color.white : Color.primary)
            .background(chosen ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary), in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

/// Ét nummereret trin med et lille billede.
struct GuideStep: View {
    let number: Int
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Text("\(number)").font(.caption.weight(.bold)).foregroundStyle(.white)
                .frame(width: 20, height: 20).background(Color.accentColor, in: Circle())
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 20)
            Text(text)
        }
        .accessibilityElement(children: .combine)
    }
}
