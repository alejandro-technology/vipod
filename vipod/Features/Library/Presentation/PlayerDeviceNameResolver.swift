import Foundation

#if canImport(UIKit) && (os(iOS) || os(visionOS))
import UIKit
#endif

enum PlayerDeviceNameResolver {
    static func displayName(from candidate: String?) -> String {
        guard let candidate else { return String(localized: "iPod") }
        let name = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return String(localized: "iPod") }
        let normalizedName = name.localizedLowercase
        let genericNames = ["iphone", "ipad", "ipod", "ipod touch"]
        let isGenericName = genericNames.contains(normalizedName)
            || normalizedName.range(
                of: #"^iphone \d+(?: e| mini| pro(?: max)?| plus| max)?$"#,
                options: .regularExpression
            ) != nil
        guard !isGenericName else {
            return String(localized: "iPod")
        }
        return name
    }

    static func currentDisplayName() -> String {
        #if canImport(UIKit) && (os(iOS) || os(visionOS))
        return displayName(from: UIDevice.current.name)
        #else
        return String(localized: "iPod")
        #endif
    }
}
