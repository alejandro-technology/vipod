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
    var playNext: (Track) -> Void = { _ in }
    var addLast: (Track) -> Void = { _ in }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        HStack(spacing: 4) {
                            RetroMenuRow(
                                title: titleForRow(row),
                                subtitle: subtitleForRow(row) ?? row.subtitle,
                                isSelected: row.id == selectedRowID,
                                theme: theme,
                                action: { activate(row) }
                            )
                            .disabled(row.id == "menu.import" && isImporting)
                            .accessibilityIdentifier(row.id)
                            if case .play(let track, _) = row.action {
                                Menu {
                                    Button(String(localized: "Play Next"), systemImage: "text.insert") { playNext(track) }
                                        .accessibilityIdentifier("track.queueNext.\(track.id.uuidString)")
                                    Button(String(localized: "Add to Queue"), systemImage: "text.append") { addLast(track) }
                                        .accessibilityIdentifier("track.queueLast.\(track.id.uuidString)")
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                        .frame(width: 40, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .accessibilityLabel(String.localizedStringWithFormat(String(localized: "Actions for %@"), track.title))
                                .accessibilityIdentifier("track.actions.\(track.id.uuidString)")
                            }
                        }
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
