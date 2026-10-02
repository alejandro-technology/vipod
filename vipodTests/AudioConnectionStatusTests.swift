import XCTest
@testable import vipod

@MainActor
private final class AudioRouteStub {
    var output: BluetoothAudioOutput?

    init(output: BluetoothAudioOutput?) {
        self.output = output
    }

    nonisolated deinit {}
}

@MainActor
final class AudioConnectionStatusTests: XCTestCase {
    func testAutomaticOutputClassificationRecognizesAirPodsAndKeepsGenericDevicesGeneric() {
        let airPods = BluetoothAudioOutput(uid: "one", name: "Alejandro’s AirPods Pro")
        let headphones = BluetoothAudioOutput(uid: "two", name: "Studio headset")

        XCTAssertEqual(AudioConnectionStatusResolver.automaticKind(for: airPods), .airPods)
        XCTAssertEqual(AudioConnectionStatusResolver.automaticKind(for: headphones), .automatic)
        XCTAssertEqual(
            AudioConnectionStatusResolver.status(output: headphones, preferredKind: .automatic, powerState: .unknown)?.symbolName,
            "antenna.radiowaves.left.and.right"
        )
        XCTAssertEqual(
            AudioConnectionStatusResolver.status(output: headphones, preferredKind: .speaker, powerState: .unknown)?.symbolName,
            "hifispeaker.fill"
        )
    }

    func testManualClassificationOverridesAirPodsNameRecognition() {
        let output = BluetoothAudioOutput(uid: "airpods", name: "AirPods Max")

        XCTAssertEqual(
            AudioConnectionStatusResolver.status(output: output, preferredKind: .speaker, powerState: .poweredOn)?.accessibilityLabel,
            "Bluetooth speaker connected: AirPods Max"
        )
        XCTAssertEqual(
            AudioConnectionStatusResolver.status(output: output, preferredKind: .headphones, powerState: .poweredOn)?.symbolName,
            "headphones"
        )
    }

    func testActiveOutputTakesPrecedenceOverRadioStateAndDisconnectDoesNotImplyOff() {
        let output = BluetoothAudioOutput(uid: "active", name: "Car audio")

        XCTAssertNotNil(AudioConnectionStatusResolver.status(output: output, preferredKind: .automatic, powerState: .unknown))
        XCTAssertNotNil(AudioConnectionStatusResolver.status(output: output, preferredKind: .automatic, powerState: .poweredOff))
        XCTAssertNil(AudioConnectionStatusResolver.status(output: nil, preferredKind: nil, powerState: .unknown))
        XCTAssertNil(AudioConnectionStatusResolver.status(output: nil, preferredKind: nil, powerState: .unauthorized))
        XCTAssertNil(AudioConnectionStatusResolver.status(output: nil, preferredKind: nil, powerState: .poweredOff))
    }

    func testManualPreferencesAreIsolatedByUIDAndRestoreAcrossDisconnectAndReconnect() async {
        let suite = "AudioConnectionStatusTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = BluetoothAudioOutput(uid: "port-1", name: "Headset")
        let second = BluetoothAudioOutput(uid: "port-2", name: "Headset")
        let route = AudioRouteStub(output: first)
        let monitor = AudioConnectionMonitor(defaults: defaults, outputProvider: { route.output })

        monitor.setPreferredDeviceKind(.speaker)
        XCTAssertEqual(monitor.preferredDeviceKind, .speaker)
        XCTAssertEqual(monitor.deviceKind, .speaker)
        XCTAssertEqual(monitor.status?.symbolName, "hifispeaker.fill")

        route.output = nil
        monitor.refresh()
        XCTAssertNil(monitor.output)
        XCTAssertEqual(monitor.preferredDeviceKind, .automatic)

        route.output = second
        monitor.refresh()
        XCTAssertEqual(monitor.preferredDeviceKind, .automatic)
        XCTAssertEqual(monitor.deviceKind, .automatic)
        XCTAssertEqual(monitor.status?.symbolName, "antenna.radiowaves.left.and.right")
        monitor.setPreferredDeviceKind(.headphones)

        route.output = first
        monitor.refresh()
        XCTAssertEqual(monitor.preferredDeviceKind, .speaker)
        XCTAssertEqual(monitor.deviceKind, .speaker)

        route.output = BluetoothAudioOutput(uid: "airpods", name: "AirPods Pro")
        monitor.refresh()
        XCTAssertEqual(monitor.deviceKind, .airPods)
        monitor.setPreferredDeviceKind(.speaker)
        XCTAssertEqual(monitor.deviceKind, .speaker)
        monitor.setPreferredDeviceKind(.automatic)
        XCTAssertEqual(monitor.preferredDeviceKind, .automatic)
        XCTAssertEqual(monitor.deviceKind, .airPods)
    }

    func testManualPreferencePersistsAcrossMonitorReconstruction() async {
        let suite = "AudioConnectionStatusTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let output = BluetoothAudioOutput(uid: "persistent-port", name: "Desk audio")

        let firstMonitor = AudioConnectionMonitor(defaults: defaults, outputProvider: { output })
        firstMonitor.setPreferredDeviceKind(.speaker)
        XCTAssertEqual(firstMonitor.deviceKind, .speaker)

        let recreatedMonitor = AudioConnectionMonitor(defaults: defaults, outputProvider: { output })
        XCTAssertEqual(recreatedMonitor.preferredDeviceKind, .speaker)
        XCTAssertEqual(recreatedMonitor.deviceKind, .speaker)
        XCTAssertEqual(recreatedMonitor.status?.symbolName, "hifispeaker.fill")
    }

    func testBluetoothOnWithoutActiveOutputHasGenericOnIndicator() {
        XCTAssertEqual(
            AudioConnectionStatusResolver.status(output: nil, preferredKind: nil, powerState: .poweredOn)?.accessibilityLabel,
            "Bluetooth is on"
        )
        XCTAssertNil(AudioConnectionStatusResolver.status(output: nil, preferredKind: nil, powerState: .poweredOff))
    }
}
