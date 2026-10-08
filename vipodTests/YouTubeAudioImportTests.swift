import XCTest
@testable import vipod

final class YouTubeAudioImportTests: XCTestCase {
    func testAcceptsOnlySupportedPublicSingleVideoURLs() {
        XCTAssertEqual(YouTubeVideoURL("https://www.youtube.com/watch?v=abcdefghijk")?.videoID, "abcdefghijk")
        XCTAssertEqual(YouTubeVideoURL("https://youtu.be/abcdefghijk?t=10")?.videoID, "abcdefghijk")
        XCTAssertEqual(YouTubeVideoURL("https://m.youtube.com/watch?v=abcdefghijk")?.videoID, "abcdefghijk")

        XCTAssertNil(YouTubeVideoURL("http://www.youtube.com/watch?v=abcdefghijk"))
        XCTAssertNil(YouTubeVideoURL("https://youtube.com.evil.test/watch?v=abcdefghijk"))
        XCTAssertNil(YouTubeVideoURL("https://youtube.com/watch?v=abcdefghijk&list=PL123"))
        XCTAssertNil(YouTubeVideoURL("https://youtu.be/abcdefghijk?list=PL123"))
        XCTAssertNil(YouTubeVideoURL("https://www.youtube.com/playlist?list=PL123"))
        XCTAssertNil(YouTubeVideoURL("https://www.youtube.com/shorts/abcdefghijk"))
        XCTAssertNil(YouTubeVideoURL("https://user@youtube.com/watch?v=abcdefghijk"))
        XCTAssertNil(YouTubeVideoURL("https://www.youtube.com/watch?v=short"))
    }

    func testChoosesHighestBitrateDirectHTTPSAACAndRejectsIncompatibleFormats() throws {
        let formats = [
            format("webm", extension: "webm", protocol: "https", audio: "opus", video: "none", bitrate: 256),
            format("video", extension: "mp4", protocol: "https", audio: "mp4a.40.2", video: "avc1.4d401f", bitrate: 900),
            format("manifest", extension: "m4a", protocol: "m3u8_native", audio: "mp4a.40.2", video: "none", bitrate: 256),
            format("insecure", extension: "m4a", protocol: "https", audio: "mp4a.40.2", video: "none", bitrate: 320, scheme: "http"),
            format("aac-low", extension: "m4a", protocol: "https", audio: "mp4a.40.2", video: "none", bitrate: 128),
            format("aac-high", extension: "m4a", protocol: "https", audio: "mp4a.40.2", video: "none", bitrate: 256)
        ]

        XCTAssertEqual(YouTubeAudioFormat.best(from: formats)?.formatID, "aac-high")
        XCTAssertNil(YouTubeAudioFormat.best(from: Array(formats.prefix(4))))
    }

    func testExtractionMetadataSkipsFormatsWithMissingOptionalFields() throws {
        let json = #"{"id":"abcdefghijk","title":"Example","isLive":false,"formats":[{"formatID":"image","extension":"jpg","protocol":"https","audioCodec":null,"videoCodec":null,"url":"https://cdn.example.test/image"},{"formatID":"audio","extension":"m4a","protocol":"https","audioCodec":"mp4a.40.2","videoCodec":"none","url":"https://cdn.example.test/audio","httpHeaders":{},"bitrate":128}],"webkitJSCChallengeCalls":1,"webkitJSCChallengeSuccesses":1}"#
        let extraction = try JSONDecoder().decode(YouTubeExtraction.self, from: Data(json.utf8))
        let formats = extraction.formats.compactMap(\.directAudioFormat)

        XCTAssertEqual(formats.map(\.formatID), ["audio"])
        XCTAssertEqual(YouTubeAudioFormat.best(from: formats)?.formatID, "audio")
    }

