import AVFoundation
import AudioToolbox
import Foundation
import ImageIO

/// The metadata snapshot that will be embedded in the downloaded audio file.
/// Nil optional values are intentionally omitted from the output container.
nonisolated struct YouTubeEffectiveMetadata: Equatable, Sendable {
    var title: String
    var artist: String?
    var album: String?
    var albumArtist: String?
    var releaseDate: String?
    var genre: String?
    var trackNumber: Int?
    var discNumber: Int?
    var trackNumberTotal: Int?
    var discNumberTotal: Int?

    init(
        title: String?, videoTitle: String,
        artist: String? = nil, album: String? = nil, albumArtist: String? = nil,
        releaseDate: String? = nil, genre: String? = nil,
        trackNumber: Int? = nil, discNumber: Int? = nil,
        trackNumberTotal: Int? = nil, discNumberTotal: Int? = nil
    ) {
        self.title = Self.normalized(title) ?? Self.normalized(videoTitle) ?? "Untitled"
        self.artist = Self.normalized(artist)
        self.album = Self.normalized(album)
        self.albumArtist = Self.normalized(albumArtist)
        self.releaseDate = Self.normalized(releaseDate)
        self.genre = Self.normalized(genre)
        self.trackNumber = trackNumber.flatMap { $0 > 0 ? $0 : nil }
        self.discNumber = discNumber.flatMap { $0 > 0 ? $0 : nil }
        self.trackNumberTotal = trackNumberTotal.flatMap { $0 > 0 ? $0 : nil }
        self.discNumberTotal = discNumberTotal.flatMap { $0 > 0 ? $0 : nil }
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

/// Writes tags into a newly owned temporary M4A without changing the audio codec.
/// On success the caller owns `outputURL` and must move or remove it. On every error,
/// including cancellation, this writer removes its partial output.
struct YouTubeM4AMetadataWriter {
    enum WriterError: Error {
        case invalidSource
        case invalidArtwork
        case exportUnavailable
        case exportFailed(String)
        case verificationFailed(String)
    }

    static func isPassthroughCompatibleAAC(sourceURL: URL) async throws -> Bool {
        let audioFile = try AVAudioFile(forReading: sourceURL)
        return isPassthroughCompatibleAAC(formatID: audioFile.fileFormat.streamDescription.pointee.mFormatID)
    }

    static func isPassthroughCompatibleAAC(formatID: AudioFormatID) -> Bool {
        // The output verification contract requires AAC-LC. HE-AAC and HE-AAC v2
        // have separate format IDs, so reject them instead of silently changing profiles.
        formatID == kAudioFormatMPEG4AAC
    }

    func write(
        sourceURL: URL,
        metadata: YouTubeEffectiveMetadata,
        artwork: Data? = nil,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) async throws -> URL {
        let outputURL = temporaryDirectory.appendingPathComponent("vipod-tagged-\(UUID().uuidString).m4a")
        do {
            guard sourceURL.pathExtension.lowercased() == "m4a",
                  FileManager.default.fileExists(atPath: sourceURL.path) else { throw WriterError.invalidSource }
            if let artwork { try Self.validateArtwork(artwork) }
            let asset = AVURLAsset(url: sourceURL)
            let playable: Bool
            let tracks: [AVAssetTrack]
            do {
                playable = try await asset.load(.isPlayable)
                tracks = try await asset.load(.tracks)
            } catch {
                throw WriterError.invalidSource
            }
            guard playable, tracks.contains(where: { $0.mediaType == .audio }) else { throw WriterError.invalidSource }
            guard try await Self.isPassthroughCompatibleAAC(sourceURL: sourceURL) else { throw WriterError.invalidSource }
            let sourceAudioDuration: Double
            do { sourceAudioDuration = try Self.decodedAudioDuration(sourceURL) }
            catch { throw WriterError.invalidSource }
            guard sourceAudioDuration.isFinite, sourceAudioDuration > 0 else { throw WriterError.invalidSource }
            guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
                throw WriterError.exportUnavailable
            }
            let supportedTypes = await withCheckedContinuation { continuation in
                exporter.determineCompatibleFileTypes { continuation.resume(returning: $0) }
            }
            guard supportedTypes.contains(.m4a) else { throw WriterError.exportUnavailable }
            exporter.outputURL = outputURL
            exporter.outputFileType = .m4a
            exporter.metadata = Self.makeMetadata(metadata, artwork: artwork)
            try await Self.export(exporter)
            try await Self.verify(outputURL, expected: metadata, artwork: artwork, sourceDuration: sourceAudioDuration)
            return outputURL
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    private static func makeMetadata(_ values: YouTubeEffectiveMetadata, artwork: Data?) -> [AVMetadataItem] {
        var items: [AVMetadataItem] = []
        func add(_ identifier: AVMetadataIdentifier, _ value: Any, dataType: String? = nil) {
            let item = AVMutableMetadataItem()
            item.identifier = identifier
            item.value = value as? (NSCopying & NSObjectProtocol)
            item.dataType = dataType
            items.append(item)
        }
        add(.commonIdentifierTitle, values.title)
        if let value = values.artist { add(.iTunesMetadataArtist, value) }
        if let value = values.album { add(.iTunesMetadataAlbum, value) }
        if let value = values.albumArtist { add(.iTunesMetadataAlbumArtist, value) }
        if let value = values.releaseDate { add(.iTunesMetadataReleaseDate, value) }
        if let value = values.genre { add(.iTunesMetadataUserGenre, value) }
        if let value = values.trackNumber {
            if let total = values.trackNumberTotal {
                add(.iTunesMetadataTrackNumber, "\(value)/\(total)", dataType: kCMMetadataBaseDataType_UTF8 as String)
            } else {
                add(.iTunesMetadataTrackNumber, NSNumber(value: value), dataType: kCMMetadataBaseDataType_SInt64 as String)
            }
        }
        if let value = values.discNumber {
            if let total = values.discNumberTotal {
                add(.iTunesMetadataDiscNumber, "\(value)/\(total)", dataType: kCMMetadataBaseDataType_UTF8 as String)
            } else {
                add(.iTunesMetadataDiscNumber, NSNumber(value: value), dataType: kCMMetadataBaseDataType_SInt64 as String)
            }
        }
        if let artwork {
            add(.iTunesMetadataCoverArt, artwork, dataType: Self.imageDataType(for: artwork)!)
        }
        return items
    }

    private static func export(_ exporter: AVAssetExportSession) async throws {
        guard let outputURL = exporter.outputURL, let fileType = exporter.outputFileType else {
            throw WriterError.exportUnavailable
        }
        let cancellation = ExportSessionCancellation(exporter)
        try await withTaskCancellationHandler {
            try await exporter.export(to: outputURL, as: fileType)
        } onCancel: {
            cancellation.cancel()
        }
    }

    private static func verify(_ url: URL, expected: YouTubeEffectiveMetadata, artwork: Data?, sourceDuration: Double) async throws {
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isPlayable), url.pathExtension == "m4a" else {
            throw WriterError.verificationFailed("Output is not playable M4A")
        }
        let audioTracks = try await asset.load(.tracks).filter { $0.mediaType == .audio }
        var descriptions: [CMFormatDescription] = []
        for track in audioTracks { descriptions.append(contentsOf: try await track.load(.formatDescriptions)) }
        guard descriptions.contains(where: { CMFormatDescriptionGetMediaSubType($0) == kAudioFormatMPEG4AAC }) else {
            throw WriterError.verificationFailed("Output codec is not AAC")
        }
        guard try await isPassthroughCompatibleAAC(sourceURL: url) else {
            throw WriterError.verificationFailed("Output AAC profile changed")
        }
        let outputDuration: Double
        do { outputDuration = try decodedAudioDuration(url) }
        catch { throw WriterError.verificationFailed("Output AAC frame duration unavailable") }
        let durationDelta = abs(outputDuration - sourceDuration)
        guard durationDelta < 0.05 else {
            throw WriterError.verificationFailed(
                "Decoded AAC duration changed (source \(sourceDuration)s, output \(outputDuration)s, delta \(durationDelta)s)"
            )
        }
        let metadata = try await asset.load(.metadata)
        func value(_ identifier: AVMetadataIdentifier) -> AVMetadataItem? {
            metadata.first {
                $0.identifier == identifier || (identifier == .commonIdentifierTitle && $0.commonKey == .commonKeyTitle)
            }
        }
        func checkString(_ identifier: AVMetadataIdentifier, _ expected: String?) async throws {
            guard let expected else { return }
            guard let item = value(identifier), try await item.load(.stringValue) == expected else {
                throw WriterError.verificationFailed("Metadata mismatch: \(identifier.rawValue)")
            }
        }
        try await checkString(.commonIdentifierTitle, expected.title)
        try await checkString(.iTunesMetadataArtist, expected.artist)
        try await checkString(.iTunesMetadataAlbum, expected.album)
        try await checkString(.iTunesMetadataAlbumArtist, expected.albumArtist)
        try await checkString(.iTunesMetadataReleaseDate, expected.releaseDate)
        try await checkString(.iTunesMetadataUserGenre, expected.genre)
        for (identifier, number, total) in [
            (AVMetadataIdentifier.iTunesMetadataTrackNumber, expected.trackNumber, expected.trackNumberTotal),
            (.iTunesMetadataDiscNumber, expected.discNumber, expected.discNumberTotal)
        ] {
            if let number {
                guard let item = value(identifier) else { throw WriterError.verificationFailed("Numeric metadata missing: \(identifier.rawValue)") }
                let numericValue = try? await item.load(.numberValue)
                let stringValue = try? await item.load(.stringValue)
                if let total {
                    guard stringValue == "\(number)/\(total)" else {
                        throw WriterError.verificationFailed("Ordinal metadata mismatch: \(identifier.rawValue)")
                    }
                } else if numericValue?.intValue != number && stringValue.flatMap(Int.init) != number {
                    throw WriterError.verificationFailed("Numeric metadata mismatch: \(identifier.rawValue)")
                }
            }
        }
        if let artwork {
            guard let item = value(.iTunesMetadataCoverArt), try await item.load(.dataValue) == artwork else {
                throw WriterError.verificationFailed("Artwork mismatch")
            }
        }
    }

    private static func validateArtwork(_ data: Data) throws {
        guard !data.isEmpty, imageDataType(for: data) != nil,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else { throw WriterError.invalidArtwork }
    }

    private static func imageDataType(for data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) else { return nil }
        return type as String
    }

    private static func decodedAudioDuration(_ url: URL) throws -> Double {
        let audioFile = try AVAudioFile(forReading: url)
        let sampleRate = audioFile.processingFormat.sampleRate
        guard audioFile.length > 0, sampleRate.isFinite, sampleRate > 0 else {
            throw WriterError.invalidSource
        }
        return Double(audioFile.length) / sampleRate
    }
}

nonisolated private final class ExportSessionCancellation: @unchecked Sendable {
    private let exporter: AVAssetExportSession
    init(_ exporter: AVAssetExportSession) { self.exporter = exporter }
    func cancel() { exporter.cancelExport() }
}
