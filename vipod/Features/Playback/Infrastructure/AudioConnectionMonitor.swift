import AVFoundation
import Foundation
import Observation

#if os(iOS)
import CoreBluetooth
#endif

@MainActor @Observable
public final class AudioConnectionMonitor: NSObject {
    public private(set) var bluetoothState: BluetoothPowerState = .unknown
    public private(set) var output: BluetoothAudioOutput?
    public private(set) var preferredDeviceKind: BluetoothDeviceKind = .automatic

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let outputProvider: @MainActor () -> BluetoothAudioOutput?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let preferenceKeyPrefix = "audioConnection.deviceKind."
    #if os(iOS)
    @ObservationIgnored private var centralManager: CBCentralManager?
    #endif

    public var deviceKind: BluetoothDeviceKind {
        guard let output else { return .automatic }
        if preferredDeviceKind != .automatic { return preferredDeviceKind }
        return AudioConnectionStatusResolver.automaticKind(for: output)
    }

    public var status: AudioConnectionStatus? {
        AudioConnectionStatusResolver.status(output: output, preferredKind: output == nil ? nil : deviceKind, powerState: bluetoothState)
    }

    public init(
        defaults: UserDefaults = .standard,
        outputProvider: (@MainActor () -> BluetoothAudioOutput?)? = nil
    ) {
        self.defaults = defaults
        #if os(iOS) || os(visionOS)
        self.outputProvider = outputProvider ?? {
            let route = AVAudioSession.sharedInstance().currentRoute
            let bluetoothPorts: [AVAudioSession.Port] = [.bluetoothA2DP, .bluetoothHFP, .bluetoothLE]
            guard let port = route.outputs.first(where: { bluetoothPorts.contains($0.portType) }) else { return nil }
            return BluetoothAudioOutput(uid: port.uid, name: port.portName)
        }
        #else
        self.outputProvider = outputProvider ?? { nil }
        #endif
        super.init()
        #if os(iOS) || os(visionOS)
        observeAudioChanges()
        #endif
        refresh()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    public func setPreferredDeviceKind(_ kind: BluetoothDeviceKind) {
        guard let output else { return }
        guard preferredDeviceKind != kind else { return }
        let key = preferenceKey(for: output.uid)
        if kind == .automatic {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(kind.rawValue, forKey: key)
        }
        preferredDeviceKind = kind
    }

    public func start() {
        #if os(iOS)
        guard centralManager == nil else { return }
        centralManager = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: false])
        refresh()
        #endif
    }

    public func refresh() {
        let newOutput = outputProvider()
        guard output != newOutput else { return }
        output = newOutput
        preferredDeviceKind = newOutput.flatMap { storedKind(for: $0) } ?? .automatic
    }

    private func preferenceKey(for uid: String) -> String {
        preferenceKeyPrefix + uid
    }

    private func storedKind(for output: BluetoothAudioOutput) -> BluetoothDeviceKind? {
        defaults.string(forKey: preferenceKey(for: output.uid)).flatMap(BluetoothDeviceKind.init(rawValue:))
    }

    #if os(iOS) || os(visionOS)
    private func observeAudioChanges() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        })
    }
    #endif
}

#if os(iOS)
extension AudioConnectionMonitor: CBCentralManagerDelegate {
    nonisolated public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state: BluetoothPowerState
        switch central.state {
        case .poweredOn: state = .poweredOn
        case .poweredOff: state = .poweredOff
        case .unauthorized: state = .unauthorized
        case .unsupported: state = .unsupported
        case .resetting: state = .resetting
        case .unknown: state = .unknown
        @unknown default: state = .unknown
        }
        Task { @MainActor [weak self] in
            self?.bluetoothState = state
            self?.refresh()
        }
    }
}
#endif
