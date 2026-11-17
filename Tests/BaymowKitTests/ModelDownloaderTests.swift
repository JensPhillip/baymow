import XCTest
@testable import BaymowKit
import BaymowCore

/// AP-40: download er alt eller intet, kan prøves igen, og diskplads kontrolleres først.
/// Netværket er udskiftet med en falsk "fetch", så testene kører uden internet.
@MainActor
final class ModelDownloaderTests: XCTestCase {
    private var root: URL!
    private var store: VoiceStore!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("baymow-dl-\(UUID().uuidString)")
        store = VoiceStore(directory: root.appendingPathComponent("Voices"))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// Et rigtigt tar.bz2-arkiv med én topmappe, som en stemme fra sherpa-onnx.
    private func makeArchive() throws -> (url: URL, sha256: String) {
        let source = root.appendingPathComponent("src/voice", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("tokens".utf8).write(to: source.appendingPathComponent("tokens.txt"))
        let archive = root.appendingPathComponent("voice.tar.bz2")
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-cjf", archive.path, "-C", source.deletingLastPathComponent().path, "voice"]
        try tar.run()
        tar.waitUntilExit()
        return (archive, try ModelDownloader.sha256(of: archive))
    }

    private func voice(sha256: String, sizeMB: Int = 1) -> DownloadableVoice {
        DownloadableVoice(id: "test-voice", name: "Test", language: .danish, locale: "da-DK", engineID: "piper",
                          url: URL(string: "https://example.invalid/voice.tar.bz2")!, sha256: sha256, sizeMB: sizeMB,
                          licenseNote: "", isApprovedDefault: false)
    }

    /// Kopierer arkivet til en ny midlertidig fil, som en rigtig download ville give.
    private func fetchCopy(of archive: URL) -> ModelDownloader.Fetcher {
        { _, progress in
            progress(1)
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent("baymow-fetch-\(UUID().uuidString)")
            try FileManager.default.copyItem(at: archive, to: copy)
            return copy
        }
    }

    /// Alt, der ligger i stemmemappen (inkl. skjulte filer) – der må ikke ligge halve installationer.
    private func leftovers() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: store.directory.path)) ?? []
    }

    func testSuccessfulInstallAndRemove() async throws {
        let (archive, sha) = try makeArchive()
        let downloader = ModelDownloader(store: store, fetch: fetchCopy(of: archive), availableSpace: { _ in .max })
        let voice = voice(sha256: sha)
        try await downloader.install(voice)
        XCTAssertTrue(downloader.isInstalled(voice))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.directory(for: voice.id).appendingPathComponent("tokens.txt").path))
        XCTAssertEqual(leftovers(), ["test-voice"])

        downloader.remove(voice)
        XCTAssertFalse(downloader.isInstalled(voice))
    }

    func testWrongChecksumInstallsNothingAndDeletesTheFile() async throws {
        let (archive, _) = try makeArchive()
        var fetched: URL?
        let downloader = ModelDownloader(store: store, fetch: { url, progress in
            let file = try await self.fetchCopy(of: archive)(url, progress)
            fetched = file
            return file
        }, availableSpace: { _ in .max })
        let voice = voice(sha256: String(repeating: "0", count: 64))

        do {
            try await downloader.install(voice)
            XCTFail("en forkert kontrolsum skal afvises")
        } catch {
            XCTAssertEqual(error as? ModelDownloader.DownloadError, .checksumMismatch)
        }
        XCTAssertFalse(downloader.isInstalled(voice))
        XCTAssertEqual(leftovers(), [], "der må ikke ligge noget tilbage efter en forkert fil")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fetched!.path), "den hentede fil skal slettes")
    }

    func testInterruptedDownloadLeavesNothingAndCanBeRetried() async throws {
        let (archive, sha) = try makeArchive()
        var failNext = true
        let downloader = ModelDownloader(store: store, fetch: { url, progress in
            progress(0.4)
            if failNext {
                failNext = false
                throw URLError(.networkConnectionLost)
            }
            return try await self.fetchCopy(of: archive)(url, progress)
        }, availableSpace: { _ in .max })
        let voice = voice(sha256: sha)

        downloader.download(voice)
        await waitUntil { downloader.progress[voice.id] == nil && downloader.errors[voice.id] != nil }
        XCTAssertEqual(downloader.errors[voice.id], "Stemmen kunne ikke hentes. Tjek internetforbindelsen, og prøv igen.")
        XCTAssertFalse(downloader.isInstalled(voice))
        XCTAssertEqual(leftovers(), [])

        // Prøv igen: samme knap, nu lykkes det, og fejlbeskeden forsvinder.
        downloader.download(voice)
        await waitUntil { downloader.progress[voice.id] == nil && downloader.isInstalled(voice) }
        XCTAssertNil(downloader.errors[voice.id])
        XCTAssertEqual(leftovers(), ["test-voice"])
    }

    func testNotEnoughSpaceStopsBeforeDownloading() async throws {
        var fetchCalled = false
        let downloader = ModelDownloader(store: store, fetch: { _, _ in
            fetchCalled = true
            throw URLError(.cancelled)
        }, availableSpace: { _ in 50_000_000 })
        let voice = voice(sha256: "x", sizeMB: 67)

        do {
            try await downloader.install(voice)
            XCTFail("for lidt plads skal afvises")
        } catch {
            XCTAssertEqual(error as? ModelDownloader.DownloadError, .notEnoughSpace(neededMB: 201))
        }
        XCTAssertFalse(fetchCalled, "der må ikke hentes noget, når pladsen ikke rækker")
        XCTAssertEqual(ModelDownloader.message(for: ModelDownloader.DownloadError.notEnoughSpace(neededMB: 201)),
                       "Der er ikke plads nok på din Mac. Stemmen kræver ca. 201 MB ledig plads.")
    }

    func testLeftoverFromCrashedInstallIsCleanedUp() async throws {
        let (archive, sha) = try makeArchive()
        let stale = store.directory.appendingPathComponent(".staging-old-voice", isDirectory: true)
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        let downloader = ModelDownloader(store: store, fetch: fetchCopy(of: archive), availableSpace: { _ in .max })
        try await downloader.install(voice(sha256: sha))
        XCTAssertEqual(leftovers(), ["test-voice"])
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<400 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Tidsfrist overskredet")
    }
}
