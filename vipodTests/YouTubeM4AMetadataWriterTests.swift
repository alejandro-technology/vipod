import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import vipod

final class YouTubeM4AMetadataWriterTests: XCTestCase {
    func testPassthroughGuardAcceptsOnlyAACLC() {
        XCTAssertTrue(YouTubeM4AMetadataWriter.isPassthroughCompatibleAAC(formatID: kAudioFormatMPEG4AAC))
        XCTAssertFalse(YouTubeM4AMetadataWriter.isPassthroughCompatibleAAC(formatID: kAudioFormatMPEG4AAC_HE))
        XCTAssertFalse(YouTubeM4AMetadataWriter.isPassthroughCompatibleAAC(formatID: kAudioFormatMPEG4AAC_HE_V2))
        XCTAssertFalse(YouTubeM4AMetadataWriter.isPassthroughCompatibleAAC(formatID: kAudioFormatMPEGLayer3))
    }

    func testWritesAndImportsEffectiveMetadataArtworkAndPreservesAAC() async throws {
        let source = try fixture()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let artwork = try makeJPEG()
        let effective = YouTubeEffectiveMetadata(
            title: "  Effective title ", videoTitle: "Video title", artist: "Performer", album: "Record",
            albumArtist: "Band", releaseDate: "2024", genre: "Electronic",
            trackNumber: 7, discNumber: 2, trackNumberTotal: 12, discNumberTotal: 3
        )
        let sourceAsset = AVURLAsset(url: source)
        let sourceDuration = try await sourceAsset.load(.duration).seconds

        let output = try await YouTubeM4AMetadataWriter().write(sourceURL: source, metadata: effective, artwork: artwork, temporaryDirectory: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        let asset = AVURLAsset(url: output)
        let audioTracks = try await asset.load(.tracks).filter { $0.mediaType == .audio }
        let descriptions = try await audioTracks.first?.load(.formatDescriptions) ?? []
        XCTAssertTrue(descriptions.contains { CMFormatDescriptionGetMediaSubType($0) == kAudioFormatMPEG4AAC })
        let outputDuration = try await asset.load(.duration).seconds
        XCTAssertEqual(outputDuration, sourceDuration, accuracy: 0.05)
        let outputMetadata = try await asset.load(.metadata)
        let embeddedTrack = try XCTUnwrap(outputMetadata.first { $0.identifier == .iTunesMetadataTrackNumber })
        let embeddedDisc = try XCTUnwrap(outputMetadata.first { $0.identifier == .iTunesMetadataDiscNumber })
        let embeddedTrackValue = try await embeddedTrack.load(.stringValue)
        let embeddedDiscValue = try await embeddedDisc.load(.stringValue)
        XCTAssertEqual(embeddedTrackValue, "7/12")
        XCTAssertEqual(embeddedDiscValue, "2/3")

        let repository = try FileTrackRepository(storageURL: root.appendingPathComponent("library", isDirectory: true))
        let report = try await repository.importTracks(from: [output])
        let imported = try XCTUnwrap(report.imported.first)
        XCTAssertTrue(report.failures.isEmpty)
        XCTAssertEqual(imported.title, effective.title)
        XCTAssertEqual(imported.artist, effective.artist)
        XCTAssertEqual(imported.album, effective.album)
        XCTAssertEqual(imported.albumArtist, effective.albumArtist)
        XCTAssertEqual(imported.trackNumber, effective.trackNumber)
        XCTAssertEqual(imported.discNumber, effective.discNumber)
        let importedArtwork = try await repository.artworkData(for: imported)
        XCTAssertEqual(importedArtwork, artwork)

        let reloaded = try FileTrackRepository(storageURL: root.appendingPathComponent("library", isDirectory: true))
        let reloadedTracks = try await reloaded.tracks()
        XCTAssertEqual(reloadedTracks, [imported])
        let playerURL = try await reloaded.mediaURL(for: imported)
        let player = try AVAudioPlayer(contentsOf: playerURL)
        XCTAssertGreaterThan(player.duration, 0)
    }

    func testCapturedLiveYouTubeAACAndJPEGRetainDecodedDurationAndTags() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
        let captures = try FileManager.default.contentsOfDirectory(at: temporaryDirectory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("VIPOD-YouTube-Readback-") }
        guard !captures.isEmpty else {
            throw XCTSkip("No bounded live YouTube M4A readback capture is present in this simulator's app temporary directory.")
        }
        var sawPassthroughAAC = false
        for capture in captures {
            defer { try? FileManager.default.removeItem(at: capture) }
            let source = capture.appendingPathComponent("source.m4a")
            let artwork = try Data(contentsOf: capture.appendingPathComponent("artwork.jpg"))
            let snapshot = try JSONDecoder().decode(CapturedMetadata.self, from: Data(contentsOf: capture.appendingPathComponent("effective-tags.json")))
            let metadata = YouTubeEffectiveMetadata(
                title: snapshot.title, videoTitle: snapshot.title, artist: snapshot.artist,
                album: snapshot.album, albumArtist: snapshot.albumArtist,
                releaseDate: snapshot.releaseDate, genre: snapshot.genre
            )
            let sourceAudio = try AVAudioFile(forReading: source)
            let sourceDecodedDuration = Double(sourceAudio.length) / sourceAudio.processingFormat.sampleRate
            let root = temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: root) }

