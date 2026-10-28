import Foundation

#if os(iOS)
/// Pure title-cleanup policy shared inward by Application and Infrastructure.
nonisolated enum YouTubeMusicSearchTitle {
    private static let noisePatterns = [
        #"(?i)\s*[\(\[\{（【]\s*(?:(?:official|music|audio|lyrics?|vevo|hd|4k|1080p|720p)\s+)*(?:music\s+video|video|audio|visuali[sz]er|lyrics?|lyric\s+video|mv|hd|4k|1080p|720p|vevo|topic)\s*[\)\]\}）】]\s*$"#,
        #"(?i)\s*(?:\||[-–—])\s*(?:(?:official|music|audio)\s+)*(?:music\s+video|video|audio|visuali[sz]er|lyrics?(?:\s+video)?|mv|hd|4k|1080p|720p|vevo|topic)\s*$"#,
        #"(?i)\s+(?:official\s+(?:music\s+)?(?:video|audio|visuali[sz]er)|lyrics?\s+video|visuali[sz]er)\s*$"#,
        #"(?i)\s+(?:4k|1080p|720p|1080\s*p|720\s*p)\s*$"#,
        #"(?i)\s+#(?:shorts|music)\s*$"#
    ]
    private static let maximumQueryCharacters = 180

    static func sanitized(_ title: String) -> String {
        var cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var didRemoveNoise = true
        while didRemoveNoise {
            didRemoveNoise = false
            for pattern in noisePatterns {
                let reduced = cleaned.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
                if reduced != cleaned {
                    cleaned = reduced
                    didRemoveNoise = true
                }
            }
        }

        let edgeSeparators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-–—|"))
        return String(cleaned.trimmingCharacters(in: edgeSeparators)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ").prefix(maximumQueryCharacters))
    }
}
#endif
