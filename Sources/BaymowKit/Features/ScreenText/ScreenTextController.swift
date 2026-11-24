import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI
import BaymowCore

/// Indstillingerne for "Læs tekst fra skærmen". Slået fra som standard (planens afsnit 3).
@MainActor
final class ScreenTextSettings: ObservableObject {
    /// ⌃⌥T – "T" for tekst.
    nonisolated static let standardShortcut = Shortcut(keyCode: UInt32(kVK_ANSI_T),
                                                       modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue, keyLabel: "T")
    private let defaults: UserDefaults
    @Published var isEnabled: Bool { didSet { defaults.set(isEnabled, forKey: "screenTextEnabled") } }
    @Published var shortcut: Shortcut {
        didSet {
            defaults.set(Int(shortcut.keyCode), forKey: "screenTextShortcut.keyCode")
            defaults.set(Int(shortcut.modifiers), forKey: "screenTextShortcut.modifiers")
            defaults.set(shortcut.keyLabel, forKey: "screenTextShortcut.keyLabel")
        }
    }
    @Published var shortcutFailed = false
    /// Har Baymow lov til at se skærmen? Opdateres, når siden vises.
    @Published private(set) var hasPermission = ScreenCapture.hasPermission

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: "screenTextEnabled")
        if defaults.object(forKey: "screenTextShortcut.keyCode") != nil, let label = defaults.string(forKey: "screenTextShortcut.keyLabel") {
            shortcut = Shortcut(keyCode: UInt32(defaults.integer(forKey: "screenTextShortcut.keyCode")),
                                modifiers: UInt(defaults.integer(forKey: "screenTextShortcut.modifiers")), keyLabel: label)
        } else {
            shortcut = Self.standardShortcut
        }
    }

    func refreshPermission() {
        let now = ScreenCapture.hasPermission
        if now != hasPermission { hasPermission = now }
    }
}

/// Genvej → træk en firkant → billede af området → Macens tekstgenkendelse → oplæsning i den almindelige afspiller.
@MainActor
final class ScreenTextController {
    private let settings: ScreenTextSettings
    /// Starter oplæsningen; returnerer en besked, hvis den ikke kunne starte.
    private let read: (String) -> Notice?
    private var overlay: SelectionOverlay?
    private var message: NSPanel?
    private var isWorking = false

    init(settings: ScreenTextSettings, read: @escaping (String) -> Notice?) {
        self.settings = settings
        self.read = read
    }

    func run() {
        guard settings.isEnabled, !isWorking, overlay == nil else { return }
        closeMessage()
        settings.refreshPermission()
        guard ScreenCapture.hasPermission else {
            show(message: "Baymow skal have lov til at se skærmen for at kunne læse teksten.",
                 symbol: "rectangle.dashed.badge.record", button: ("Giv lov", { ScreenCapture.requestPermission() }))
            return
        }
        let overlay = SelectionOverlay { [weak self] rect in
            self?.overlay = nil
            if let rect { self?.recognize(rect) }
        }
        self.overlay = overlay
        overlay.show()
    }

    private func recognize(_ rect: CGRect) {
        isWorking = true
        Task {
            defer { isWorking = false }
            try? await Task.sleep(nanoseconds: 120_000_000) // overlægget skal være væk fra billedet
            do {
                let image = try await ScreenCapture.image(of: rect)
                let text = DanishLetterFix.apply(try await ScreenTextRecognizer.recognize(image))
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    show(message: "Baymow fandt ingen tekst i firkanten. Prøv en større firkant om teksten.",
                         symbol: "text.viewfinder", button: nil)
                    return
                }
                if let notice = read(text) { show(message: notice.message, symbol: "exclamationmark.triangle.fill", button: nil) }
            } catch ScreenTextError.unsupported {
                show(message: "Tekst fra skærmen kræver macOS 15.2 eller nyere.", symbol: "exclamationmark.triangle.fill", button: nil)
            } catch ScreenTextError.noPermission {
                show(message: "Baymow skal have lov til at se skærmen for at kunne læse teksten.",
                     symbol: "rectangle.dashed.badge.record", button: ("Giv lov", { ScreenCapture.requestPermission() }))
            } catch {
                show(message: "Baymow kunne ikke læse skærmen. Prøv igen.", symbol: "exclamationmark.triangle.fill", button: nil)
            }
        }
    }

    /// En lille besked øverst til højre. Uden knap forsvinder den selv efter 6 sekunder.
    private func show(message text: String, symbol: String, button: (String, () -> Void)?) {
        closeMessage()
        let view = ScreenTextMessageView(text: text, symbol: symbol, button: button.map { title, action in
            (title, { [weak self] in action(); self?.closeMessage() })
        }, onClose: { [weak self] in self?.closeMessage() })
        let panel = FloatingPanel.make(content: view)
        panel.setFrameOrigin(FloatingPanel.origin(saved: nil, size: panel.frame.size))
        panel.orderFrontRegardless()
        message = panel
        if button == nil {
            Task { [weak self, weak panel] in
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                if let panel, self?.message === panel { self?.closeMessage() }
            }
        }
    }

    private func closeMessage() {
        message?.orderOut(nil)
        message = nil
    }

    func close() {
        overlay?.close()
        overlay = nil
        closeMessage()
    }
}

