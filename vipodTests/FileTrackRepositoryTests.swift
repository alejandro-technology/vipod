import AVFoundation
import XCTest
@testable import vipod

final class FileTrackRepositoryTests: XCTestCase {
    func testSyntheticMP3ImportPersistsMetadataAndResolvesOwnedFile() async throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "VIPOD-TestTone", withExtension: "mp3"))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let repository = try FileTrackRepository(storageURL: root)
        let report = try await repository.importTracks(from: [fixture])
        XCTAssertEqual(report.imported.count, 1)
        XCTAssertTrue(report.failures.isEmpty)
        let imported = try XCTUnwrap(report.imported.first)
        XCTAssertEqual(imported.title, "VIPOD Test Tone")
        XCTAssertEqual(imported.artist, "VIPOD Test Suite")
        XCTAssertEqual(imported.album, "Synthetic Fixtures")
        let importedURL = try await repository.mediaURL(for: imported)
        XCTAssertEqual(importedURL.deletingLastPathComponent().lastPathComponent, "Audio")

        let reloaded = try FileTrackRepository(storageURL: root)
        let persisted = try await reloaded.tracks()
        XCTAssertEqual(persisted, [imported])
        let audioURL = try await reloaded.mediaURL(for: imported)
        let player = try AVAudioPlayer(contentsOf: audioURL)
        XCTAssertGreaterThan(player.duration, 0.8)
        XCTAssertLessThan(player.duration, 1.3)
        player.currentTime = 0.4
        XCTAssertEqual(player.currentTime, 0.4, accuracy: 0.01)
    }

    func testLegacyCatalogEnrichmentPersistsTagsWithoutChangingTrackOrAudioIdentity() async throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "VIPOD-TestTone", withExtension: "mp3"))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let audioDirectory = root.appendingPathComponent("Audio", isDirectory: true)
        let artworkDirectory = root.appendingPathComponent("Artwork", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: artworkDirectory, withIntermediateDirectories: true)
        let audioName = "stable-audio.mp3"
        let audioURL = audioDirectory.appendingPathComponent(audioName)
        try makeTaggedMP3(from: fixture).write(to: audioURL)
        let artworkName = "stable-artwork.jpg"
        try Data([0xFF, 0xD8, 0xFF]).write(to: artworkDirectory.appendingPathComponent(artworkName))
        let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let legacyJSON = """
        [{"id":"\(id.uuidString)","title":"Legacy Title","artist":"Fixture Performer","album":"Fixture Album","audioFilename":"\(audioName)","artworkFilename":"\(artworkName)"}]
        """.data(using: .utf8)!
        try legacyJSON.write(to: root.appendingPathComponent("tracks.json"))
        let originalAudio = try Data(contentsOf: audioURL)

        let migrated = try await FileTrackRepository(storageURL: root).tracks()
        let persisted = try await FileTrackRepository(storageURL: root).tracks()
        let track = try XCTUnwrap(persisted.first)

        XCTAssertEqual(track.id, id)
        XCTAssertEqual(track.audioFilename, audioName)
        XCTAssertEqual(track.artworkFilename, artworkName)
        XCTAssertEqual(track.title, "Legacy Title")
        XCTAssertEqual(track.artist, "Fixture Performer")
        XCTAssertEqual(track.albumArtist, "Fixture Album Artist")
        XCTAssertEqual(track.trackNumber, 2)
        XCTAssertEqual(track.discNumber, 1)
        XCTAssertEqual(migrated.first?.id, id)
        XCTAssertEqual(try Data(contentsOf: audioURL), originalAudio)
    }

    func testDecodedNonpositiveTrackAndDiscNumbersAreDiscarded() throws {
        let json = """
        [{"id":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","title":"Song","artist":"Artist","album":"Album","trackNumber":0,"discNumber":-3,"audioFilename":"stable.mp3"}]
        """.data(using: .utf8)!
        let track = try XCTUnwrap(JSONDecoder().decode([Track].self, from: json).first)
        XCTAssertNil(track.trackNumber)
        XCTAssertNil(track.discNumber)
    }

    private func makeTaggedMP3(from fixture: URL) throws -> Data {
        let payload = try Data(contentsOf: fixture)
        let audioStart: Int
        if payload.count >= 10, payload[0] == 0x49, payload[1] == 0x44, payload[2] == 0x33 {
            let existingTagSize = (Int(payload[6] & 0x7F) << 21) | (Int(payload[7] & 0x7F) << 14) | (Int(payload[8] & 0x7F) << 7) | Int(payload[9] & 0x7F)
            audioStart = min(payload.count, 10 + existingTagSize)
        } else {
            audioStart = 0
        }
        func frame(_ id: String, _ text: String) -> Data {
            let body = Data([0]) + Data(text.utf8)
            var frameData = Data(id.utf8)
            frameData.append(contentsOf: [UInt8((body.count >> 24) & 0xFF), UInt8((body.count >> 16) & 0xFF), UInt8((body.count >> 8) & 0xFF), UInt8(body.count & 0xFF), 0, 0])
            frameData.append(body)
            return frameData
        }
        var frames = Data()
        frames.append(frame("TIT2", "Fixture Song"))
        frames.append(frame("TPE1", "Fixture Performer"))
        frames.append(frame("TALB", "Fixture Album"))
        frames.append(frame("TPE2", "Fixture Album Artist"))
        frames.append(frame("TRCK", "2/12"))
        frames.append(frame("TPOS", "1/2"))
        let size = frames.count
        var tag = Data([0x49, 0x44, 0x33, 3, 0, 0,
                        UInt8((size >> 21) & 0x7F), UInt8((size >> 14) & 0x7F),
                        UInt8((size >> 7) & 0x7F), UInt8(size & 0x7F)])
        tag.append(frames)
        tag.append(payload.dropFirst(audioStart))
        return tag
    }

    func testImportReportsBadFileAndContinuesWithValidFixture() async throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "VIPOD-TestTone", withExtension: "mp3"))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let broken = root.appendingPathComponent("broken.mp3")
        try Data("not audio".utf8).write(to: broken)

        let repository = try FileTrackRepository(storageURL: root.appendingPathComponent("library", isDirectory: true))
        let report = try await repository.importTracks(from: [broken, fixture])
        XCTAssertEqual(report.imported.count, 1)
        XCTAssertEqual(report.failures.map(\.filename), ["broken.mp3"])
        let savedTracks = try await repository.tracks()
        XCTAssertEqual(savedTracks.count, 1)
    }

    func testImportingSameSyntheticMP3TwicePersistsOneTrackAndReportsDuplicate() async throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "VIPOD-TestTone", withExtension: "mp3"))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try FileTrackRepository(storageURL: root)

        let report = try await repository.importTracks(from: [fixture, fixture])

        XCTAssertEqual(report.imported.count, 1)
        XCTAssertEqual(report.failures.map(\.filename), [fixture.lastPathComponent])
        let reloaded = try FileTrackRepository(storageURL: root)
        let persistedTracks = try await reloaded.tracks()
        XCTAssertEqual(persistedTracks.count, 1)
        XCTAssertEqual(persistedTracks.first?.id, report.imported.first?.id)
    }

    func testRemovingImportedTrackPreservesSourceAndAllowsReimport() async throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "VIPOD-TestTone", withExtension: "mp3"))
        let remainingFixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "VIPOD-ArtworkTone", withExtension: "m4a"))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceDirectory = root.appendingPathComponent("Source", isDirectory: true)
        let libraryDirectory = root.appendingPathComponent("Library", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        let sourceURL = sourceDirectory.appendingPathComponent(fixture.lastPathComponent)
        let remainingSourceURL = sourceDirectory.appendingPathComponent(remainingFixture.lastPathComponent)
        try FileManager.default.copyItem(at: fixture, to: sourceURL)
        try FileManager.default.copyItem(at: remainingFixture, to: remainingSourceURL)
        let sourceBytes = try Data(contentsOf: sourceURL)

        let repository = try FileTrackRepository(storageURL: libraryDirectory)
        let report = try await repository.importTracks(from: [sourceURL, remainingSourceURL])
        XCTAssertEqual(report.imported.count, 2)
        XCTAssertTrue(report.failures.isEmpty)
        let imported = try XCTUnwrap(report.imported.first { $0.audioFilename.hasSuffix(".mp3") })
        let remaining = try XCTUnwrap(report.imported.first { $0.audioFilename.hasSuffix(".m4a") })
        let ownedAudioURL = try await repository.mediaURL(for: imported)
        let remainingAudioURL = try await repository.mediaURL(for: remaining)
        XCTAssertNotEqual(ownedAudioURL.standardizedFileURL, sourceURL.standardizedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: ownedAudioURL.path))

        try await repository.removeTrack(id: imported.id)

        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceBytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ownedAudioURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: remainingAudioURL.path))
        let reloaded = try FileTrackRepository(storageURL: libraryDirectory)
        let tracksAfterRemoval = try await reloaded.tracks()
        XCTAssertEqual(tracksAfterRemoval, [remaining])

        let reimport = try await reloaded.importTracks(from: [sourceURL])
        XCTAssertEqual(reimport.imported.count, 1)
        XCTAssertTrue(reimport.failures.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceBytes)
        let tracksAfterReimport = try await FileTrackRepository(storageURL: libraryDirectory).tracks()
        XCTAssertEqual(Set(tracksAfterReimport), Set([remaining] + reimport.imported))
        XCTAssertTrue(FileManager.default.fileExists(atPath: remainingAudioURL.path))
    }

    func testRemovalCatalogWriteFailurePreservesSourceOwnedAudioAndLibraryRecords() async throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "VIPOD-TestTone", withExtension: "mp3"))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceDirectory = root.appendingPathComponent("Source", isDirectory: true)
        let libraryDirectory = root.appendingPathComponent("Library", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        let sourceURL = sourceDirectory.appendingPathComponent(fixture.lastPathComponent)
        try FileManager.default.copyItem(at: fixture, to: sourceURL)
        let sourceBytes = try Data(contentsOf: sourceURL)

        let repository = try FileTrackRepository(storageURL: libraryDirectory)
        let report = try await repository.importTracks(from: [sourceURL])
        let imported = try XCTUnwrap(report.imported.first)
        let ownedAudioURL = try await repository.mediaURL(for: imported)
        let catalogURL = libraryDirectory.appendingPathComponent("tracks.json")
        let catalogBytes = try Data(contentsOf: catalogURL)

        try FileManager.default.removeItem(at: catalogURL)
        try FileManager.default.createDirectory(at: catalogURL, withIntermediateDirectories: false)
        do {
            try await repository.removeTrack(id: imported.id)
            XCTFail("Expected catalog persistence to fail")
        } catch let error as RepositoryError {
            guard case .catalogFailure = error else {
                return XCTFail("Expected a catalog failure, received \(error)")
            }
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceBytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: ownedAudioURL.path))
        let cachedTracksAfterFailure = try await repository.tracks()
        XCTAssertEqual(cachedTracksAfterFailure, [imported])

        try FileManager.default.removeItem(at: catalogURL)
        try catalogBytes.write(to: catalogURL, options: .atomic)
        let reloaded = try FileTrackRepository(storageURL: libraryDirectory)
        let tracksAfterReload = try await reloaded.tracks()
        XCTAssertEqual(tracksAfterReload, [imported])
        XCTAssertTrue(FileManager.default.fileExists(atPath: ownedAudioURL.path))
    }

    func testStaticMediaURLResolverRejectsParentDirectoryTraversal() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let malicious = Track(title: "Outside", audioFilename: "../outside.mp3")

        XCTAssertThrowsError(try FileTrackRepository.resolveMediaURL(for: malicious, in: root)) { error in
            guard let repositoryError = error as? RepositoryError else {
                return XCTFail("Expected an invalid catalog error, received \(error)")
            }
            if case .invalidCatalog = repositoryError { return }
            XCTFail("Expected an invalid catalog error")
        }
    }
}
