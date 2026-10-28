import Foundation
import ImageIO
import UniformTypeIdentifiers

#if os(iOS)
@MainActor
final class MusicBrainzClient: YouTubeMusicMetadataSearching {
    typealias Transport = @MainActor (URLRequest) async throws -> (Data, URLResponse)
    typealias Sleep = @MainActor (TimeInterval) async throws -> Void

    private enum CachedValue {
        case recordings([YouTubeMusicRecording])
        case release(YouTubeMusicReleaseDetails)
    }

    private struct CacheEntry {
        let expiresAt: Date
        let value: CachedValue
    }

    private static let maximumResponseBytes = 2 * 1024 * 1024
    private static let maximumArtworkBytes = 8 * 1024 * 1024
    private static let maximumCacheEntries = 24
    private static let cacheLifetime: TimeInterval = 10 * 60
    private static let maximumRetryCount = 2
    private static let userAgent = "VIPOD/1.0 (com.alejandrotechnology.vipod)"

    private let transport: Transport
    private let sleep: Sleep
    private let processing: MusicBrainzProcessing
    private let requestGate: MusicBrainzRequestGate
    private let requestIntervalNanoseconds: UInt64
    private var cache: [String: CacheEntry] = [:]
    private var cacheOrder: [String] = []

    init(
        session: URLSession? = nil,
        minimumRequestInterval: TimeInterval = 1,
        sleep: @escaping Sleep = { seconds in
            try await Task.sleep(for: .seconds(seconds))
        },
        transport: Transport? = nil
    ) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 15
        let requestSession = session ?? URLSession(configuration: configuration)
        let processing = MusicBrainzProcessing()
        self.processing = processing
        self.transport = transport ?? { request in
            let maximumBytes = request.value(forHTTPHeaderField: "Accept") == "application/json"
                ? Self.maximumResponseBytes : Self.maximumArtworkBytes
            return try await processing.load(request, session: requestSession, maximumBytes: maximumBytes)
        }
        self.sleep = sleep
        self.requestGate = MusicBrainzRequestGate()
        self.requestIntervalNanoseconds = UInt64(min(max(0, minimumRequestInterval), 60) * 1_000_000_000)
    }

    func searchRecordings(query: String) async throws -> [YouTubeMusicRecording] {
        guard let expression = YouTubeMusicBrainzQuery.escapedLucenePhrase(query),
              let url = YouTubeMusicBrainzQuery.searchURL(for: query) else {
            throw MusicBrainzClientError.emptyQuery
        }
        let cacheKey = "recording:\(expression)"
        if case .recordings(let recordings)? = cachedValue(for: cacheKey) { return recordings }

        let payload: RecordingSearchResponse = try await decodeResponse(from: url)
        let recordings = Array((payload.recordings ?? []).prefix(10)).compactMap(Self.recording(from:))
        cacheValue(.recordings(recordings), for: cacheKey)
        return recordings
    }

    func loadRelease(id: String) async throws -> YouTubeMusicReleaseDetails {
        guard let identifier = UUID(uuidString: id) else { throw MusicBrainzClientError.invalidIdentifier }
        let releaseID = identifier.uuidString.lowercased()
        let cacheKey = "release:\(releaseID)"
        if case .release(let details)? = cachedValue(for: cacheKey) { return details }

        var components = URLComponents(string: "https://musicbrainz.org/ws/2/release/\(releaseID)")
        components?.queryItems = [
            URLQueryItem(name: "inc", value: "recordings+artists+artist-credits+genres"),
            URLQueryItem(name: "fmt", value: "json")
        ]
        guard let url = components?.url else { throw MusicBrainzClientError.invalidResponse }
        let payload: ReleaseResponse = try await decodeResponse(from: url)
        let details = Self.releaseDetails(from: payload, identifier: releaseID)
        cacheValue(.release(details), for: cacheKey)
        return details
    }

    func artwork(releaseID: String) async throws -> Data? {
        guard let identifier = UUID(uuidString: releaseID) else { throw MusicBrainzClientError.invalidIdentifier }
        guard let url = URL(string: "https://coverartarchive.org/release/\(identifier.uuidString.lowercased())/front-500") else {
            throw MusicBrainzClientError.invalidResponse
        }
        let data = try await requestData(from: url, accept: "image/jpeg, image/png")
        return try await processing.normalizedJPEG(data, maximumBytes: Self.maximumArtworkBytes)
    }

    private func decodeResponse<Value: Decodable & Sendable>(from url: URL) async throws -> Value {
        let data = try await requestData(from: url, accept: "application/json")
        return try await processing.decode(Value.self, from: data)
    }

    private func requestData(from url: URL, accept: String) async throws -> Data {
        for attempt in 0...Self.maximumRetryCount {
            try Task.checkCancellation()
            try await requestGate.waitForTurn(intervalNanoseconds: requestIntervalNanoseconds)
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(accept, forHTTPHeaderField: "Accept")

            do {
                let (data, response) = try await transport(request)
                try Task.checkCancellation()
                guard let http = response as? HTTPURLResponse else { throw MusicBrainzClientError.invalidResponse }
                if !(200..<300).contains(http.statusCode) {
                    guard Self.isTransient(statusCode: http.statusCode), attempt < Self.maximumRetryCount else {
                        throw MusicBrainzClientError.httpStatus(http.statusCode)
                    }
                    try await sleep(TimeInterval(1 << attempt))
                    continue
                }
                if accept != "application/json" {
                    guard let finalURL = http.url,
                          finalURL.scheme?.lowercased() == "https",
                          Self.isCoverArtHost(finalURL.host) else { throw MusicBrainzClientError.invalidResponse }
                    guard data.count <= Self.maximumArtworkBytes else { throw MusicBrainzClientError.responseTooLarge }
                } else {
                    guard data.count <= Self.maximumResponseBytes else { throw MusicBrainzClientError.responseTooLarge }
                }
                return data
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError where error.code == .cancelled {
                throw CancellationError()
            } catch let error as MusicBrainzClientError {
                try Task.checkCancellation()
                if case .httpStatus(let statusCode) = error,
                   Self.isTransient(statusCode: statusCode), attempt < Self.maximumRetryCount {
                    try await sleep(TimeInterval(1 << attempt))
                    continue
                }
                throw error
            } catch {
                try Task.checkCancellation()
                guard Self.isTransient(error), attempt < Self.maximumRetryCount else {
                    throw MusicBrainzClientError.networkUnavailable
                }
                try await sleep(TimeInterval(1 << attempt))
            }
        }
        throw MusicBrainzClientError.networkUnavailable
    }

    private func cachedValue(for key: String) -> CachedValue? {
        guard let entry = cache[key] else { return nil }
        guard entry.expiresAt > Date() else {
            cache.removeValue(forKey: key)
            cacheOrder.removeAll { $0 == key }
            return nil
        }
        return entry.value
    }

    private func cacheValue(_ value: CachedValue, for key: String) {
        cacheOrder.removeAll { $0 == key }
        cache[key] = CacheEntry(expiresAt: Date().addingTimeInterval(Self.cacheLifetime), value: value)
        cacheOrder.append(key)
        while cacheOrder.count > Self.maximumCacheEntries {
            cache.removeValue(forKey: cacheOrder.removeFirst())
        }
    }

    private static func recording(from payload: RecordingPayload) -> YouTubeMusicRecording? {
        guard let id = payload.id, UUID(uuidString: id) != nil,
              let title = normalized(payload.title) else { return nil }
        let releases = Array((payload.releases ?? []).prefix(10)).compactMap { release -> YouTubeMusicReleaseSummary? in
            guard let releaseID = release.id, UUID(uuidString: releaseID) != nil,
                  let releaseTitle = normalized(release.title) else { return nil }
            return YouTubeMusicReleaseSummary(
                id: releaseID.lowercased(), title: releaseTitle,
                artist: credit(release.artistCredit), date: normalized(release.date),
                trackCount: positive(release.trackCount)
            )
        }
        return YouTubeMusicRecording(
            id: id.lowercased(), title: title, artist: credit(payload.artistCredit),
            firstReleaseDate: normalized(payload.firstReleaseDate),
            genre: payload.genres?.compactMap { normalized($0.name) }.first,
            releases: releases
        )
    }

    private static func releaseDetails(from payload: ReleaseResponse, identifier: String) -> YouTubeMusicReleaseDetails {
        let media = payload.media ?? []
        let tracks = media.prefix(20).flatMap { medium -> [YouTubeMusicTrack] in
            let sourceTracks = Array((medium.tracks ?? []).prefix(200))
            return sourceTracks.enumerated().compactMap { index, track in
                guard let title = normalized(track.title) ?? normalized(track.recording?.title) else { return nil }
                let position = positive(track.position) ?? positive(track.number.flatMap { Int($0) }) ?? index + 1
                let recordingID = track.recording?.id?.lowercased()
                let trackID = track.id.flatMap { UUID(uuidString: $0) == nil ? nil : $0.lowercased() }
                    ?? recordingID
                    ?? "\(medium.position ?? 1)-\(position)"
                return YouTubeMusicTrack(
                    id: trackID, title: title,
                    artist: credit(track.recording?.artistCredit),
                    number: position, numberTotal: positive(medium.trackCount) ?? sourceTracks.count,
                    discNumber: positive(medium.position)
                )
            }
        }
        return YouTubeMusicReleaseDetails(
            id: identifier,
            title: normalized(payload.title) ?? "Unknown release",
            artist: credit(payload.artistCredit), date: normalized(payload.date),
            genre: payload.genres?.compactMap { normalized($0.name) }.first,
            discTotal: media.isEmpty ? nil : media.count,
            tracks: Array(tracks.prefix(200))
        )
    }

    private static func credit(_ entries: [ArtistCredit]?) -> String? {
        guard let entries else { return nil }
        let value = entries.map { entry in
            (entry.name ?? entry.artist?.name ?? "") + (entry.joinPhrase ?? "")
        }.joined()
        return normalized(value)
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func positive(_ value: Int?) -> Int? {
        value.flatMap { $0 > 0 ? $0 : nil }
    }

    private static func isTransient(statusCode: Int) -> Bool {
        statusCode == 408 || statusCode == 429 || [500, 502, 503, 504].contains(statusCode)
    }

    private static func isTransient(_ error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return [.timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed].contains(error.code)
    }

    private static func isCoverArtHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "coverartarchive.org" || host == "archive.org" || host.hasSuffix(".archive.org")
    }

    nonisolated private struct RecordingSearchResponse: Decodable, Sendable {
        let recordings: [RecordingPayload]?
    }

    nonisolated private struct RecordingPayload: Decodable, Sendable {
        let id: String?
        let title: String?
        let artistCredit: [ArtistCredit]?
        let firstReleaseDate: String?
        let releases: [ReleaseSummaryPayload]?
        let genres: [GenrePayload]?

        enum CodingKeys: String, CodingKey {
            case id, title, artistCredit = "artist-credit", firstReleaseDate = "first-release-date", releases, genres
        }
    }

    nonisolated private struct ReleaseSummaryPayload: Decodable, Sendable {
        let id: String?
        let title: String?
        let date: String?
        let trackCount: Int?
        let artistCredit: [ArtistCredit]?

        enum CodingKeys: String, CodingKey {
            case id, title, date, trackCount = "track-count", artistCredit = "artist-credit"
        }
    }

    nonisolated private struct ReleaseResponse: Decodable, Sendable {
        let id: String?
        let title: String?
        let date: String?
        let artistCredit: [ArtistCredit]?
        let genres: [GenrePayload]?
        let media: [MediumPayload]?

        enum CodingKeys: String, CodingKey {
            case id, title, date, artistCredit = "artist-credit", genres, media
        }
    }

    nonisolated private struct MediumPayload: Decodable, Sendable {
        let position: Int?
        let trackCount: Int?
        let tracks: [TrackPayload]?

        enum CodingKeys: String, CodingKey {
            case position, tracks, trackCount = "track-count"
        }
    }

    nonisolated private struct TrackPayload: Decodable, Sendable {
        let id: String?
        let title: String?
        let number: String?
        let position: Int?
        let recording: TrackRecordingPayload?
    }

    nonisolated private struct TrackRecordingPayload: Decodable, Sendable {
        let id: String?
        let title: String?
        let artistCredit: [ArtistCredit]?

        enum CodingKeys: String, CodingKey {
            case id, title, artistCredit = "artist-credit"
        }
    }

    nonisolated private struct ArtistCredit: Decodable, Sendable {
        let name: String?
        let joinPhrase: String?
        let artist: ArtistPayload?

        enum CodingKeys: String, CodingKey {
            case name, artist, joinPhrase = "joinphrase"
        }
    }

    nonisolated private struct ArtistPayload: Decodable, Sendable {
        let name: String?
    }

    nonisolated private struct GenrePayload: Decodable, Sendable {
        let name: String?
    }
}

