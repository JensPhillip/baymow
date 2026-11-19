import AppKit

/// "Om Baymow" (AP-50): version, licens og kreditering af de dele, Baymow bygger på. Se docs/LICENSER.md.
@MainActor
enum AboutBaymow {
    /// Dele, der bygges ind i appen, og deres licenser. Holdes i trit med docs/LICENSER.md.
    static let components: [(name: String, license: String)] = [
        ("sherpa-onnx", "Apache-2.0"), ("ONNX Runtime", "MIT"), ("eSpeak NG", "GPL-3.0-or-later"),
        ("piper-phonemize", "MIT"), ("Kaldi-komponenter", "Apache-2.0"), ("OpenFst", "Apache-2.0"),
        ("KISS FFT", "BSD-3-Clause"), ("SentencePiece", "Apache-2.0"),
    ]

    static var creditsText: String {
        var lines = [
            "Baymow læser markeret tekst højt – lokalt på din Mac.",
            "",
            "Fri software under GNU General Public License version 3 eller senere (GPL-3.0-or-later).",
            "Du må bruge, ændre og videregive Baymow på samme vilkår.",
            "",
            "Bygger på:",
        ]
        lines += components.map { "• \($0.name) (\($0.license))" }
        lines += [
            "",
            "Stemmer: Apples systemstemmer (del af macOS) og Piper-stemmen \"talesyntese\" (træningsdata CC0), som du selv kan hente.",
        ]
        return lines.joined(separator: "\n")
    }

    static func show() {
        let credits = NSAttributedString(string: creditsText, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor,
        ])
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Baymow", .credits: credits])
    }
}
