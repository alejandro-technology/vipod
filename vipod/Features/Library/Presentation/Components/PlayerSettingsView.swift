import SwiftUI

struct PlayerSettingsPresentation {
    let isBlackTheme: Bool
    let isShuffled: Bool
    let repeatMode: RepeatMode
    let preferredBluetoothKind: BluetoothDeviceKind?
    var deviceName: String = String(localized: "iPod")

    func title(for row: ClassicPlayerRow) -> String {
        switch row.id {
        case "theme.black": String.localizedStringWithFormat(String(localized: "Black %@"), deviceName)
        case "theme.white": String.localizedStringWithFormat(String(localized: "White %@"), deviceName)
        case "settings.shuffle": String(localized: "Shuffle")
        case "repeat.off": String(localized: "Repeat Off")
        case "repeat.all": String(localized: "Repeat All")
        case "repeat.one": String(localized: "Repeat One")
        default: row.title
        }
    }

    func subtitle(for row: ClassicPlayerRow) -> String? {
        switch row.id {
        case "theme.black": isBlackTheme ? String(localized: "Selected") : nil
        case "theme.white": isBlackTheme ? nil : String(localized: "Selected")
        case "settings.shuffle": isShuffled ? String(localized: "On") : String(localized: "Off")
        case "repeat.off": repeatMode == .off ? String(localized: "Selected") : nil
        case "repeat.all": repeatMode == .all ? String(localized: "Selected") : nil
        case "repeat.one": repeatMode == .one ? String(localized: "Selected") : nil
        case "settings.bluetooth.automatic": preferredBluetoothKind == .automatic ? String(localized: "Selected") : nil
        case "settings.bluetooth.airPods": preferredBluetoothKind == .airPods ? String(localized: "Selected") : nil
        case "settings.bluetooth.headphones": preferredBluetoothKind == .headphones ? String(localized: "Selected") : nil
        case "settings.bluetooth.speaker": preferredBluetoothKind == .speaker ? String(localized: "Selected") : nil
        default: nil
        }
    }
}

struct PlayerSettingsView: View {
    let rows: [ClassicPlayerRow]
    let selectedRowID: String?
    let theme: iPodTheme
    let reduceMotion: Bool
    let isImporting: Bool
    let isLoading: Bool
    let loadFailed: Bool
    let hasTracks: Bool
    let summary: String?
    let failures: [String]
    let failuresExpanded: Binding<Bool>
    let hasLibraryError: Bool
    let outputName: String?
    let outputKind: BluetoothDeviceKind?
    let presentation: PlayerSettingsPresentation
    let retryAction: () -> Void
    let activate: (ClassicPlayerRow) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if isImporting { ImportingMusicStatus() }
            if let outputName {
                LibraryRouteStatus(outputName: outputName, deviceKind: outputKind, theme: theme)
            }
            LibraryLoadStateView(
                isLoading: isLoading,
                loadFailed: loadFailed,
                hasTracks: hasTracks,
                showsFailureInPlaceOfContent: true,
                retryAction: retryAction
            ) {
                PlayerMenuList(
                    rows: rows,
                    selectedRowID: selectedRowID,
                    theme: theme,
                    reduceMotion: reduceMotion,
                    isImporting: isImporting,
                    titleForRow: presentation.title,
                    subtitleForRow: presentation.subtitle,
                    activate: activate
                )
            }
            if let summary {
                ImportReportView(summary: summary, failures: failures, isExpanded: failuresExpanded, theme: theme)
            }
            if hasLibraryError { LibraryAttentionStatus(theme: theme) }
        }
    }
}
