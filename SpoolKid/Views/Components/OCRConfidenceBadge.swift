import SwiftUI

struct OCRConfidenceBadge: View {
    let confidence: OCRFieldConfidence
    
    var body: some View {
        Text(confidence.rawValue.capitalized)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor.opacity(0.2))
            .foregroundColor(backgroundColor)
            .clipShape(Capsule())
    }
    
    private var backgroundColor: Color {
        switch confidence {
        case .high: return .green
        case .medium: return .yellow
        case .low: return .red
        case .none: return .gray
        }
    }
}

#Preview {
    VStack {
        OCRConfidenceBadge(confidence: .high)
        OCRConfidenceBadge(confidence: .medium)
        OCRConfidenceBadge(confidence: .low)
        OCRConfidenceBadge(confidence: .none)
    }
    .padding()
}
