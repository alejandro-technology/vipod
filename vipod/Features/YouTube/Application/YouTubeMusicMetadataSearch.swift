import Foundation

#if os(iOS)
nonisolated struct YouTubeMusicRecording: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let artist: String?
    let firstReleaseDate: String?
    let genre: String?
    let releases: [YouTubeMusicReleaseSummary]
}

nonisolated struct YouTubeMusicReleaseSummary: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let artist: String?
    let date: String?
    let trackCount: Int?
}

nonisolated struct YouTubeMusicTrack: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let artist: String?
    let number: Int?
    let numberTotal: Int?
    let discNumber: Int?
}

nonisolated struct YouTubeMusicReleaseDetails: Equatable, Sendable {
    let id: String
    let title: String
    let artist: String?
    let date: String?
    let genre: String?
    let discTotal: Int?
    let tracks: [YouTubeMusicTrack]
}

@MainActor
protocol YouTubeMusicMetadataSearching: AnyObject {
    func searchRecordings(query: String) async throws -> [YouTubeMusicRecording]
    func loadRelease(id: String) async throws -> YouTubeMusicReleaseDetails
    func artwork(releaseID: String) async throws -> Data?
}
#endif
