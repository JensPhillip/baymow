import AppKit
import Combine
import SwiftUI

/// Hvordan knapbjælken ligger på skærmen (AP-77). Brugeren valgte C (logo, der folder sig ud) som standard.
enum ActionBarStyle: String, CaseIterable, Identifiable {
    case hover, edge, floating, dot

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hover: return "Logo, der folder sig ud"
        case .edge: return "Fast i skærmens kant"
        case .floating: return "Altid synlig"
        case .dot: return "Prik, du klikker på"
        }
    }

    var detail: String {
        switch self {
        case .hover: return "Hold musen over logoet, så kommer knapperne frem."
        case .edge: return "En lille fane i siden af skærmen. Hold musen over den."
        case .floating: return "Knapperne står fremme hele tiden."
        case .dot: return "Klik på logoet for at vise eller skjule knapperne."
        }
    }

    var symbol: String {
        switch self {
        case .hover: return "cursorarrow.rays"
        case .edge: return "sidebar.right"
        case .floating: return "rectangle.stack.fill"
        case .dot: return "circle.circle.fill"
        }
    }

    /// Ligger knapperne under hinanden (ellers ved siden af hinanden)?
    var isVertical: Bool { self == .edge || self == .floating }
}

/// Indstillingerne for knapbjælken og for tastaturgenvejene. Knapperne er slået fra som standard (planens afsnit 3);
/// velkomsten spørger nye brugere. Tasterne virker, til brugeren selv slår dem fra – og kun, hvis knapperne er slået til.
@MainActor
final class ActionBarSettings: ObservableObject {
    private let defaults: UserDefaults

    @Published var isEnabled: Bool { didSet { defaults.set(isEnabled, forKey: Keys.enabled) } }
    @Published var style: ActionBarStyle { didSet { defaults.set(style.rawValue, forKey: Keys.style) } }
    /// Knapper, brugeren har valgt fra.
    @Published var hiddenButtons: Set<ActionBarButton> {
        didSet { defaults.set(hiddenButtons.map(\.rawValue).sorted(), forKey: Keys.hidden) }
    }
    /// Brugerens eget valg om tastaturgenvejene. Se `keysActive`.
    @Published var keysEnabled: Bool { didSet { defaults.set(keysEnabled, forKey: Keys.keys) } }
    /// Har brugeren svaret på spørgsmålet i velkomsten?
    @Published var hasChosen: Bool { didSet { defaults.set(hasChosen, forKey: Keys.chosen) } }
    /// Fanen i kanten: højre (ellers venstre) side, og hvor højt (0 = bunden, 1 = toppen).
    @Published var edgeOnRight: Bool { didSet { defaults.set(edgeOnRight, forKey: Keys.edgeRight) } }
    @Published var edgeHeight: Double { didSet { defaults.set(edgeHeight, forKey: Keys.edgeHeight) } }

    enum Keys {
        static let enabled = "actionBarEnabled", style = "actionBarStyle", hidden = "actionBarHidden"
        static let keys = "keyboardShortcutsEnabled", chosen = "actionBarChosen"
        static let edgeRight = "actionBarEdgeRight", edgeHeight = "actionBarEdgeHeight"
        static let originX = "actionBarOrigin.x", originY = "actionBarOrigin.y"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Keys.enabled)
        style = defaults.string(forKey: Keys.style).flatMap(ActionBarStyle.init(rawValue:)) ?? .hover
        hiddenButtons = Set((defaults.stringArray(forKey: Keys.hidden) ?? []).compactMap(ActionBarButton.init(rawValue:)))
        keysEnabled = defaults.object(forKey: Keys.keys) as? Bool ?? true
        hasChosen = defaults.bool(forKey: Keys.chosen)
        edgeOnRight = defaults.object(forKey: Keys.edgeRight) as? Bool ?? true
        edgeHeight = defaults.object(forKey: Keys.edgeHeight) as? Double ?? 0.6
    }

    /// Virker tasterne? Uden knapper skal tasterne altid virke, ellers kan Baymow ikke bruges.
    var keysActive: Bool { !isEnabled || keysEnabled }

    /// Svaret i velkomsten: med eller uden knapper. Tasterne virker i begge tilfælde.
    func choose(buttons: Bool) {
        isEnabled = buttons
        keysEnabled = true
        hasChosen = true
    }

    /// Hvor logoet (eller bjælken) står – nederste venstre hjørne i skærmkoordinater.
    var savedOrigin: CGPoint? {
        get {
            guard defaults.object(forKey: Keys.originX) != nil else { return nil }
            return CGPoint(x: defaults.double(forKey: Keys.originX), y: defaults.double(forKey: Keys.originY))
        }
        set {
            if let newValue {
                defaults.set(newValue.x, forKey: Keys.originX)
                defaults.set(newValue.y, forKey: Keys.originY)
            } else {
                defaults.removeObject(forKey: Keys.originX)
                defaults.removeObject(forKey: Keys.originY)
            }
        }
    }

    /// Knapperne, der vises: kun funktioner, der er slået til, og som brugeren ikke har valgt fra.
    func visibleButtons(available: Set<ActionBarButton>) -> [ActionBarButton] {
        ActionBarButton.allCases.filter { available.contains($0) && !hiddenButtons.contains($0) }
    }
}
