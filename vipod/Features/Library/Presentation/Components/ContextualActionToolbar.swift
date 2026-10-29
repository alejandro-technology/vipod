import SwiftUI

struct ContextualPlayerAction: Identifiable {
    let id: String
    let title: String
    let accessibilityLabel: String?
    let icon: String
    let isEnabled: Bool
    let action: () -> Void
}

struct ContextualActionToolbar: View {
    let actions: [ContextualPlayerAction]
    let theme: iPodTheme

    var body: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)
            ForEach(actions) { action in
                CircularActionButton(
                    icon: action.icon,
                    label: action.title,
                    theme: theme,
                    isEnabled: action.isEnabled,
                    accessibilityID: action.id,
                    accessibilityLabel: action.accessibilityLabel,
                    action: action.action
                )
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("context.actions.toolbar")
    }
}
