import Foundation
import Testing
@testable import PenumbraSystem

@MainActor
final class ApplierHarness {
    let directory = FileManager.default.temporaryDirectory.appending(path: "penumbra-applier-\(UUID())")
    var storeURL: URL { directory.appending(path: "Index.plist") }
    var backupURL: URL { directory.appending(path: "Backups/Index.plist") }
    var restarts = 0
    var publicAPICalls: [URL] = []
    /// When false, the agent never reports the new image.
    var agentAccepts = true
    var reported: URL?

    init() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func makeApplier() -> WallpaperApplier {
        var environment = WallpaperApplier.Environment(
            storeURL: storeURL,
            backupURL: backupURL,
            restartAgent: { [unowned self] in
                restarts += 1
                if agentAccepts, let data = try? Data(contentsOf: storeURL) {
                    reported = try? WallpaperStoreEditor.imageURL(in: data)
                }
            },
            currentImageURL: { [unowned self] in reported },
            setWithPublicAPI: { [unowned self] in publicAPICalls.append($0) }
        )
        environment.checkAttempts = 2
        environment.checkInterval = .milliseconds(1)
        return WallpaperApplier(environment: environment)
    }
}

@MainActor
@Suite struct WallpaperApplierTests {
    let target = URL(fileURLWithPath: "/tmp/new.png")

    @Test func writesTheStoreRestartsAndBacksUp() async throws {
        let h = try ApplierHarness()
        let original = try makeStoreData()
        try original.write(to: h.storeURL)

        try await h.makeApplier().apply(target)

        #expect(h.restarts == 1)
        #expect(h.publicAPICalls.isEmpty)
        #expect(try WallpaperStoreEditor.imageURL(in: Data(contentsOf: h.storeURL)) == target)
        #expect(try Data(contentsOf: h.backupURL) == original)
    }

    @Test func doesNothingWhenAlreadySet() async throws {
        let h = try ApplierHarness()
        let original = try makeStoreData(url: target.absoluteString)
        try original.write(to: h.storeURL)

        try await h.makeApplier().apply(target)

        #expect(h.restarts == 0)
        #expect(try Data(contentsOf: h.storeURL) == original)
    }

    @Test func backupKeepsTheFirstStoreOnly() async throws {
        let h = try ApplierHarness()
        let original = try makeStoreData()
        try original.write(to: h.storeURL)

        let applier = h.makeApplier()
        try await applier.apply(target)
        try await applier.apply(URL(fileURLWithPath: "/tmp/second.png"))

        #expect(try Data(contentsOf: h.backupURL) == original)
    }

    @Test func rollsBackAndFallsBackWhenTheWriteDoesntTakeEffect() async throws {
        let h = try ApplierHarness()
        h.agentAccepts = false
        let original = try makeStoreData()
        try original.write(to: h.storeURL)

        try await h.makeApplier().apply(target)

        #expect(h.restarts == 2)
        #expect(try Data(contentsOf: h.storeURL) == original)
        #expect(h.publicAPICalls == [target])
    }

    @Test func usesPublicAPIForAnUnsupportedStoreWithoutTouchingIt() async throws {
        let h = try ApplierHarness()
        let original = try makeStoreData(type: "individual")
        try original.write(to: h.storeURL)

        try await h.makeApplier().apply(target)

        #expect(h.restarts == 0)
        #expect(try Data(contentsOf: h.storeURL) == original)
        #expect(h.publicAPICalls == [target])
    }

    @Test func usesPublicAPIWhenTheStoreIsMissing() async throws {
        let h = try ApplierHarness()
        try await h.makeApplier().apply(target)
        #expect(h.publicAPICalls == [target])
    }
}
