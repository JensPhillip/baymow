import SwiftUI
import BaymowCore

/// Tilstanden i mail-svarets lille vindue.
@MainActor
final class MailReplyPanelModel: ObservableObject {
    enum Problem: Equatable {
        case needsCloud
        case notSupported
        case caretInThread
        case cloud(CloudSpellingError)
    }

    enum State: Equatable {
        case working
        case done(String)
        case failed(Problem)
    }

    @Published var state: State = .working
    @Published private(set) var isListening = false
    /// Sat i mailen (ellers kopieret, fordi brugeren var skiftet til et andet program).
    var inserted = false
    var provider: CloudProvider = .openai
    /// Det, modellen selv har antaget (fx et tidspunkt) – vises, så brugeren kan tjekke det.
    var assumptions: [String] = []
    /// Den nyeste mail var brugerens egen: svaret er en opfølgning.
    var followUp = false
    var sourceBundleID: String?
    private let speak: SpellingPanelModel.Speak
    private let stop: () -> Void
    private var listenToken = 0

    init(speak: @escaping SpellingPanelModel.Speak, stop: @escaping () -> Void = {}) {
        self.speak = speak
        self.stop = stop
    }

    var reply: String? { if case .done(let text) = state { return text } else { return nil } }

    /// "Hør": læser svaret op. Et tryk mere stopper.
    func listen() {
        guard let reply else { return }
        listenToken += 1
        if isListening { stop(); isListening = false; return }
        let token = listenToken
        isListening = true
        speak(reply, .danish) { [weak self] in
            guard let self, self.listenToken == token else { return }
            self.isListening = false
        }
    }
}

/// Mail-svarets vindue: hvad der skete, felterne i [klammer] med orange, "Hør", "Fortryd".
struct MailReplyPanelView: View {
    @ObservedObject var model: MailReplyPanelModel
    let onUndo: () -> Void
    let onClose: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                IconTile(symbol: "envelope.fill", color: .indigo, size: 30)
                Text("Mail-svar").font(.title3.weight(.semibold))
                Spacer()
                if model.reply != nil {
                    ListenButton(isPlaying: model.isListening, help: "Læs svaret højt", controlSize: .regular,
                                 action: model.listen)
                }
                Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityLabel("Luk").help("Luk")
            }
            content
        }
        .padding(18)
        .frame(width: 440)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.primary.opacity(0.12)))
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .working:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("\(model.provider.title) skriver et svar …").foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
            sentLabel
        case .done(let reply):
            let fields = MailReplyPrompt.placeholders(in: reply)
            Label(model.inserted ? "Svaret står i din mail i stedet for dine stikord." : "Svaret er kopieret. Gå tilbage til mailen, og tryk ⌘V.",
                  systemImage: model.inserted ? "checkmark.circle.fill" : "doc.on.clipboard")
                .foregroundStyle(model.inserted ? .green : .orange)
            if model.followUp {
                Label("Den nyeste mail var din egen, så det er en opfølgning.", systemImage: "arrow.uturn.forward")
                    .foregroundStyle(.secondary)
            }
            if !model.assumptions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Baymow har antaget:", systemImage: "lightbulb.fill").foregroundStyle(.orange).font(.headline)
                    ForEach(Array(model.assumptions.enumerated()), id: \.offset) { _, assumption in
                        Label(assumption, systemImage: "questionmark.circle").foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Ret det i mailen, hvis det ikke passer.").font(.callout).foregroundStyle(.secondary)
                }
            }
            if fields.isEmpty && model.assumptions.isEmpty {
                Label("Læs svaret igennem, før du sender det.", systemImage: "eye").foregroundStyle(.secondary)
            } else if !fields.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label(fields.count == 1 ? "Udfyld 1 felt i [klammer]:" : "Udfyld \(fields.count) felter i [klammer]:",
                          systemImage: "exclamationmark.bubble.fill")
                        .foregroundStyle(.orange).font(.headline)
                    ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                        Text(field).padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.orange.opacity(0.22), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            HStack {
                sentLabel
                Spacer()
                if model.inserted {
                    Button(action: onUndo) { Label("Fortryd", systemImage: "arrow.uturn.backward") }
                        .controlSize(.large)
                        .help("Fjerner svaret og giver dig dine stikord tilbage (⌘Z i mailen).")
                }
            }
        case .failed(let problem):
            Label(Self.message(problem, provider: model.provider), systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            if problem == .needsCloud {
                Button(action: onSettings) { Label("Åbn Baymow", systemImage: "gearshape") }.controlSize(.large)
            }
        }
    }

    private var sentLabel: some View {
        Label("Mailtråden blev sendt til \(model.provider.company)", systemImage: "cloud.fill")
            .font(.caption).foregroundStyle(.secondary)
            .help("Mail-svar sender dine stikord og den citerede tråd til \(model.provider.company), når du trykker genvejen.")
    }

    static func message(_ problem: MailReplyPanelModel.Problem, provider: CloudProvider) -> String {
        switch problem {
        case .needsCloud:
            return "Mail-svar skal bruge en nøgle til ChatGPT eller Claude. Gem den på siden Mail i Baymow."
        case .notSupported:
            return "Baymow kan ikke læse svarfeltet i dette program endnu. Prøv i Apple Mail, og klik i svaret først."
        case .caretInThread:
            return "Sæt markøren lige efter dine stikord øverst i svaret, og prøv igen."
        case .cloud(let error):
            switch error {
            case .offline: return "Intet internet. Prøv igen, når du er på nettet."
            case .badKey, .noKey: return "Nøglen til \(provider.title) virker ikke. Se siden Mail i Baymow."
            case .failed: return "\(provider.title) svarede ikke. Prøv igen om lidt."
            }
        }
    }
}
