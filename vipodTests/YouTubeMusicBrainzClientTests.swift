import XCTest
import ImageIO
@testable import vipod

final class YouTubeMusicBrainzClientTests: XCTestCase {
    @MainActor
    func testBoundedCollectorAcceptsBodyExactlyAtCap() async throws {
        let counter = ByteConsumptionCounter()
        let body = try await MusicBrainzBoundedBody().collect(
            CountingBytes(count: 4, counter: counter), maximumBytes: 4
        )
        XCTAssertEqual(body, Data(repeating: 42, count: 4))
        XCTAssertEqual(counter.consumed, 4)
        XCTAssertEqual(counter.mainThreadByteCount, 0)
    }

    @MainActor
    func testBoundedCollectorStopsAtFirstExcessByteRegardlessOfContentLength() async {
        for expectedLength: Int64 in [-1, 2] {
            let counter = ByteConsumptionCounter()
            do {
                _ = try await MusicBrainzBoundedBody().collect(
                    CountingBytes(count: 100, counter: counter), maximumBytes: 4, expectedLength: expectedLength
                )
                XCTFail("Missing or understated Content-Length must not bypass the streaming cap.")
            } catch {
                XCTAssertEqual((error as? LocalizedError)?.errorDescription, "The MusicBrainz response exceeded the allowed size.")
            }
            XCTAssertEqual(counter.consumed, 5, "Stop on the first excess byte, without consuming the rest of the body.")
        }
    }

    @MainActor
    func testBoundedCollectorRejectsExcessContentLengthWithoutConsumingBody() async {
        let counter = ByteConsumptionCounter()
        do {
            _ = try await MusicBrainzBoundedBody().collect(
                CountingBytes(count: 100, counter: counter), maximumBytes: 4, expectedLength: 100
            )
            XCTFail("An oversized Content-Length should fail before collecting bytes.")
        } catch {
            XCTAssertEqual((error as? LocalizedError)?.errorDescription, "The MusicBrainz response exceeded the allowed size.")
        }
        XCTAssertEqual(counter.consumed, 0)
    }

    @MainActor
    func testInjectedTransportRetainsJSONAndArtworkCapsWithoutRetryingOversizedBodies() async throws {
        for isArtwork in [false, true] {
            var requestCount = 0
            let cap = isArtwork ? 8 * 1024 * 1024 : 2 * 1024 * 1024
            let client = MusicBrainzClient(minimumRequestInterval: 0, sleep: { _ in }, transport: { request in
                requestCount += 1
                let response = try XCTUnwrap(HTTPURLResponse(
                    url: XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil
                ))
                return (Data(repeating: 0, count: cap + 1), response)
            })
            do {
                if isArtwork { _ = try await client.artwork(releaseID: "22222222-2222-4222-8222-222222222222") }
                else { _ = try await client.searchRecordings(query: "Title") }
                XCTFail("The original \(cap)-byte cap must still reject an oversized injected response.")
            } catch {
                XCTAssertEqual((error as? LocalizedError)?.errorDescription, "The MusicBrainz response exceeded the allowed size.")
            }
            XCTAssertEqual(requestCount, 1)
        }
    }

    @MainActor
    func testCancelledURLSessionTransportRemainsCancellationWithoutRetry() async {
        var requestCount = 0
        var delays: [TimeInterval] = []
        let client = MusicBrainzClient(minimumRequestInterval: 0, sleep: { delays.append($0) }, transport: { _ in
            requestCount += 1
            throw URLError(.cancelled)
        })
        do {
            _ = try await client.searchRecordings(query: "Cancelled search")
            XCTFail("URLSession cancellation must remain cancellation.")
        } catch is CancellationError {
            // Expected: cancellation must not become a user-facing network failure.
        } catch {
            XCTFail("Expected CancellationError, received \(error)")
        }
        XCTAssertEqual(requestCount, 1)
        XCTAssertTrue(delays.isEmpty)
    }

    @MainActor
    func testCancelledTaskWinsOverGenericTransportError() async {
        let client = MusicBrainzClient(minimumRequestInterval: 0, sleep: { _ in }, transport: { _ in
            withUnsafeCurrentTask { $0?.cancel() }
            throw URLError(.networkConnectionLost)
        })
        let operation = Task {
            try await client.searchRecordings(query: "Cancelled task")
        }
        do {
            _ = try await operation.value
            XCTFail("A cancelled task must not retry or become networkUnavailable.")
        } catch is CancellationError {
            // Expected even when the transport's final error is not a cancellation code.
        } catch {
            XCTFail("Expected CancellationError, received \(error)")
        }
    }

    @MainActor
    func testJSONDecodingExecutesOffMainThreadWhenCalledFromMainActor() async throws {
        let probe = try await MusicBrainzProcessing().decode(DecodingExecutorProbe.self, from: Data("{}".utf8))
        XCTAssertFalse(probe.ranOnMainThread)
    }

