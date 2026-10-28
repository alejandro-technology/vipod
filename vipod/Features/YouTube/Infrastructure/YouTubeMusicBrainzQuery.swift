import Foundation

#if os(iOS)
nonisolated enum YouTubeMusicBrainzQuery {
    private static let luceneSpecialCharacters = CharacterSet(charactersIn: #"+-&|!(){}[]^\"~*?:\/"#)

    static func escapedLucenePhrase(_ title: String) -> String? {
        let sanitized = YouTubeMusicSearchTitle.sanitized(title)
        guard !sanitized.isEmpty else { return nil }
        let escaped = sanitized.unicodeScalars.reduce(into: String()) { result, scalar in
            if scalar == "\\" || luceneSpecialCharacters.contains(scalar) { result.append("\\") }
            result.unicodeScalars.append(scalar)
        }
        return "recording:\"\(escaped)\""
    }

    static func searchURL(for title: String, limit: Int = 10) -> URL? {
        guard let query = escapedLucenePhrase(title),
              var components = URLComponents(string: "https://musicbrainz.org/ws/2/recording/") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: String(min(max(limit, 1), 10)))
        ]
        return components.url
    }
}
#endif