    func testExpiredSignedURLGetsExactlyOneFreshExtraction() {
        XCTAssertTrue(YouTubeSignedURLRetryPolicy.shouldReextract(statusCode: 401, attempt: 0))
        XCTAssertTrue(YouTubeSignedURLRetryPolicy.shouldReextract(statusCode: 403, attempt: 0))
        XCTAssertFalse(YouTubeSignedURLRetryPolicy.shouldReextract(statusCode: 403, attempt: 1))
        XCTAssertFalse(YouTubeSignedURLRetryPolicy.shouldReextract(statusCode: 404, attempt: 0))
        XCTAssertFalse(YouTubeSignedURLRetryPolicy.shouldReextract(statusCode: 500, attempt: 0))
    }

    func testM4AContainerProbeRequiresAnFTYPBoxHeader() {
        XCTAssertTrue(YouTubeAudioContainer.hasM4AFileType(Data([0, 0, 0, 24, 0x66, 0x74, 0x79, 0x70])))
        XCTAssertFalse(YouTubeAudioContainer.hasM4AFileType(Data([0, 0, 0, 24, 0x6D, 0x6F, 0x6F, 0x76])))
        XCTAssertFalse(YouTubeAudioContainer.hasM4AFileType(Data([0, 0, 0, 4])))
    }

    func testTemporaryFileScopeRemovesURLSessionFilesWhenValidationOrMoveFails() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vipod-youtube-cleanup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let downloaded = root.appendingPathComponent("urlsession-download.tmp")
        let invalidContainer = Data("not an audio container".utf8)
        XCTAssertFalse(YouTubeAudioContainer.hasM4AFileType(invalidContainer))
        try invalidContainer.write(to: downloaded)
        var scope = YouTubeTemporaryFileScope()
        scope.track(root)
        scope.track(downloaded)

        XCTAssertThrowsError(try scope.move(downloaded, to: root.appendingPathComponent("missing/title.m4a")))
        scope.cleanup()

        XCTAssertFalse(FileManager.default.fileExists(atPath: downloaded.path), "The download stays owned until a successful move and is deleted on failure.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path), "The per-job directory is removed on every exit path.")
    }

    func testTemporaryFileScopeCleansDownloadedAndRenamedFilesAfterFailures() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("youtube-cleanup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let downloaded = root.appendingPathComponent("urlsession-download.tmp")
        try Data("payload".utf8).write(to: downloaded)
        var scope = YouTubeTemporaryFileScope()
        scope.track(downloaded)
        XCTAssertThrowsError(try scope.move(downloaded, to: root.appendingPathComponent("missing/title.m4a")))
        scope.cleanup()
        XCTAssertFalse(FileManager.default.fileExists(atPath: downloaded.path), "A failed move must leave the source registered for cleanup.")

        let secondDownload = root.appendingPathComponent("refreshed-download.tmp")
        try Data("payload".utf8).write(to: secondDownload)
        let jobDirectory = root.appendingPathComponent("job", isDirectory: true)
        try FileManager.default.createDirectory(at: jobDirectory, withIntermediateDirectories: false)
        let titleDerivedFile = jobDirectory.appendingPathComponent("Example Title.m4a")
        scope.track(secondDownload)
        scope.track(jobDirectory)
        try scope.move(secondDownload, to: titleDerivedFile)

        scope.cleanup()

        XCTAssertFalse(FileManager.default.fileExists(atPath: titleDerivedFile.path), "Cancellation or validation failure must remove the title-derived temporary audio.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: jobDirectory.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondDownload.path))
    }

    private func format(
        _ id: String,
        extension ext: String,
        protocol protocolName: String,
        audio: String,
        video: String,
        bitrate: Double,
        scheme: String = "https"
    ) -> YouTubeAudioFormat {
        YouTubeAudioFormat(
            formatID: id,
            extensionName: ext,
            protocolName: protocolName,
            audioCodec: audio,
            videoCodec: video,
            url: URL(string: "\(scheme)://cdn.example.test/audio")!,
            httpHeaders: [:],
            filesize: nil,
            bitrate: bitrate
        )
    }
}
