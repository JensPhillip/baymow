import SwiftUI
import BaymowCore

/// Tilstanden i stavehjælpens vindue.
@MainActor
final class SpellingPanelModel: ObservableObject {
    enum State: Equatable { case working, ready, tooLong }

    @Published var state: State = .working
    @Published private(set) var segments: [SpellingSegment] = []
    @Published var copied = false
    /// Vises, hvis brugeren er skiftet til et andet program: teksten er kopieret i stedet.
    @Published var pasteHint = false
    private(set) var usedModel = true
    private(set) var source: SpellingSource = .mac
    private(set) var cloudProblem: CloudSpellingError?
    /// Det firma, brugeren har valgt (til beskeder, når internet-hjælpen ikke virkede).
    var chosenProvider: CloudProvider = .openai
    private(set) var language: Language = .danish
    /// Valgmulighederne for hvert ændret ord, i fast rækkefølge: det skrevne, Baymows rettelse, andre forslag.
    private(set) var options: [Int: [String]] = [:]

    let sourceBundleID: String?
    private let speak: (String, Language) -> Void

    init(sourceBundleID: String?, speak: @escaping (String, Language) -> Void) {
        self.sourceBundleID = sourceBundleID
        self.speak = speak
    }

    func load(_ result: SpellingResult) {
        segments = result.segments
        usedModel = result.usedModel
        source = result.source
        cloudProblem = result.cloudProblem
        language = result.language
        for segment in result.changes {
            options[segment.id] = SpellingGuard.unique([segment.original, segment.text] + segment.suggestions, excluding: "")
        }
        state = .ready
    }

    var text: String { segments.map(\.text).joined() }
    var changes: [SpellingSegment] { segments.filter { $0.kind != .same } }
    var hasChanges: Bool { segments.contains { $0.isChanged } }

    /// Brugeren vælger et ord og hører det.
    func choose(_ word: String, for id: Int) {
        guard let index = segments.firstIndex(where: { $0.id == id }) else { return }
        segments[index].text = word
        copied = false
        speak(word, language)
    }

    func listen() { speak(text, language) }
}

/// Stavehjælpens vindue: teksten med farver, ét felt pr. rettelse og to knapper.
struct SpellingPanelView: View {
    @ObservedObject var model: SpellingPanelModel
    let onApply: () -> Void
    let onCopy: () -> Void
    let onClose: () -> Void

