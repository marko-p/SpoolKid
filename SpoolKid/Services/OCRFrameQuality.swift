/// Cheap per-frame luminance quality assessment for the OCR camera feed.
/// Pure, `nonisolated`, unit-testable with synthetic `Stats` inputs.
nonisolated enum OCRFrameQuality {

    // MARK: - Thresholds (named constants)

    /// Fraction of sampled pixels above `glareLuminanceLevel` that triggers the glare hint.
    static let glarePixelFraction: Float = 0.12
    /// Full-range luminance (0–1) above which a pixel counts as near-white.
    static let glareLuminanceLevel: Float = 0.97
    /// Luminance spread (max–min, 0–1) below which the contrast hint fires.
    static let contrastMinSpread: Float = 0.20
    /// Consecutive frames a condition must persist before the hint is shown or cleared.
    static let debounceFrames = 3
    /// Status text emitted via `onStatus` when no quality issue is detected.
    static let normalPrompt = "Point camera at the filament label"

    // MARK: - Hint

    enum Hint: String {
        case glare    = "Reduce glare"
        case contrast = "More light / move closer"
    }

    // MARK: - Stats (pure value type; populated from a pixel buffer in the VC)

    struct Stats {
        /// Fraction of sampled Y-plane pixels whose luminance exceeds `glareLuminanceLevel`.
        let glareFraction: Float
        /// Max–min sampled luminance (0–1 range).
        let luminanceSpread: Float
    }

    // MARK: - Evaluation

    static func evaluate(_ stats: Stats) -> Hint? {
        if stats.glareFraction >= glarePixelFraction { return .glare }
        if stats.luminanceSpread < contrastMinSpread { return .contrast }
        return nil
    }
}
