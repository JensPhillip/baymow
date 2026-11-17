import Foundation

/// Lokal fejllog uden brugerindhold.
///
/// API'et tager bevidst kun lukkede enum-værdier, et bundle-id og et tal. Der findes ingen
/// fritekst-parameter, så markeret tekst kan ikke ende i loggen ved en fejl.
/// Loggen uploades aldrig.
public final class DiagnosticsService: @unchecked Sendable {
    public enum Event: String, Sendable {
        case appLaunched
        case hotkeyRegistrationFailed
        case captureSucceeded
        case captureNoSelection
        case captureNoPermission
        case captureUnsupported
        case speechStarted
        case speechFailed
        case noVoiceAvailable
    }

    public enum CaptureMethod: String, Sendable {
        case accessibility
        case webTextMarker
        case clipboard
    }

    public let logURL: URL
    private let queue = DispatchQueue(label: "baymow.diagnostics")
    private let maxBytes = 1_000_000

    public init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Baymow", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        logURL = dir.appendingPathComponent("baymow.log")
    }

    /// - Parameter voice: stemmen, der læste. Kun dens id og sprog logges – de kommer fra stemmekataloget, ikke fra brugeren.
    public func record(_ event: Event, sourceBundleID: String? = nil, method: CaptureMethod? = nil, milliseconds: Int? = nil,
                       voice: Voice? = nil) {
        let time = ISO8601DateFormatter().string(from: Date())
        queue.async { [logURL, maxBytes] in
            var fields: [String: Any] = ["time": time, "event": event.rawValue]
            if let sourceBundleID { fields["source"] = sourceBundleID }
            if let method { fields["method"] = method.rawValue }
            if let milliseconds { fields["ms"] = milliseconds }
            if let voice {
                fields["voice"] = voice.id
                fields["language"] = voice.language.rawValue
            }
            guard var data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]) else { return }
            data.append(0x0A)

            let fm = FileManager.default
            if let size = (try? fm.attributesOfItem(atPath: logURL.path))?[.size] as? Int, size > maxBytes {
                let old = logURL.appendingPathExtension("1")
                try? fm.removeItem(at: old)
                try? fm.moveItem(at: logURL, to: old)
            }
            if let handle = try? FileHandle(forWritingTo: logURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: logURL)
            }
        }
    }

    /// Venter til alle ventende linjer er skrevet (bruges i tests).
    public func flush() { queue.sync {} }
}
