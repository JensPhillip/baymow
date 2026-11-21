import AppKit
import SwiftUI
import BaymowCore

/// Lille flytbar afspiller, der ligger oven på andre vinduer uden at tage fokus fra dem.
@MainActor
public final class FloatingPlayer: NSObject, NSWindowDelegate {
    private let sessions: ReadingSessionManager
    private let settings: SettingsStore
    private var panel: NSPanel?

    public init(sessions: ReadingSessionManager, settings: SettingsStore) {
        self.sessions = sessions
        self.settings = settings
    }

    public var frame: NSRect? { panel?.isVisible == true ? panel?.frame : nil }

    public func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.orderFrontRegardless()
    }

    /// Lukker afspilleren og afslutter sessionen, så teksten frigives. Appen kører videre.
    public func close() {
        sessions.close()
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let view = PlayerView(sessions: sessions, settings: settings) { [weak self] in self?.close() }
        let panel = FloatingPanel.make(content: view)
        panel.delegate = self
        panel.setFrameOrigin(FloatingPanel.origin(saved: settings.playerOrigin, size: panel.frame.size))
        return panel
    }

    public func windowDidMove(_ notification: Notification) {
        if let origin = panel?.frame.origin { settings.playerOrigin = origin }
    }
}

/// Fælles vinduestype for afspiller og beskeder.
@MainActor
enum FloatingPanel {
    static func make<Content: View>(content: Content) -> NSPanel {
        let hosting = NSHostingView(rootView: content)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.contentView = hosting
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }

    /// Gemt placering, hvis den stadig er på en skærm – ellers øverst til højre.
    static func origin(saved: CGPoint?, size: NSSize) -> NSPoint {
        if let saved, NSScreen.screens.contains(where: { $0.visibleFrame.intersects(NSRect(origin: saved, size: size)) }) {
            return saved
        }
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        return NSPoint(x: visible.maxX - size.width - 24, y: visible.maxY - size.height - 24)
    }
}

struct PlayerView: View {
    @ObservedObject var sessions: ReadingSessionManager
    @ObservedObject var settings: SettingsStore
    let onClose: () -> Void

    /// Så lille og stille som muligt (brugerens ønske 21. november 2026): én række små knapper og en tynd
    /// linje, der viser, hvor langt oplæsningen er nået. Tager ikke fokus fra teksten.
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                iconButton(sessions.state == .speaking ? "pause.fill" : "play.fill",
                           label: sessions.state == .speaking ? "Pause" : "Afspil", size: 15) { sessions.togglePlayPause() }
                    .keyboardShortcut(.space, modifiers: [])
                iconButton("backward.end.fill", label: "Start forfra", size: 11) { sessions.restart() }
                iconButton("stop.fill", label: "Stop", size: 11) { sessions.stop() }
                    .disabled(sessions.state == .stopped)

                Divider().frame(height: 14)

                iconButton("minus", label: "Langsommere", size: 10) { sessions.setRate(settings.rate - 0.1) }
                    .disabled(settings.rate <= SettingsStore.rateRange.lowerBound)
                Text(rateLabel(settings.rate))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 30)
                    .accessibilityLabel("Hastighed \(rateLabel(settings.rate))")
                iconButton("plus", label: "Hurtigere", size: 10) { sessions.setRate(settings.rate + 0.1) }
                    .disabled(settings.rate >= SettingsStore.rateRange.upperBound)

                Divider().frame(height: 14)

                Button {
                    settings.showReadingWindow.toggle()
                } label: {
                    Image(systemName: "text.viewfinder").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(settings.showReadingWindow ? Color.accentColor : Color.secondary)
                        .frame(width: 22, height: 22).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(settings.showReadingWindow ? "Skjul teksten" : "Vis teksten, og fremhæv ordet, der læses")
                .accessibilityLabel(settings.showReadingWindow ? "Skjul teksten" : "Vis teksten")

                Menu {
                    ForEach(Language.allCases) { language in
                        Button {
                            sessions.setLanguage(language)
                        } label: {
                            if language == sessions.language { Label(language.flagAndName, systemImage: "checkmark") }
                            else { Text(language.flagAndName) }
                        }
                    }
                } label: {
                    Text(sessions.language?.flag ?? "🌐").font(.system(size: 13))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Skift sprog for denne tekst")
                .accessibilityLabel("Sprog: \(sessions.language?.displayName ?? "ukendt")")

                Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 22)
                    .help("Luk afspilleren")
                    .accessibilityLabel("Luk afspilleren")
            }

            ProgressView(value: sessions.progress)
                .progressViewStyle(.linear)
                .controlSize(.mini)
                .tint(sessions.state == .speaking ? .accentColor : .secondary)
                .accessibilityLabel(statusText)
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .fixedSize()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.primary.opacity(0.1)))
    }

    private func iconButton(_ symbol: String, label: String, size: CGFloat = 15, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size, weight: .semibold)).frame(width: 22, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    private var statusText: String {
        switch sessions.state {
        case .speaking: return "Læser op"
        case .paused: return "På pause"
        case .stopped: return "Stoppet"
        case .finished: return "Færdig"
        case .idle: return "Klar"
        }
    }
}

/// Diskret besked, der forsvinder af sig selv.
@MainActor
public final class NoticePresenter {
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?
    private let settings: SettingsStore

    public init(settings: SettingsStore) { self.settings = settings }

    /// - Parameter below: vises under denne ramme (afspilleren), hvis den er synlig.
    public func show(_ notice: Notice, below anchor: NSRect? = nil, onOpenApp: @escaping () -> Void) {
        dismiss()
        var actionTitle: String?
        var action: (() -> Void)?
        switch notice {
        case .noPermission:
            actionTitle = "Åbn Systemindstillinger"
            action = { TextCaptureService.openAccessibilitySettings() }
        case .noVoice:
            actionTitle = "Åbn Baymow"
            action = onOpenApp
        case .noSelection, .unsupported, .tooLong:
            break
        }
        let view = NoticeView(message: notice.message, actionTitle: actionTitle) { [weak self] in
            action?()
            self?.dismiss()
        } onClose: { [weak self] in self?.dismiss() }

        let panel = FloatingPanel.make(content: view)
        let size = panel.frame.size
        if let anchor {
            panel.setFrameOrigin(NSPoint(x: anchor.minX, y: anchor.minY - size.height - 8))
        } else {
            panel.setFrameOrigin(FloatingPanel.origin(saved: settings.playerOrigin, size: size))
        }
        panel.orderFrontRegardless()
        self.panel = panel

        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: (action == nil ? 6 : 12) * 1_000_000_000)
            if !Task.isCancelled { self?.dismiss() }
        }
    }

    public func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

struct NoticeView: View {
    let message: String
    let actionTitle: String?
    let onAction: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange).font(.system(size: 16))
            VStack(alignment: .leading, spacing: 8) {
                Text(message).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                if let actionTitle { Button(actionTitle, action: onAction).controlSize(.small) }
            }
            Spacer(minLength: 4)
            Button(action: onClose) { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Luk besked")
        }
        .padding(14)
        .frame(width: 330)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.primary.opacity(0.12)))
    }
}
