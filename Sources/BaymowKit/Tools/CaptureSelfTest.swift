import AppKit
import BaymowCore

/// `open -n -W build/Baymow.app --args --capture-selftest` (AP-41): viser et vindue med eksempelteksten fra
/// førstegangsopsætningen, markerer den og henter markeringen med samme kode som genvejen. Resultatet skrives
/// til ~/Library/Logs/Baymow/capture-selftest.txt (kun metode og om teksten passede – teksten er vores egen).
@MainActor
public enum CaptureSelfTest {
    public static func run() -> Int32 {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 120))
        textView.isEditable = false
        textView.isSelectable = true
        textView.string = OnboardingModel.sampleText
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 500, height: 120),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = textView
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        app.activate(ignoringOtherApps: true)

        let expected = "bliver teksten læst højt for dig"
        textView.setSelectedRange((textView.string as NSString).range(of: expected))

        var lines = ["trusted: \(TextCaptureService.hasPermission)"]
        var result: Result<CapturedText, CaptureFailure>?
        let deadline = Date().addingTimeInterval(3)
        while NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        lines.append("forrest: \(NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier)")

        // Samme rækkefølge som genvejen i AppShell: først Baymows eget vindue, så andre programmer.
        var passed = false
        if let own = OwnWindowSelection.text() {
            passed = own == expected
            lines.append("metode: eget vindue · tekst passede: \(passed)")
            lines.append(passed ? "BESTÅET" : "IKKE BESTÅET")
            write(lines)
            return passed ? 0 : 1
        }
        Task { result = await TextCaptureService().capture() }
        let end = Date().addingTimeInterval(5)
        while result == nil, Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }

        switch result {
        case .success(let captured):
            passed = captured.text == expected
            lines.append("metode: \(captured.method.rawValue) · tekst passede: \(passed)")
        case .failure(let failure):
            lines.append("fejl: \(failure.notice)")
        case nil:
            lines.append("tidsfrist overskredet")
        }
        lines.append(passed ? "BESTÅET" : "IKKE BESTÅET")
        write(lines)
        return passed ? 0 : 1
    }

    private static func write(_ lines: [String]) {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/Baymow")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? lines.joined(separator: "\n").write(to: dir.appendingPathComponent("capture-selftest.txt"), atomically: true, encoding: .utf8)
    }
}
