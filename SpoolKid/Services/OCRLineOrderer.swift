import CoreGraphics

/// Orders OCR text lines by their on-label geometry: group into columns by horizontal overlap,
/// read each column top-to-bottom, columns left-to-right. Boxes are Vision-normalized with the
/// origin bottom-left, so a larger `midY` is higher on the label. Pure; CoreGraphics only.
nonisolated enum OCRLineOrderer {
    /// Minimum horizontal-overlap ratio (of the narrower box) for a line to join a column. Tunable.
    static let columnOverlapThreshold: CGFloat = 0.5
    /// A box at least this fraction of the total content width is a full-width line (title/banner),
    /// not a column member. Without this, a wide title's box overlaps every column and collapses
    /// them into one. Tunable.
    static let fullWidthFraction: CGFloat = 0.6

    /// Ordered text in column-major reading order.
    static func order(_ items: [(text: String, box: CGRect)]) -> [String] {
        orderedItems(items).map(\.text)
    }

    /// Same ordering as `order`, but returns the `(text, box)` pairs so callers (e.g. the scanner)
    /// can keep each line paired with its box — used to archive geometry aligned with the lines
    /// actually fed to the parser.
    static func orderedItems(_ items: [(text: String, box: CGRect)]) -> [(text: String, box: CGRect)] {
        guard items.count > 1 else { return items }

        // Full-width lines (titles/banners) are emitted first, top-to-bottom, ahead of the
        // columnar body — otherwise their wide box overlaps every column and merges them all.
        // (Simplest rule that handles top titles; a full-width footer would still sort to the
        // front, which the current corpus doesn't need.)
        let totalMinX = items.map { $0.box.minX }.min() ?? 0
        let totalMaxX = items.map { $0.box.maxX }.max() ?? 1
        let totalWidth = max(totalMaxX - totalMinX, 0.0001)
        let fullWidth = items.filter { $0.box.width / totalWidth >= fullWidthFraction }
        let body = items.filter { $0.box.width / totalWidth < fullWidthFraction }
        guard !fullWidth.isEmpty else { return columnMajor(body) }
        return fullWidth.sorted { $0.box.midY > $1.box.midY } + columnMajor(body)
    }

    /// Column-major ordering of the (non-full-width) body: group by horizontal overlap, columns
    /// left-to-right, each top-to-bottom.
    private static func columnMajor(_ items: [(text: String, box: CGRect)]) -> [(text: String, box: CGRect)] {
        guard items.count > 1 else { return items }

        // Build columns: sweep left-to-right, joining each line to the first column it overlaps.
        let sorted = items.sorted { $0.box.minX < $1.box.minX }
        var columns: [[(text: String, box: CGRect)]] = []
        var ranges: [(lo: CGFloat, hi: CGFloat)] = []
        for item in sorted {
            let lo = item.box.minX, hi = item.box.maxX
            if let idx = ranges.firstIndex(where: { overlapRatio($0.lo, $0.hi, lo, hi) >= columnOverlapThreshold }) {
                columns[idx].append(item)
                ranges[idx] = (min(ranges[idx].lo, lo), max(ranges[idx].hi, hi))
            } else {
                columns.append([item])
                ranges.append((lo, hi))
            }
        }

        // Columns left-to-right; within a column, top-to-bottom (midY descending).
        let ordered = zip(columns, ranges).sorted { $0.1.lo < $1.1.lo }
        return ordered.flatMap { column, _ in
            column.sorted { $0.box.midY > $1.box.midY }
        }
    }

    /// Overlap of [a1,a2] and [b1,b2] as a fraction of the narrower interval's width (0 if either is empty).
    private static func overlapRatio(_ a1: CGFloat, _ a2: CGFloat, _ b1: CGFloat, _ b2: CGFloat) -> CGFloat {
        let overlap = max(0, min(a2, b2) - max(a1, b1))
        let narrower = min(a2 - a1, b2 - b1)
        guard narrower > 0 else { return 0 }
        return overlap / narrower
    }
}
