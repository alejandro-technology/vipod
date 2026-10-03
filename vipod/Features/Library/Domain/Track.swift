import Foundation

public struct Track: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var artist: String
    public var album: String
    public var albumArtist: String?
    public var trackNumber: Int?
    public var discNumber: Int?
    public var isCompilation: Bool
    public var duration: TimeInterval?
    public var audioFilename: String
    public var artworkFilename: String?

    public init(id: UUID = UUID(), title: String, artist: String? = nil, album: String? = nil, albumArtist: String? = nil, trackNumber: Int? = nil, discNumber: Int? = nil, isCompilation: Bool = false, duration: TimeInterval? = nil, audioFilename: String, artworkFilename: String? = nil) {
        self.id = id
        self.title = Self.usable(title, fallback: "Unknown Title")
        self.artist = Self.usable(artist, fallback: "Unknown Artist")
        self.album = Self.usable(album, fallback: "Unknown Album")
        self.albumArtist = Self.optionalUsable(albumArtist)
        self.trackNumber = Self.positive(trackNumber)
        self.discNumber = Self.positive(discNumber)
        self.isCompilation = isCompilation
        self.duration = duration.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        self.audioFilename = audioFilename
        self.artworkFilename = artworkFilename
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, artist, album, albumArtist, trackNumber, discNumber, isCompilation
        case duration, audioFilename, artworkFilename
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try values.decode(UUID.self, forKey: .id),
            title: try values.decode(String.self, forKey: .title),
            artist: try values.decodeIfPresent(String.self, forKey: .artist),
            album: try values.decodeIfPresent(String.self, forKey: .album),
            albumArtist: try values.decodeIfPresent(String.self, forKey: .albumArtist),
            trackNumber: try values.decodeIfPresent(Int.self, forKey: .trackNumber),
            discNumber: try values.decodeIfPresent(Int.self, forKey: .discNumber),
            isCompilation: try values.decodeIfPresent(Bool.self, forKey: .isCompilation) ?? false,
            duration: try values.decodeIfPresent(TimeInterval.self, forKey: .duration),
            audioFilename: try values.decode(String.self, forKey: .audioFilename),
            artworkFilename: try values.decodeIfPresent(String.self, forKey: .artworkFilename)
        )
    }

    private static func optionalUsable(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    private static func positive(_ value: Int?) -> Int? { value.flatMap { $0 > 0 ? $0 : nil } }

    private static func usable(_ value: String?, fallback: String) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return fallback }
        return value
    }
}
