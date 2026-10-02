import SwiftUI

struct ImportReportView: View {
    let summary: String
    let failures: [String]
    @Binding var isExpanded: Bool
    let theme: iPodTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(summary).font(.system(size: 10, weight: .semibold))
            if !failures.isEmpty {
                Button {
                    isExpanded.toggle()
                } label: {
                    Text(isExpanded
                        ? String(localized: "Hide failed files")
                        : String.localizedStringWithFormat(String(localized: "Show %lld failed files"), failures.count))
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("library.importFailures")
                if isExpanded {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(failures, id: \.self) { filename in
                                Text(String.localizedStringWithFormat(String(localized: "Could not import %@"), filename))
                                    .font(.system(size: 9))
                                    .lineLimit(1)
                            }
                        }
                    }
                    .frame(maxHeight: 68)
                    .scrollIndicators(.hidden)
                }
            }
        }
        .foregroundStyle(theme.palette.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }
}
