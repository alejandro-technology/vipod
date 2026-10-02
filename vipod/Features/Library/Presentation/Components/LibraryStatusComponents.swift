import SwiftUI

struct ImportingMusicStatus: View {
    var body: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text(String(localized: "Importing Music…"))
                .font(.system(size: 11, weight: .medium))
        }
        .frame(maxWidth: .infinity, minHeight: 30)
        .accessibilityElement(children: .combine)
    }
}

struct LibraryAttentionStatus: View {
    let theme: iPodTheme

    var body: some View {
        Text(String(localized: "The music library needs attention."))
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(theme.palette.secondaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
    }
}

struct LibraryLoadStateView<Content: View>: View {
    let isLoading: Bool
    let loadFailed: Bool
    let hasTracks: Bool
    let showsFailureInPlaceOfContent: Bool
    let retryAction: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        if loadFailed && !hasTracks && showsFailureInPlaceOfContent {
            LibraryLoadFailurePanel(isLoading: isLoading, retryAction: retryAction)
        } else if isLoading && !hasTracks {
            HStack(spacing: 8) {
                ProgressView()
                Text(String(localized: "Loading Music…"))
                    .font(.system(size: 14))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            content()
        }
    }
}

struct LibraryLoadFailurePanel: View {
    let isLoading: Bool
    let retryAction: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Text(String(localized: "The music library could not be loaded."))
                .font(.system(size: 12, weight: .medium))
            Button(action: retryAction) {
                HStack(spacing: 6) {
                    if isLoading { ProgressView().controlSize(.small) }
                    Text(String(localized: "Retry Library Load"))
                }
                .font(.system(size: 12, weight: .semibold))
                .frame(minHeight: 44)
                .padding(.horizontal, 8)
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .accessibilityIdentifier("library.retry")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(8)
    }
}

struct LibraryRouteStatus: View {
    let outputName: String
    let deviceKind: BluetoothDeviceKind?
    let theme: iPodTheme

    var body: some View {
        VStack(spacing: 2) {
            Text(String.localizedStringWithFormat(String(localized: "Connected device: %@"), outputName))
            if deviceKind == .airPods { Text(String(localized: "Battery level is unavailable.")) }
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(theme.palette.secondaryText)
        .frame(maxWidth: .infinity, minHeight: 34)
        .accessibilityIdentifier("settings.bluetooth.route")
    }
}