    static let corrected = Color.green
    static let uncertain = Color.orange

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            switch model.state {
            case .working:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Baymow ser på din tekst …").foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            case .tooLong:
                Label("Teksten er for lang. Markér et mindre stykke.", systemImage: "text.badge.xmark")
                    .foregroundStyle(.orange)
            case .ready:
                if model.changes.isEmpty {
                    Label("Ingen fejl fundet", systemImage: "checkmark.circle.fill")
                        .font(.title3.weight(.semibold)).foregroundStyle(Self.corrected)
                } else {
                    result
                }
                footer
            }
        }
        .padding(18)
        .frame(width: 480)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.primary.opacity(0.12)))
    }

    private var header: some View {
        HStack(spacing: 10) {
            IconTile(symbol: "textformat.abc.dottedunderline", color: .teal, size: 30)
            Text("Stavehjælp").font(.title3.weight(.semibold))
            Spacer()
            if model.state == .ready {
                Button(action: model.listen) { Label("Hør", systemImage: "speaker.wave.2.fill") }
                    .buttonStyle(.bordered)
                    .help("Læs den rettede tekst højt")
            }
            Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)) }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel("Luk stavehjælpen").help("Luk")
        }
    }

    @ViewBuilder private var result: some View {
        ScrollView {
            Text(highlighted)
                .font(.system(size: 17))
                .lineSpacing(5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(maxHeight: 220)
        .fixedSize(horizontal: false, vertical: true)

        Divider()
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.changes) { segment in ChangeRow(model: model, segment: segment) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 200)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let problem = model.cloudProblem {
                Label(Self.message(for: problem, provider: model.chosenProvider), systemImage: "wifi.exclamationmark")
                    .font(.callout).foregroundStyle(.orange)
            } else if !model.usedModel {
                Label("Kun Macens stavekontrol. Slå Apple Intelligence til for bedre hjælp.", systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if model.pasteHint {
                Label("Kopieret. Gå tilbage til din tekst, og tryk ⌘V.", systemImage: "doc.on.clipboard")
                    .font(.callout).foregroundStyle(.orange)
            }
            HStack(spacing: 10) {
                sourceLabel
                Spacer()
                Button(action: onCopy) {
                    Label(model.copied ? "Kopieret" : "Kopiér", systemImage: model.copied ? "checkmark" : "doc.on.doc")
                }
                .controlSize(.large)
                .help("Læg den rettede tekst på udklipsholderen")
                if model.hasChanges {
                    Button(action: onApply) { Label("Brug rettelsen", systemImage: "checkmark.circle.fill") }
                        .buttonStyle(PrimaryStyle())
                        .help("Skift din markerede tekst ud med den rettede")
                }
            }
        }
    }

    @ViewBuilder private var sourceLabel: some View {
        if case .cloud(let provider) = model.source {
            Label("Rettet af \(provider.title) via internet", systemImage: "cloud.fill")
                .font(.caption).foregroundStyle(.secondary)
                .help("Teksten blev sendt til \(provider.company), fordi du har slået \"Bedre hjælp via internet\" til.")
        } else {
            Label("Rettet på din Mac", systemImage: "lock.fill")
                .font(.caption).foregroundStyle(.secondary)
                .help("Din tekst bliver på din Mac. Intet sendes væk.")
        }
    }

    static func message(for problem: CloudSpellingError, provider: CloudProvider) -> String {
        switch problem {
        case .offline: return "Intet internet. Rettet af Macens egen hjælp, som finder færre fejl."
        case .badKey: return "Nøglen til \(provider.title) virker ikke. Rettet af Macens egen hjælp. Se siden Stavning i Baymow."
        case .noKey: return "Der mangler en nøgle til \(provider.title). Rettet af Macens egen hjælp. Se siden Stavning i Baymow."
        case .failed: return "\(provider.title) svarede ikke. Rettet af Macens egen hjælp, som finder færre fejl."
        }
    }

    /// Teksten med rettede ord på grøn baggrund og ord, du selv skal tjekke, på orange.
    private var highlighted: AttributedString {
        var out = AttributedString()
        for segment in model.segments {
            var piece = AttributedString(segment.text)
            if segment.isChanged {
                piece.backgroundColor = Self.corrected.opacity(0.28)
                piece.font = .system(size: 17, weight: .semibold)
            } else if segment.kind == .uncertain {
                piece.backgroundColor = Self.uncertain.opacity(0.28)
                piece.underlineStyle = .single
            }
            out += piece
        }
        return out
    }
}

/// Ét ændret ord: et ikon og ordene, man kan vælge imellem. Et tryk vælger ordet og læser det op.
private struct ChangeRow: View {
    @ObservedObject var model: SpellingPanelModel
    let segment: SpellingSegment

    private var current: SpellingSegment { model.segments.first { $0.id == segment.id } ?? segment }

    var body: some View {
        let current = current
        HStack(spacing: 8) {
            Image(systemName: current.isChanged ? "checkmark.circle.fill" : "questionmark.circle.fill")
                .foregroundStyle(current.isChanged ? SpellingPanelView.corrected : SpellingPanelView.uncertain)
                .font(.system(size: 18))
                .frame(width: 22)
                .accessibilityHidden(true)
            ForEach(model.options[segment.id] ?? [], id: \.self) { word in
                Button { model.choose(word, for: segment.id) } label: {
                    HStack(spacing: 4) {
                        if word == current.original { Image(systemName: "pencil").font(.system(size: 10)) }
                        Text(word).strikethrough(word == current.original && current.isChanged)
                    }
                }
                .buttonStyle(ChipStyle(chosen: current.text == word))
                .help(word == current.original ? "Det, du skrev. Tryk for at beholde det og høre det."
                                               : "Tryk for at vælge \"\(word)\" og høre det.")
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Du skrev \(current.original). Valgt: \(current.text).")
    }
}

/// Hovedknappen. Altid blå: vinduet tager ikke fokus fra brugerens program, og macOS ville ellers tegne den grå.
private struct PrimaryStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Rectangle())
    }
}
