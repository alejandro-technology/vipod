import SwiftUI

struct ContextualPlayerAction: Identifiable {
    let id: String
    let title: String
    let icon: String
    let isEnabled: Bool
    let action: () -> Void
}

struct ContextualActionToolbar: View {
    let actions: [ContextualPlayerAction]
    let theme: iPodTheme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                if index > 0 { Spacer(minLength: 0) }
                CircularActionButton(
                    icon: action.icon,
                    label: action.title,
                    theme: theme,
                    isEnabled: action.isEnabled,
                    accessibilityID: action.id,
                    action: action.action
                )
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("context.actions.toolbar")
    }
}
