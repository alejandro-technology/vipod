import SwiftUI

struct PlayerMenuList: View {
    let rows: [ClassicPlayerRow]
    let selectedRowID: String?
    let theme: iPodTheme
    let reduceMotion: Bool
    let isImporting: Bool
    let titleForRow: (ClassicPlayerRow) -> String
    let subtitleForRow: (ClassicPlayerRow) -> String?
    let activate: (ClassicPlayerRow) -> Void
    var selectRow: ((ClassicPlayerRow) -> Void)? = nil
    var playNext: (Track) -> Void = { _ in }
    var addLast: (Track) -> Void = { _ in }
    var favorite: (Track) -> Void = { _ in }
    var playlists: [LibraryPlaylist] = []
    var addToPlaylist: (Track, UUID) -> Void = { _, _ in }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        RetroMenuRow(
                            title: titleForRow(row),
                            subtitle: subtitleForRow(row) ?? row.subtitle,
                            isSelected: row.id == selectedRowID,
                            theme: theme,
                            action: {
                                if case .addToPlaylist = row.action {
                                    (selectRow ?? activate)(row)
                                } else if case .play = row.action {
                                    if row.id == selectedRowID {
                                        activate(row)
                                    } else {
                                        (selectRow ?? activate)(row)
                                    }
                                } else {
                                    activate(row)
                                }
                            }
                        )
                        .disabled(row.id == "menu.import" && isImporting)
                        .accessibilityIdentifier(row.id)
                        .id(row.id)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .onChange(of: selectedRowID) { _, rowID in
                guard let rowID else { return }
                if reduceMotion { proxy.scrollTo(rowID, anchor: .center) }
                else { withAnimation(.easeOut(duration: 0.16)) { proxy.scrollTo(rowID, anchor: .center) } }
            }
            .onAppear {
                if let selectedRowID { proxy.scrollTo(selectedRowID, anchor: .center) }
            }
        }
    }
}
