import SwiftUI

/// A one-line suggestion, shown only when something about the battery stands out.
struct SuggestionCard: View {
    let suggestion: SuggestionEngine.Suggestion

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: suggestion.isWrittenByAI ? "sparkles" : "lightbulb.fill")
                .foregroundStyle(iconStyle)
            Text(suggestion.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 14))
        .help(suggestion.isWrittenByAI ? "Written on this Mac by Apple Intelligence" : "")
    }

    private var iconStyle: AnyShapeStyle {
        guard suggestion.isWrittenByAI else { return AnyShapeStyle(.yellow) }
        return AnyShapeStyle(LinearGradient(colors: [.orange, .pink, .purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}
