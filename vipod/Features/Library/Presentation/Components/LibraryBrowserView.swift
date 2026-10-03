import SwiftUI

struct LibraryBrowserPresentation {
    let rows: [ClassicPlayerRow]
    let selectedRowID: String?
    let selectedRowTitle: String?
    let theme: iPodTheme
    let reduceMotion: Bool
    let isImporting: Bool
    let isLoading: Bool
    let loadFailed: Bool
    let hasTracks: Bool
    let shouldShowEmptyLibrary: Bool
    let usesSplitMenu: Bool
    let isMainMenu: Bool
    let isFilterable: Bool
    let isSongs: Bool
    let filterText: Binding<String>
    let canRemoveSelectedTrack: Bool
    let summary: String?
    let failures: [String]
    let failuresExpanded: Binding<Bool>
    let hasLibraryError: Bool
    let preview: MenuArtworkPreview
}

struct LibraryBrowserActions {
    let importMusic: () -> Void
    let removeSelectedSong: () -> Void
    let retryLoad: () -> Void
    let activate: (ClassicPlayerRow) -> Void
    var playNext: (Track) -> Void = { _ in }
    var addLast: (Track) -> Void = { _ in }
}

struct LibraryBrowserView: View {
    let presentation: LibraryBrowserPresentation
    let actions: LibraryBrowserActions
    let titleForRow: (ClassicPlayerRow) -> String
    let subtitleForRow: (ClassicPlayerRow) -> String?

    var body: some View {
        VStack(spacing: 0) {
            if presentation.isImporting { ImportingMusicStatus() }
            if presentation.isFilterable { filterBar }

            LibraryLoadStateView(
                isLoading: presentation.isLoading,
                loadFailed: presentation.loadFailed,
                hasTracks: presentation.hasTracks,
                showsFailureInPlaceOfContent: !presentation.isMainMenu,
                retryAction: actions.retryLoad
            ) {
                destinationContent
            }

            if let summary = presentation.summary {
                ImportReportView(
                    summary: summary,
                    failures: presentation.failures,
                    isExpanded: presentation.failuresExpanded,
                    theme: presentation.theme
                )
            }
            if presentation.loadFailed && !presentation.hasTracks && presentation.isMainMenu {
                LibraryLoadFailurePanel(isLoading: presentation.isLoading, retryAction: actions.retryLoad)
            }
            if presentation.hasLibraryError { LibraryAttentionStatus(theme: presentation.theme) }
        }
    }

    @ViewBuilder
    private var destinationContent: some View {
        if presentation.shouldShowEmptyLibrary && !presentation.usesSplitMenu {
            emptyLibrary
        } else if presentation.usesSplitMenu {
            splitMenu
        } else {
            menuList
        }
    }

    private var filterBar: some View {
        HStack(spacing: 6) {
            Text(String(localized: "Find"))
                .font(.system(size: 12, weight: .semibold))
            TextField(String(localized: "Filter music"), text: presentation.filterText)
                .font(.system(size: 13))
                .textFieldStyle(.plain)
                .accessibilityLabel(String(localized: "Filter music"))
            if presentation.isSongs {
                Button(action: actions.removeSelectedSong) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(presentation.canRemoveSelectedTrack ? Color.red : presentation.theme.palette.secondaryText)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!presentation.canRemoveSelectedTrack)
                .accessibilityIdentifier("library.remove")
                .accessibilityLabel(presentation.selectedRowTitle.map {
                    String.localizedStringWithFormat(String(localized: "Remove %@"), $0)
                } ?? String(localized: "Remove selected song"))
                .accessibilityValue(presentation.selectedRowTitle ?? String(localized: "No song selected"))
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 38)
        .overlay(alignment: .bottom) { presentation.theme.palette.separator.opacity(0.65).frame(height: 1) }
    }

    private var menuList: some View {
        PlayerMenuList(
            rows: presentation.rows,
            selectedRowID: presentation.selectedRowID,
            theme: presentation.theme,
            reduceMotion: presentation.reduceMotion,
            isImporting: presentation.isImporting,
            titleForRow: titleForRow,
            subtitleForRow: subtitleForRow,
            activate: actions.activate,
            playNext: actions.playNext,
            addLast: actions.addLast
        )
    }

    private var splitMenu: some View {
        GeometryReader { proxy in
            if proxy.size.width < 280 {
                menuList
            } else {
                HStack(alignment: .top, spacing: 0) {
                    menuList.frame(width: proxy.size.width * 0.66)
                    presentation.theme.palette.separator.opacity(0.7).frame(width: 1)
                    presentation.preview.frame(width: proxy.size.width * 0.34 - 1, height: proxy.size.height)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private var emptyLibrary: some View {
        VStack(spacing: 8) {
            Text(String(localized: "Your music library is empty."))
                .font(.system(size: 14, weight: .medium))
            Button(action: actions.importMusic) {
                Text(String(localized: "Import Music"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(presentation.theme.palette.selectionText)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(presentation.theme.palette.selection)
            }
            .buttonStyle(.plain)
            .disabled(presentation.isImporting)
            .accessibilityIdentifier("library.import")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(10)
    }
}
