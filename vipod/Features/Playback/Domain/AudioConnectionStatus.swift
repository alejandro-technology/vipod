import Foundation

public enum BluetoothDeviceKind: String, CaseIterable, Sendable {
    case automatic
    case airPods
    case headphones
    case speaker
}

public enum BluetoothPowerState: Sendable, Equatable {
    case unknown
    case poweredOn
    case poweredOff
    case unauthorized
    case unsupported
    case resetting
}

public struct BluetoothAudioOutput: Equatable, Sendable {
    public let uid: String
    public let name: String

    public init(uid: String, name: String) {
        self.uid = uid
        self.name = name
    }
}

public struct AudioConnectionStatus: Equatable, Sendable {
    public let symbolName: String
    public let accessibilityLabel: String

    public init(symbolName: String, accessibilityLabel: String) {
        self.symbolName = symbolName
        self.accessibilityLabel = accessibilityLabel
    }
}

enum AudioConnectionStatusResolver {
    static func status(
        output: BluetoothAudioOutput?,
        preferredKind: BluetoothDeviceKind?,
        powerState: BluetoothPowerState
    ) -> AudioConnectionStatus? {
        if let output {
            let kind = preferredKind == .automatic || preferredKind == nil
                ? automaticKind(for: output)
                : preferredKind!
            switch kind {
            case .automatic:
                return AudioConnectionStatus(symbolName: "antenna.radiowaves.left.and.right", accessibilityLabel: "Bluetooth audio connected: \(output.name)")
            case .headphones:
                return AudioConnectionStatus(symbolName: "headphones", accessibilityLabel: "Bluetooth headphones connected: \(output.name)")
            case .airPods:
                return AudioConnectionStatus(symbolName: "airpods", accessibilityLabel: "AirPods connected: \(output.name)")
            case .speaker:
                return AudioConnectionStatus(symbolName: "hifispeaker.fill", accessibilityLabel: "Bluetooth speaker connected: \(output.name)")
            }
        }

        guard powerState == .poweredOn else { return nil }
        return AudioConnectionStatus(symbolName: "antenna.radiowaves.left.and.right", accessibilityLabel: "Bluetooth is on")
    }

    static func automaticKind(for output: BluetoothAudioOutput) -> BluetoothDeviceKind {
        output.name.localizedCaseInsensitiveContains("airpod") ? .airPods : .automatic
    }
}