private struct ScreenTextMessageView: View {
    let text: String
    let symbol: String
    let button: (String, () -> Void)?
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(symbol: symbol, color: .cyan, size: 30)
            VStack(alignment: .leading, spacing: 10) {
                Text(text).fixedSize(horizontal: false, vertical: true)
                if let button {
                    Button(action: button.1) { Label(button.0, systemImage: "lock.open.fill") }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                }
            }
            Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)) }
                .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Luk")
        }
        .padding(16)
        .frame(width: 380)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.primary.opacity(0.12)))
    }
}

// MARK: Firkanten

/// Et halvmørkt lag over alle skærme, hvor brugeren trækker en firkant. Esc eller et klik uden træk fortryder.
@MainActor
final class SelectionOverlay {
    private var windows: [NSWindow] = []
    private let completion: (CGRect?) -> Void
    private var finished = false
    /// Programmet, brugeren kom fra: får fokus igen bagefter.
    private var previous: NSRunningApplication?

    init(completion: @escaping (CGRect?) -> Void) {
        self.completion = completion
    }

    func show() {
        previous = NSWorkspace.shared.frontmostApplication
        for screen in NSScreen.screens {
            let window = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.ignoresMouseEvents = false
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.screenOrigin = screen.frame.origin
            view.onFinish = { [weak self] rect in self?.finish(rect) }
            window.contentView = view
            window.setFrame(screen.frame, display: true)
            windows.append(window)
            window.orderFrontRegardless()
        }
        NSApp.activate(ignoringOtherApps: true)
        let mouseScreen = windows.first { $0.frame.contains(NSEvent.mouseLocation) } ?? windows.first
        mouseScreen?.makeKey()
        mouseScreen?.makeFirstResponder(mouseScreen?.contentView)
    }

    private func finish(_ rect: CGRect?) {
        guard !finished else { return }
        finished = true
        close()
        completion(rect)
    }

    func close() {
        windows.forEach { $0.orderOut(nil) }
        windows = []
        if previous?.bundleIdentifier != Bundle.main.bundleIdentifier { previous?.activate() }
        previous = nil
    }
}

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

private final class SelectionView: NSView {
    var screenOrigin: CGPoint = .zero
    var onFinish: ((CGRect?) -> Void)?
    private var start: CGPoint?
    private var current: CGPoint?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) { onFinish?(nil) } else { super.keyDown(with: event) }
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let rect = selection, rect.width > 8, rect.height > 8 else { onFinish?(nil); return }
        // Til skærmens koordinater (AppKit: origo nederst til venstre på hovedskærmen).
        onFinish?(rect.offsetBy(dx: screenOrigin.x, dy: screenOrigin.y))
    }

    private var selection: CGRect? {
        guard let start, let current else { return nil }
        return CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                      width: abs(start.x - current.x), height: abs(start.y - current.y))
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()
        if let rect = selection {
            NSColor.clear.setFill()
            rect.fill(using: .copy)
            NSColor.systemBlue.setStroke()
            let path = NSBezierPath(rect: rect)
            path.lineWidth = 2
            path.stroke()
        } else {
            let hint = "Træk en firkant om teksten, der skal læses op  ·  Esc fortryder" as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 18, weight: .semibold),
                                                             .foregroundColor: NSColor.white]
            let size = hint.size(withAttributes: attributes)
            let box = NSRect(x: bounds.midX - size.width / 2 - 16, y: bounds.maxY - 120, width: size.width + 32, height: size.height + 16)
            NSColor.black.withAlphaComponent(0.6).setFill()
            NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10).fill()
            hint.draw(at: NSPoint(x: box.minX + 16, y: box.minY + 8), withAttributes: attributes)
        }
    }
}
