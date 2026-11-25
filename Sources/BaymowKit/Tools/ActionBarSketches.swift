import SwiftUI

/// Skitser af knapbjælken (AP-77) på et tegnet skrivebord, så brugeren kan vælge en variant. Ingen brugertekst.
@MainActor
enum ActionBarSketches {
    enum Variant: String, CaseIterable {
        case floating, dot, hover, edge

        var title: String {
            switch self {
            case .floating: return "A · Altid synlig"
            case .dot: return "B · Prik, der folder sig ud ved klik"
            case .hover: return "C · Logo, der folder sig ud, når musen er over"
            case .edge: return "D · Klæber til skærmens kant"
            }
        }

        var explanation: String {
            switch self {
            case .floating: return "Bjælken står fremme hele tiden. Træk den derhen, hvor den er i vejen mindst."
            case .dot: return "Kun en lille prik. Et klik viser knapperne, et klik mere skjuler dem."
            case .hover: return "Kun logoet. Hold musen over det, så kommer knapperne frem. Ingen klik."
            case .edge: return "En lille fane i siden af skærmen. Musen over fanen trækker bjælken ud."
            }
        }
    }

    static let buttons: [ActionBarButton] = [.read, .screenText, .spelling, .mailReply]

    /// Én variant, foldet sammen (`open == false`) eller åben.
    struct Scene: View {
        let variant: Variant
        let open: Bool

        var body: some View {
            ZStack {
                Desktop()
                overlay
            }
            .frame(width: 820, height: 500)
            .overlay(alignment: .topLeading) { caption.padding(14) }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }

        private var caption: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(variant.title).font(.headline)
                Text(open ? "Åben – musen er over \"Læs op\"" : "Foldet sammen").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 8))
        }

        @ViewBuilder private var overlay: some View {
            switch variant {
            case .floating:
                HStack(alignment: .top, spacing: 8) {
                    Spacer()
                    if open { ActionBarTip(button: .read).padding(.top, 80) }
                    ActionBarView(buttons: buttons, highlighted: open ? .read : nil)
                }
                .padding(.trailing, 24).padding(.top, 60)
                .frame(maxHeight: .infinity, alignment: .top)
            case .dot:
                VStack(alignment: .trailing, spacing: 10) {
                    Spacer()
                    if open {
                        ActionBarTip(button: .read)
                        ActionBarView(buttons: buttons, vertical: false, highlighted: .read, showMark: false)
                    }
                    ActionBarDot(hint: open ? nil : "Klik for knapper")
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(24)
            case .hover:
                VStack(alignment: .trailing, spacing: 10) {
                    HStack(alignment: .center, spacing: 10) {
                        Spacer()
                        if open {
                            ActionBarView(buttons: buttons, vertical: false, highlighted: .read, showMark: false)
                        }
                        ZStack(alignment: .bottomTrailing) {
                            BaymowMark(size: 46)
                            if open {
                                Image(systemName: "cursorarrow").font(.system(size: 22)).foregroundStyle(.black)
                                    .shadow(color: .white, radius: 1).offset(x: 10, y: 14)
                            }
                        }
                    }
                    if open { ActionBarTip(button: .read).padding(.trailing, 210) }
                    Spacer()
                }
                .padding(.trailing, 24).padding(.top, 70)
            case .edge:
                HStack(spacing: 8) {
                    Spacer()
                    if open {
                        ActionBarTip(button: .read)
                        ActionBarView(buttons: buttons, highlighted: .read)
                    } else {
                        ActionBarEdgeTab()
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    /// Et tegnet skrivebord med et dokument, hvor en sætning er markeret.
    struct Desktop: View {
        var body: some View {
            ZStack {
                LinearGradient(colors: [Color(red: 0.36, green: 0.52, blue: 0.78), Color(red: 0.62, green: 0.45, blue: 0.70)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0).frame(width: 10, height: 10) }
                        Spacer()
                        Text("Brev til forældre.docx").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(10)
                    .background(Color(nsColor: .windowBackgroundColor))
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Kære forældre").font(.title3.weight(.semibold))
                        Text(Self.paragraph)
                        Text("Har I spørgsmål, er I velkomne til at skrive til mig.")
                        RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.18)).frame(height: 9)
                        RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.18)).frame(width: 300, height: 9)
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(Color(nsColor: .textBackgroundColor))
                }
                .frame(width: 470, height: 330)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
                .offset(x: -110, y: 20)
            }
        }

        /// Afsnittet med én sætning markeret, som i et rigtigt program.
        static var paragraph: AttributedString {
            var marked = AttributedString("Husk at give jeres barn madpakke og regntøj med.")
            marked.backgroundColor = Color(nsColor: .selectedTextBackgroundColor)
            return AttributedString("Vi glæder os til skolefesten på fredag. ") + marked
                + AttributedString(" Festen begynder kl. 17 i gymnastiksalen.")
        }
    }

    /// Alle varianter, foldet sammen og åbne.
    static func shots() -> [(String, AnyView)] {
        Variant.allCases.flatMap { variant in
            [("knapbjaelke-\(variant.rawValue)-lukket", AnyView(Scene(variant: variant, open: false))),
             ("knapbjaelke-\(variant.rawValue)-aaben", AnyView(Scene(variant: variant, open: true)))]
        }
    }
}
