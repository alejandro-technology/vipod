import SwiftUI

struct CollectionAddition: Identifiable {
    let title: String
    let identifier: String
    let action: () -> Void

    var id: String { identifier }
}

struct CollectionRowsView: View {
    let rows: [ClassicPlayerRow]
    let selectedRowID: String?
    let theme: iPodTheme
    let emptyMessage: String
    let openIdentifier: (ClassicPlayerRow) -> String
    let activate: (ClassicPlayerRow) -> Void
    var selectRow: ((ClassicPlayerRow) -> Void)? = nil
    var reduceMotion = false
    var touchSelectOnly = false
    let actions: (ClassicPlayerRow) -> AnyView
    var additions: [CollectionAddition] = []
    var footerAction: CollectionAddition?

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(spacing: 0) {
                if rows.isEmpty {
                    CollectionMessageView(message: emptyMessage, theme: theme)
                }
                ForEach(rows) { row in
                    HStack(spacing: 4) {
                        RetroMenuRow(
                            title: row.title,
                            subtitle: row.subtitle,
                            isSelected: row.id == selectedRowID,
                            theme: theme,
                            action: {
                                if touchSelectOnly || isTrackRow(row) {
                                    (selectRow ?? activate)(row)
                                }
                                else { activate(row) }
                            }
                        )
                        .accessibilityIdentifier(openIdentifier(row))
                        .id(row.id)
                        actions(row)
                    }
                }
                ForEach(additions) { addition in
                    RetroMenuRow(title: addition.title, isSelected: false, theme: theme, action: addition.action)
                        .accessibilityIdentifier(addition.identifier)
                }
                if let footerAction {
                    RetroMenuRow(title: footerAction.title, isSelected: false, theme: theme, action: footerAction.action)
                        .accessibilityIdentifier(footerAction.identifier)
                }
            }
        }
        .scrollIndicators(.hidden)
        .onChange(of: selectedRowID) { _, id in
            guard let id else { return }
            if reduceMotion { proxy.scrollTo(id, anchor: .center) }
            else { withAnimation(.easeOut(duration: 0.16)) { proxy.scrollTo(id, anchor: .center) } }
        }
        .onChange(of: rows.map(\.id)) { _, _ in
            guard let selectedRowID else { return }
            if reduceMotion { proxy.scrollTo(selectedRowID, anchor: .center) }
            else { withAnimation(.easeOut(duration: 0.16)) { proxy.scrollTo(selectedRowID, anchor: .center) } }
        }
        .onAppear { if let selectedRowID { proxy.scrollTo(selectedRowID, anchor: .center) } }
        }
    }

    private func isTrackRow(_ row: ClassicPlayerRow) -> Bool {
        if case .play = row.action { return true }
        return false
    }
}

struct CollectionMessageView: View {
    let message: String
    let theme: iPodTheme

    var body: some View {
        Text(message)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(theme.palette.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .padding(.horizontal, 10)
            .accessibilityIdentifier("collections.empty")
    }
}