/// Explicit actor hops keep the production transport and CPU-heavy work off MainActor.
actor MusicBrainzProcessing {
    private let bodyCollector = MusicBrainzBoundedBody()

    func load(_ request: URLRequest, session: URLSession, maximumBytes: Int) async throws -> (Data, URLResponse) {
        try Task.checkCancellation()
        let (bytes, response) = try await session.bytes(for: request)
        // Breaking out of AsyncBytes does not itself cancel the underlying task.
        defer { bytes.task.cancel() }
        let data = try await bodyCollector.collect(
            bytes, maximumBytes: maximumBytes, expectedLength: response.expectedContentLength
        )
        return (data, response)
    }

    func decode<Value: Decodable & Sendable>(_ type: Value.Type, from data: Data) throws -> Value {
        try Task.checkCancellation()
        let value: Value
        do { value = try JSONDecoder().decode(type, from: data) }
        catch { throw MusicBrainzClientError.invalidResponse }
        try Task.checkCancellation()
        return value
    }

    func normalizedJPEG(_ data: Data, maximumBytes: Int) throws -> Data {
        try Task.checkCancellation()
        guard data.count <= maximumBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw MusicBrainzClientError.invalidArtwork
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        guard width > 0, height > 0, width <= 20_000, height <= 20_000,
              width.multipliedReportingOverflow(by: height).overflow == false,
              width * height <= 100_000_000 else { throw MusicBrainzClientError.invalidArtwork }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw MusicBrainzClientError.invalidArtwork
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw MusicBrainzClientError.invalidArtwork }
        try Task.checkCancellation()
        return output as Data
    }
}