            if try await YouTubeM4AMetadataWriter.isPassthroughCompatibleAAC(sourceURL: source) {
                sawPassthroughAAC = true
                let tagged = try await YouTubeM4AMetadataWriter().write(
                    sourceURL: source, metadata: metadata, artwork: artwork, temporaryDirectory: root
                )
                let taggedAudio = try AVAudioFile(forReading: tagged)
                let taggedDecodedDuration = Double(taggedAudio.length) / taggedAudio.processingFormat.sampleRate
                XCTAssertEqual(taggedDecodedDuration, sourceDecodedDuration, accuracy: 0.05)
            } else {
                do {
                    _ = try await YouTubeM4AMetadataWriter().write(
                        sourceURL: source, metadata: metadata, artwork: artwork, temporaryDirectory: root
                    )
                    XCTFail("HE-AAC must not be silently exported as AAC-LC.")
                } catch YouTubeM4AMetadataWriter.WriterError.invalidSource { }
            }
        }
        XCTAssertTrue(sawPassthroughAAC, "A captured AAC-LC source should retain decoded frame duration and exact JPEG/tags.")
    }

    func testOmitsMissingFieldsAndFallsBackToVideoTitle() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let metadata = YouTubeEffectiveMetadata(title: nil, videoTitle: " Video fallback ", trackNumber: 0, discNumber: -1)
        let output = try await YouTubeM4AMetadataWriter().write(sourceURL: fixture(), metadata: metadata, temporaryDirectory: root)
        let items = try await AVURLAsset(url: output).load(.metadata)
        XCTAssertTrue(items.contains { $0.commonKey == .commonKeyTitle })
        XCTAssertFalse(items.contains { $0.identifier == .iTunesMetadataArtist || $0.identifier == .iTunesMetadataAlbum || $0.identifier == .iTunesMetadataTrackNumber || $0.identifier == .iTunesMetadataDiscNumber })
        XCTAssertEqual(metadata.title, "Video fallback")
        XCTAssertNil(metadata.trackNumber)
        XCTAssertNil(metadata.discNumber)
    }

    func testRejectsInvalidSourceAndArtworkWithoutLeavingOutput() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let badSource = root.appendingPathComponent("bad.m4a")
        try Data("not audio".utf8).write(to: badSource)
        do {
            _ = try await YouTubeM4AMetadataWriter().write(sourceURL: badSource, metadata: .init(title: "Song", videoTitle: "Video"), temporaryDirectory: root)
            XCTFail("Expected invalid source")
        } catch YouTubeM4AMetadataWriter.WriterError.invalidSource { }
        do {
            _ = try await YouTubeM4AMetadataWriter().write(sourceURL: fixture(), metadata: .init(title: "Song", videoTitle: "Video"), artwork: Data([1, 2]), temporaryDirectory: root)
            XCTFail("Expected invalid artwork")
        } catch YouTubeM4AMetadataWriter.WriterError.invalidArtwork { }
        let remaining = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertEqual(remaining, ["bad.m4a"])
    }

    func testPreCancelledTaskDoesNotRetainAnOutput() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let task = Task {
            try Task.checkCancellation()
            return try await YouTubeM4AMetadataWriter().write(sourceURL: fixture(), metadata: .init(title: "Song", videoTitle: "Video"), temporaryDirectory: root)
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError { }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    private func fixture() throws -> URL {
        try XCTUnwrap(Bundle(for: FileTrackRepositoryTests.self).url(forResource: "VIPOD-ArtworkTone", withExtension: "m4a"))
    }

    private struct CapturedMetadata: Decodable {
        let title: String
        var artist: String?
        var album: String?
        var albumArtist: String?
        var releaseDate: String?
        var genre: String?
    }

    private func makeJPEG() throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil),
              let context = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let image = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return data as Data
    }
}