    @MainActor
    func testArtworkNormalizationStillReturnsValidJPEGThroughWorker() async throws {
        let png = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1kAAAAASUVORK5CYII="))
        let client = MusicBrainzClient(minimumRequestInterval: 0, sleep: { _ in }, transport: { request in
            let response = try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil))
            return (png, response)
        })
        let artwork = try await client.artwork(releaseID: "22222222-2222-4222-8222-222222222222")
        let jpeg = try XCTUnwrap(artwork)
        XCTAssertEqual(Array(jpeg.prefix(2)), [0xff, 0xd8])
        XCTAssertNotNil(CGImageSourceCreateWithData(jpeg as CFData, nil))
    }

    func testSanitizedTitleRemovesOnlyRecognizedTrailingNoiseAndPreservesAccents() {
        XCTAssertEqual(
            YouTubeMusicSearchTitle.sanitized("  Beyoncé — Halo (Official Music Video) [4K] #shorts  "),
            "Beyoncé — Halo"
        )
        XCTAssertEqual(
            YouTubeMusicSearchTitle.sanitized("Sigur Rós - Svefn-g-englar | Official Audio"),
            "Sigur Rós - Svefn-g-englar"
        )
        XCTAssertEqual(YouTubeMusicSearchTitle.sanitized("Árbol"), "Árbol")
        XCTAssertEqual(YouTubeMusicSearchTitle.sanitized("[Official Audio]"), "")
    }

    func testLucenePunctuationIsEscapedBeforeURLQueryEncoding() throws {
        let url = try XCTUnwrap(YouTubeMusicBrainzQuery.searchURL(for: "AC/DC: \"Jóga\" + live? (Official Audio)", limit: 99))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(
            components.queryItems?.first(where: { $0.name == "query" })?.value,
            "recording:\"AC\\/DC\\: \\\"Jóga\\\" \\+ live\\?\""
        )
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "limit" })?.value, "10")
        XCTAssertFalse(url.absoluteString.contains("AC/DC: \"Jóga\""), "URLComponents must encode user-provided punctuation in the URL.")
    }

    @MainActor
    func testSearchBuildsEscapedEncodedRequestDecodesReleasesAndCachesResults() async throws {
        var requests: [URLRequest] = []
        let client = MusicBrainzClient(minimumRequestInterval: 0, sleep: { _ in }, transport: { request in
            requests.append(request)
            return try Self.response(request: request, status: 200, json: Self.recordingSearchJSON)
        })

        let recordings = try await client.searchRecordings(query: "Björk: Jóga (Official Audio)")
        XCTAssertEqual(recordings.count, 1)
        XCTAssertEqual(recordings[0].title, "Jóga")
        XCTAssertEqual(recordings[0].artist, "Björk")
        XCTAssertEqual(recordings[0].firstReleaseDate, "1997-09-15")
        XCTAssertEqual(recordings[0].genre, "Art Pop")
        XCTAssertEqual(recordings[0].releases.first?.title, "Homogenic")
        XCTAssertEqual(recordings[0].releases.first?.trackCount, 10)

        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "VIPOD/1.0 (com.alejandrotechnology.vipod)")
        let components = try XCTUnwrap(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "query" })?.value, "recording:\"Björk\\: Jóga\"")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "fmt" })?.value, "json")

        let cached = try await client.searchRecordings(query: "Björk: Jóga [Official Music Video]")
        XCTAssertEqual(cached, recordings)
        XCTAssertEqual(requests.count, 1, "Equivalent sanitized titles share the bounded result cache.")
    }

    @MainActor
    func testReleaseLookupReturnsRealTrackPositionAndDiscInformation() async throws {
        var requestedURL: URL?
        let client = MusicBrainzClient(minimumRequestInterval: 0, sleep: { _ in }, transport: { request in
            requestedURL = request.url
            return try Self.response(request: request, status: 200, json: Self.releaseJSON)
        })

        let details = try await client.loadRelease(id: "22222222-2222-4222-8222-222222222222")
        XCTAssertTrue(try XCTUnwrap(requestedURL?.absoluteString).contains("/ws/2/release/22222222-2222-4222-8222-222222222222"))
        XCTAssertEqual(details.title, "Homogenic")
        XCTAssertEqual(details.artist, "Björk")
        XCTAssertEqual(details.discTotal, 2)
        XCTAssertEqual(details.tracks.count, 2)
        XCTAssertEqual(details.tracks[0].title, "Jóga")
        XCTAssertEqual(details.tracks[0].number, 3)
        XCTAssertEqual(details.tracks[0].numberTotal, 10)
        XCTAssertEqual(details.tracks[0].discNumber, 1)
        XCTAssertEqual(details.tracks[0].artist, "Björk")
    }

    @MainActor
    func testTransientResponsesRetryWithBoundedBackoffAndPermanentErrorsDoNotRetry() async throws {
        var requestCount = 0
        var delays: [TimeInterval] = []
        let client = MusicBrainzClient(minimumRequestInterval: 0, sleep: { delays.append($0) }, transport: { request in
            requestCount += 1
            let status = requestCount < 3 ? 503 : 200
            return try Self.response(request: request, status: status, json: Self.recordingSearchJSON)
        })

        let results = try await client.searchRecordings(query: "Jóga")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(requestCount, 3, "The retry policy allows at most two retries.")
        XCTAssertEqual(delays, [1, 2])

        var badRequestCount = 0
        let permanentFailure = MusicBrainzClient(minimumRequestInterval: 0, sleep: { _ in }, transport: { request in
            badRequestCount += 1
            return try Self.response(request: request, status: 400, json: "{}")
        })
        do {
            _ = try await permanentFailure.searchRecordings(query: "Jóga")
            XCTFail("A permanent HTTP failure should be surfaced.")
        } catch {
            XCTAssertEqual((error as? LocalizedError)?.errorDescription, "MusicBrainz returned HTTP status 400.")
        }
        XCTAssertEqual(badRequestCount, 1)
    }

    @MainActor
    func testOverlappingRequestsShareOnePerSecondRateGate() async throws {
        var requestTimes: [UInt64] = []
        let client = MusicBrainzClient(minimumRequestInterval: 0.05, sleep: { _ in }, transport: { request in
            requestTimes.append(DispatchTime.now().uptimeNanoseconds)
            try await Task.sleep(for: .milliseconds(10))
            return try Self.response(request: request, status: 200, json: Self.recordingSearchJSON)
        })

        async let first = client.searchRecordings(query: "First title")
        async let second = client.searchRecordings(query: "Second title")
        _ = try await (first, second)
        XCTAssertEqual(requestTimes.count, 2)
        XCTAssertGreaterThanOrEqual(requestTimes[1] - requestTimes[0], 45_000_000)
    }

    @MainActor
    func testEmptySearchQueryIsRejectedWithoutMakingARequest() async throws {
        var didRequest = false
        let client = MusicBrainzClient(minimumRequestInterval: 0, sleep: { _ in }, transport: { request in
            didRequest = true
            return try Self.response(request: request, status: 200, json: "{}")
        })

        XCTAssertNil(YouTubeMusicBrainzQuery.searchURL(for: "  [Official Audio]  "))
        do {
            _ = try await client.searchRecordings(query: "  [Official Audio]  ")
            XCTFail("An empty sanitized title should not be sent to MusicBrainz.")
        } catch {
            XCTAssertEqual((error as? LocalizedError)?.errorDescription, "Enter a title to search MusicBrainz.")
        }
        XCTAssertFalse(didRequest)
    }

    private static func response(request: URLRequest, status: Int, json: String) throws -> (Data, URLResponse) {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else {
            throw URLError(.badServerResponse)
        }
        return (Data(json.utf8), response)
    }

    private static let recordingSearchJSON = #"""
    {
      "recordings": [{
        "id": "11111111-1111-4111-8111-111111111111",
        "title": "Jóga",
        "first-release-date": "1997-09-15",
        "artist-credit": [{ "name": "Björk", "artist": { "name": "Björk" } }],
        "genres": [{ "name": "Art Pop" }],
        "releases": [{
          "id": "22222222-2222-4222-8222-222222222222",
          "title": "Homogenic",
          "date": "1997-09-22",
          "track-count": 10,
          "artist-credit": [{ "name": "Björk" }]
        }]
      }]
    }
    """#

    private static let releaseJSON = #"""
    {
      "id": "22222222-2222-4222-8222-222222222222",
      "title": "Homogenic",
      "date": "1997-09-22",
      "artist-credit": [{ "name": "Björk" }],
      "genres": [{ "name": "Art Pop" }],
      "media": [
        {
          "position": 1,
          "track-count": 10,
          "tracks": [{
            "id": "33333333-3333-4333-8333-333333333333",
            "title": "Jóga",
            "number": "3",
            "position": 3,
            "recording": {
              "id": "11111111-1111-4111-8111-111111111111",
              "title": "Jóga",
              "artist-credit": [{ "name": "Björk" }]
            }
          }]
        },
        { "position": 2, "track-count": 1, "tracks": [{ "title": "Hidden track", "number": "1", "position": 1 }] }
      ]
    }
    """#
}

nonisolated private struct DecodingExecutorProbe: Decodable, Sendable {
    let ranOnMainThread: Bool

    init(from decoder: Decoder) throws {
        ranOnMainThread = Thread.isMainThread
    }
}

nonisolated private final class ByteConsumptionCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var mainThreadCount = 0

    var consumed: Int { lock.withLock { count } }
    var mainThreadByteCount: Int { lock.withLock { mainThreadCount } }

    func recordByte() {
        lock.withLock {
            count += 1
            if Thread.isMainThread { mainThreadCount += 1 }
        }
    }
}

nonisolated private struct CountingBytes: AsyncSequence, Sendable {
    typealias Element = UInt8
    let count: Int
    let counter: ByteConsumptionCounter

    func makeAsyncIterator() -> Iterator { Iterator(remaining: count, counter: counter) }

    struct Iterator: AsyncIteratorProtocol {
        var remaining: Int
        let counter: ByteConsumptionCounter

        mutating func next() async -> UInt8? {
            guard remaining > 0 else { return nil }
            remaining -= 1
            counter.recordByte()
            return 42
        }
    }
}