/// Enforces the cap during consumption, including when Content-Length is absent or incorrect.
actor MusicBrainzBoundedBody {
    func collect<Bytes: AsyncSequence & Sendable>(
        _ bytes: Bytes,
        maximumBytes: Int,
        expectedLength: Int64 = -1
    ) async throws -> Data where Bytes.Element == UInt8 {
        guard expectedLength <= Int64(maximumBytes) else { throw MusicBrainzClientError.responseTooLarge }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximumBytes else { throw MusicBrainzClientError.responseTooLarge }
            data.append(byte)
        }
        return data
    }
}

private actor MusicBrainzRequestGate {
    private var nextAllowedUptimeNanoseconds: UInt64 = 0

    func waitForTurn(intervalNanoseconds: UInt64) async throws {
        let now = DispatchTime.now().uptimeNanoseconds
        let scheduled = max(now, nextAllowedUptimeNanoseconds)
        nextAllowedUptimeNanoseconds = scheduled &+ intervalNanoseconds
        if scheduled > now { try await Task.sleep(nanoseconds: scheduled - now) }
    }
}

nonisolated private enum MusicBrainzClientError: LocalizedError {
    case emptyQuery
    case invalidIdentifier
    case invalidResponse
    case invalidArtwork
    case responseTooLarge
    case networkUnavailable
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .emptyQuery: "Enter a title to search MusicBrainz."
        case .invalidIdentifier: "The selected MusicBrainz item is invalid."
        case .invalidResponse: "MusicBrainz returned data that VIPOD could not read."
        case .invalidArtwork: "The selected cover art could not be read."
        case .responseTooLarge: "The MusicBrainz response exceeded the allowed size."
        case .networkUnavailable: "MusicBrainz is unavailable. Check your connection and try again."
        case .httpStatus(let status): "MusicBrainz returned HTTP status \(status)."
        }
    }
}
#endif
