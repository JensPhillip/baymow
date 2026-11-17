import Foundation
import CryptoKit
import Combine
import BaymowCore

/// En stemme, der kan hentes til appen. Listen er fast og kontrolleret: hver post har en kontrolsum,
/// så appen kun installerer præcis den fil, der er afprøvet.
public struct DownloadableVoice: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let language: Language
    public let locale: String
    public let engineID: String
    public let url: URL
    public let sha256: String
    public let sizeMB: Int
    public let licenseNote: String
    /// Har stemmen bestået stemmeporten? Ellers vælges den aldrig automatisk.
    public let isApprovedDefault: Bool

    public static let catalog: [DownloadableVoice] = [
        DownloadableVoice(
            id: "piper-da-talesyntese",
            name: "Talesyntese",
            language: .danish,
            locale: "da-DK",
            engineID: "piper",
            url: URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-da_DK-talesyntese-medium.tar.bz2")!,
            sha256: "f2e2cbcdb2b21e76f93635b35105d07b37997ace434d7289d04b689a97c19bd0",
            sizeMB: 67,
            licenseNote: "Forsøgsstemme (Piper). Ikke godkendt som standard: brugertest fandt den svær at forstå.",
            isApprovedDefault: false
        ),
    ]
}

/// Mappen med hentede stemmer: `~/Library/Application Support/Baymow/Voices/<id>/`.
public struct VoiceStore: Sendable {
    public let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Baymow/Voices", isDirectory: true)
    }

    public func directory(for id: String) -> URL { directory.appendingPathComponent(id, isDirectory: true) }

    public func isInstalled(_ id: String) -> Bool {
        FileManager.default.fileExists(atPath: directory(for: id).appendingPathComponent("installed").path)
    }

    public func installed() -> [DownloadableVoice] {
        DownloadableVoice.catalog.filter { isInstalled($0.id) }
    }
}

/// Henter, kontrollerer, installerer og sletter stemmer. Dette er appens eneste netværksadgang,
/// og den sker kun, når brugeren selv trykker "Hent".
@MainActor
public final class ModelDownloader: NSObject, ObservableObject {
    public enum DownloadError: LocalizedError {
        case http(Int), checksumMismatch, extractionFailed

        public var errorDescription: String? {
            switch self {
            case .http(let code): return "Serveren svarede med fejl \(code)."
            case .checksumMismatch: return "Den hentede fil var ikke den forventede og er blevet slettet."
            case .extractionFailed: return "Stemmen kunne ikke pakkes ud."
            }
        }
    }

    /// 0…1 for stemmer, der er ved at blive hentet.
    @Published public private(set) var progress: [String: Double] = [:]
    @Published public private(set) var errors: [String: String] = [:]
    /// Tæller op, når en stemme er installeret eller fjernet, så visninger kan opdatere.
    @Published public private(set) var revision = 0

    public let store: VoiceStore
    public var onChange: (() -> Void)?

    public init(store: VoiceStore = VoiceStore()) {
        self.store = store
    }

    public func isInstalled(_ voice: DownloadableVoice) -> Bool { store.isInstalled(voice.id) }

    public func download(_ voice: DownloadableVoice) {
        guard progress[voice.id] == nil else { return }
        progress[voice.id] = 0
        errors[voice.id] = nil
        Task {
            do {
                try await install(voice)
            } catch {
                errors[voice.id] = (error as? LocalizedError)?.errorDescription ?? "Stemmen kunne ikke hentes. Tjek internetforbindelsen."
            }
            progress[voice.id] = nil
            revision += 1
            onChange?()
        }
    }

    public func remove(_ voice: DownloadableVoice) {
        try? FileManager.default.removeItem(at: store.directory(for: voice.id))
        revision += 1
        onChange?()
    }

    private func install(_ voice: DownloadableVoice) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: store.directory, withIntermediateDirectories: true)

        let delegate = ProgressDelegate { [weak self] fraction in
            Task { @MainActor in self?.progress[voice.id] = fraction }
        }
        let (archive, response) = try await URLSession.shared.download(from: voice.url, delegate: delegate)
        defer { try? fm.removeItem(at: archive) }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw DownloadError.http(http.statusCode) }

        let staging = store.directory.appendingPathComponent(".staging-\(voice.id)", isDirectory: true)
        try? fm.removeItem(at: staging)
        defer { try? fm.removeItem(at: staging) }

        // Kontrolsum og udpakning er tunge og holdes væk fra hovedtråden.
        try await Task.detached(priority: .userInitiated) {
            guard try Self.sha256(of: archive) == voice.sha256 else { throw DownloadError.checksumMismatch }
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            let tar = Process()
            tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            // --strip-components 1: arkivet har én topmappe, som vi ikke vil have med.
            tar.arguments = ["-xjf", archive.path, "-C", staging.path, "--strip-components", "1"]
            try tar.run()
            tar.waitUntilExit()
            guard tar.terminationStatus == 0 else { throw DownloadError.extractionFailed }
            try Data().write(to: staging.appendingPathComponent("installed"))
        }.value

        let destination = store.directory(for: voice.id)
        try? fm.removeItem(at: destination)
        try fm.moveItem(at: staging, to: destination)
    }

    nonisolated static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private final class ProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: (Double) -> Void

    init(onProgress: @escaping (Double) -> Void) { self.onProgress = onProgress }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}
