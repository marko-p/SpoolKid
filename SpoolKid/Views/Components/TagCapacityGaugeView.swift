import SwiftUI

/// Segmented capacity meter for the OpenPrintTag write flow: NFC-V / Material / URL /
/// Printer countdown (or Printer area) / Free against a nominal ICODE SLIX2 budget.
/// Advisory only.
struct TagCapacityGaugeView: View {
    let breakdown: TagCapacityEstimator.Breakdown

    private var readout: String {
        breakdown.fits
            ? "\(breakdown.total) / \(breakdown.capacity) B"
            : "\(breakdown.total) / \(breakdown.capacity) B · \(breakdown.over) over"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tag capacity · ICODE SLIX2")
                    .font(.subheadline)
                Spacer()
                Text(readout)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(breakdown.fits ? Color.secondary : Color.red)
            }

            GeometryReader { geo in
                let scale = Double(breakdown.fits ? breakdown.capacity : breakdown.total)
                let width = geo.size.width
                HStack(spacing: 0) {
                    bar(width * ratio(breakdown.overhead, scale), Color(.systemGray))
                    bar(width * ratio(breakdown.material, scale), .teal)
                    bar(width * ratio(breakdown.url, scale), .indigo)
                    bar(width * ratio(breakdown.aux, scale), .orange)
                }
            }
            .frame(height: 12)
            .background(Color(.tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            )

            legend
        }
        .padding(.vertical, 2)
    }

    private func ratio(_ bytes: Int, _ scale: Double) -> Double {
        scale > 0 ? min(1, Double(bytes) / scale) : 0
    }

    private func bar(_ width: CGFloat, _ color: Color) -> some View {
        Rectangle().fill(color).frame(width: max(0, width))
    }

    /// Wraps onto a second row: with the countdown segment the legend is wider
    /// than a phone.
    private var legend: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)],
                  alignment: .leading, spacing: 4) {
            legendItem(Color(.systemGray), "NFC-V", breakdown.overhead)
            legendItem(.teal, "Material", breakdown.material)
            if breakdown.url > 0 {
                legendItem(.indigo, "URL", breakdown.url)
            }
            if breakdown.aux > 0 {
                // Only a layout that also wrote a length lets the printer count
                // down; the region is written either way.
                legendItem(.orange, breakdown.countsDown ? "Printer countdown" : "Printer area", breakdown.aux)
            }
            if breakdown.fits {
                legendItem(Color(.tertiarySystemFill), "Free", breakdown.free)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func legendItem(_ color: Color, _ label: String, _ bytes: Int) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 9, height: 9)
                .overlay(RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.primary.opacity(0.15), lineWidth: 0.5))
            Text("\(label) \(bytes) B")
        }
    }
}

#Preview {
    Form {
        Section("Tag capacity") {
            TagCapacityGaugeView(breakdown: .init(material: 100, url: 27, overhead: 31, capacity: 304, aux: 35, countsDown: true))
            TagCapacityGaugeView(breakdown: .init(material: 100, url: 27, overhead: 31, capacity: 304, aux: 35))
            TagCapacityGaugeView(breakdown: .init(material: 260, url: 40, overhead: 31, capacity: 304))
        }
    }
}
