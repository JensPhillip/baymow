import AppKit
import Carbon.HIToolbox

/// Registrerer én global tastaturgenvej via Carbon-hotkeys.
/// Kræver ingen særlige tilladelser og virker, uanset hvilket program der er forrest.
@MainActor
public final class GlobalShortcutManager {
    public var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    /// Hver genvej har sit eget nummer, så flere genveje (fx stavehjælpen, AP-63) ikke udløser hinanden.
    private let hotKeyNumber: UInt32
    private static var nextNumber: UInt32 = 1

    public init() {
        hotKeyNumber = Self.nextNumber
        Self.nextNumber += 1
    }

    /// Returnerer `false`, hvis genvejen ikke kunne registreres (fx optaget af et andet program).
    @discardableResult
    public func register(_ shortcut: Shortcut) -> Bool {
        unregister()
        installHandlerIfNeeded()

        let flags = NSEvent.ModifierFlags(rawValue: shortcut.modifiers)
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }

        let id = EventHotKeyID(signature: OSType(0x4F504C53) /* 'OPLS' */, id: hotKeyNumber)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, carbon, id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        hotKeyRef = ref
        return true
    }

    public func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData, let event else { return OSStatus(eventNotHandledErr) }
                var pressed = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &pressed)
                let manager = Unmanaged<GlobalShortcutManager>.fromOpaque(userData).takeUnretainedValue()
                // En anden genvej: lad den næste lytter få den.
                guard pressed.id == manager.hotKeyNumber else { return OSStatus(eventNotHandledErr) }
                // Carbon leverer hotkey-events på hovedtråden.
                MainActor.assumeIsolated { manager.onTrigger?() }
                return noErr
            },
            1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef
        )
    }
}
