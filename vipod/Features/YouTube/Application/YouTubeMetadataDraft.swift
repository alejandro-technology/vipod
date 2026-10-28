import Foundation

#if os(iOS)
nonisolated struct YouTubeMetadataDraft: Equatable, Sendable {
    var title: String
    var artist: String
    var album: String
    var albumArtist: String
    var releaseDate: String
    var genre: String
    var trackNumber: String
    var trackNumberTotal: String
    var discNumber: String
    var discNumberTotal: String

    init(metadata: YouTubeEffectiveMetadata) {
        title = metadata.title
        artist = metadata.artist ?? ""
        album = metadata.album ?? ""
        albumArtist = metadata.albumArtist ?? ""
        releaseDate = metadata.releaseDate ?? ""
        genre = metadata.genre ?? ""
        trackNumber = metadata.trackNumber.map(String.init) ?? ""
        trackNumberTotal = metadata.trackNumberTotal.map(String.init) ?? ""
        discNumber = metadata.discNumber.map(String.init) ?? ""
        discNumberTotal = metadata.discNumberTotal.map(String.init) ?? ""
    }

    var validationMessage: String? {
        guard Self.normalized(title) != nil else { return "A title is required before downloading." }
        if let message = Self.ordinalValidation(number: trackNumber, total: trackNumberTotal, label: "Track") { return message }
        if let message = Self.ordinalValidation(number: discNumber, total: discNumberTotal, label: "Disc") { return message }
        return nil
    }

    func effectiveMetadata(videoTitle: String) -> YouTubeEffectiveMetadata? {
        guard validationMessage == nil, let title = Self.normalized(title) else { return nil }
        return YouTubeEffectiveMetadata(
            title: title,
            videoTitle: videoTitle,
            artist: Self.normalized(artist),
            album: Self.normalized(album),
            albumArtist: Self.normalized(albumArtist),
            releaseDate: Self.normalized(releaseDate),
            genre: Self.normalized(genre),
            trackNumber: Self.positiveInteger(trackNumber),
            discNumber: Self.positiveInteger(discNumber),
            trackNumberTotal: Self.positiveInteger(trackNumberTotal),
            discNumberTotal: Self.positiveInteger(discNumberTotal)
        )
    }

    private static func ordinalValidation(number: String, total: String, label: String) -> String? {
        let trimmedNumber = number.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTotal = total.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedNumber = positiveInteger(trimmedNumber)
        let parsedTotal = positiveInteger(trimmedTotal)

        if !trimmedNumber.isEmpty && parsedNumber == nil { return "\(label) number must be a positive whole number." }
        if !trimmedTotal.isEmpty && parsedTotal == nil { return "\(label) total must be a positive whole number." }
        if parsedTotal != nil && parsedNumber == nil { return "Enter a \(label.lowercased()) number before its total." }
        if let parsedNumber, let parsedTotal, parsedTotal < parsedNumber {
            return "\(label) total cannot be smaller than its number."
        }
        return nil
    }

    private static func positiveInteger(_ value: String) -> Int? {
        guard let number = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)), number > 0 else { return nil }
        return number
    }

    private static func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
#endif
