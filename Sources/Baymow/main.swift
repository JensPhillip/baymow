import AppKit
import BaymowKit

// Programmet starter altid på hovedtråden.
MainActor.assumeIsolated {
    let arguments = CommandLine.arguments
    if CommandLine.arguments.contains("--measure-latency") {
        LatencyProbe.run()
        exit(0)
    }

    if let index = CommandLine.arguments.firstIndex(of: "--ax-diagnose"), CommandLine.arguments.count > index + 1 {
        AccessibilityDiagnostics.run(bundleID: CommandLine.arguments[index + 1])
        exit(0)
    }

    if let index = arguments.firstIndex(of: "--synthesize"), arguments.count > index + 3 {
        exit(DeveloperTools.synthesize(voiceDirectory: arguments[index + 1], textFile: arguments[index + 2],
                                       outputDirectory: arguments[index + 3]))
    }
    if let index = arguments.firstIndex(of: "--install-voice"), arguments.count > index + 1 {
        exit(DeveloperTools.installVoice(id: arguments[index + 1]))
    }
    if arguments.contains("--normalize") {
        DeveloperTools.normalizeStandardInput()
        exit(0)
    }

    let app = NSApplication.shared
    let shell = AppShell()
    app.delegate = shell
    app.setActivationPolicy(.regular)
    app.run()
}
