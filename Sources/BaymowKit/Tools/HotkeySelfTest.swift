import AppKit
import Carbon.HIToolbox
import BaymowCore

/// `--hotkey-selftest`: to genveje på én gang (⌃⌥S og ⌃⌥R, AP-63). Hver tast skal kun udløse sin egen genvej.
/// Sender tasterne som systemhændelser, så det kræver Tilgængelighed (som appen selv).
@MainActor
public enum HotkeySelfTest {
    public static func run() -> Int32 {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.finishLaunching()
        print("Tilgængelighed: \(TextCaptureService.hasPermission ? "ja" : "nej")")
        let read = GlobalShortcutManager(), spell = GlobalShortcutManager()
        var log: [String] = []
        read.onTrigger = { log.append("S") }
        spell.onTrigger = { log.append("R") }
        guard read.register(.standard),
              spell.register(Shortcut(keyCode: UInt32(kVK_ANSI_R), modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue,
                                      keyLabel: "R")) else {
            print("FEJL: genvejene kunne ikke registreres (kører Baymow allerede? Afslut den først)"); return 1
        }
        func press(_ key: Int) {
            let source = CGEventSource(stateID: .privateState)
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: down)
                event?.flags = [.maskControl, .maskAlternate]
                event?.post(tap: .cgSessionEventTap)
            }
            // Carbon leverer genvejene gennem programmets hændelseskø.
            let until = Date().addingTimeInterval(0.4)
            while Date() < until {
                if let event = NSApplication.shared.nextEvent(matching: .any, until: Date().addingTimeInterval(0.02),
                                                              inMode: .default, dequeue: true) {
                    NSApplication.shared.sendEvent(event)
                }
            }
        }
        press(kVK_ANSI_S); press(kVK_ANSI_R); press(kVK_ANSI_S)
        read.unregister(); spell.unregister()
        let ok = log == ["S", "R", "S"]
        print("\(ok ? "BESTÅET" : "FEJL"): forventet S R S, fik \(log.joined(separator: " "))")
        return ok ? 0 : 1
    }
}
