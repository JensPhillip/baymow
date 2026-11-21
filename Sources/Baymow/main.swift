import AppKit
import BaymowKit
import BaymowCore

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
                                       outputDirectory: arguments[index + 3], raw: arguments.contains("--raw"),
                                       overrides: !arguments.contains("--no-overrides")))
    }
    if let index = arguments.firstIndex(of: "--install-voice"), arguments.count > index + 1 {
        exit(DeveloperTools.installVoice(id: arguments[index + 1]))
    }
    if let index = arguments.firstIndex(of: "--synthesize-text"), arguments.count > index + 3 {
        exit(DeveloperTools.synthesizeText(voiceDirectory: arguments[index + 1], textFile: arguments[index + 2],
                                           output: arguments[index + 3]))
    }
    if let index = arguments.firstIndex(of: "--soak-selftest"), arguments.count > index + 3 {
        exit(SoakTest.run(minutes: Double(arguments[index + 1]) ?? 480, interval: Double(arguments[index + 2]) ?? 300,
                          outputDirectory: arguments[index + 3]))
    }
    if let index = arguments.firstIndex(of: "--ax-bounds"), arguments.count > index + 1 {
        BoundsDiagnostics.run(bundleID: arguments[index + 1])
        exit(0)
    }
    if let index = arguments.firstIndex(of: "--inplace-selftest") {
        exit(InPlaceSelfTest.run(target: arguments.count > index + 1 ? arguments[index + 1] : "textedit"))
    }
    if arguments.contains("--highlight-selftest") {
        exit(HighlightSelfTest.run())
    }
    if arguments.contains("--copykey-selftest") {
        exit(CaptureSelfTest.runCopyKey())
    }
    if arguments.contains("--capture-selftest") {
        exit(CaptureSelfTest.run())
    }
    if let index = arguments.firstIndex(of: "--memory-selftest") {
        exit(MemorySelfTest.run(engineName: arguments.count > index + 1 ? arguments[index + 1] : "apple"))
    }
    if arguments.contains("--player-selftest") {
        exit(DeveloperTools.playerSelfTest())
    }
    if let index = arguments.firstIndex(of: "--prepare"), arguments.count > index + 1 {
        DeveloperTools.prepareStandardInput(engineID: arguments[index + 1])
        exit(0)
    }
    if arguments.contains("--normalize") {
        DeveloperTools.normalizeStandardInput()
        exit(0)
    }

    // Appens id skiftede 2026-11-21 (B9): flyt indstillingerne med, før de læses.
    SettingsMigration.migrateIfNeeded()

    let app = NSApplication.shared
    let shell = AppShell()
    app.delegate = shell
    app.setActivationPolicy(.regular)
    app.run()
}
