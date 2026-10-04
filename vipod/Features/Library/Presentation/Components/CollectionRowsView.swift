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
    let actions: (ClassicPlayerRow) -> AnyView
    var additions: [CollectionAddition] = []
    var footerAction: CollectionAddition?

    var body: some View {
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
                            action: { activate(row) }
                        )
                        .accessibilityIdentifier(openIdentifier(row))
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
