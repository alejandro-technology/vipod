import Foundation

public struct Track: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var artist: String
    public var album: String
    public var duration: TimeInterval?
    public var audioFilename: String
    public var artworkFilename: String?

    public init(id: UUID = UUID(), title: String, artist: String? = nil, album: String? = nil, duration: TimeInterval? = nil, audioFilename: String, artworkFilename: String? = nil) {
        self.id = id
        self.title = Self.usable(title, fallback: "Unknown Title")
        self.artist = Self.usable(artist, fallback: "Unknown Artist")
        self.album = Self.usable(album, fallback: "Unknown Album")
        self.duration = duration.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        self.audioFilename = audioFilename
        self.artworkFilename = artworkFilename
    }

    private static func usable(_ value: String?, fallback: String) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return fallback }
        return value
    }
}
