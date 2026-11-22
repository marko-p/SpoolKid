import UIKit
import AVFoundation
import CoreImage
import Vision

enum SmartScanTelemetryContract {
    static let started = "started"
    static let qrCandidate = "qr-candidate"
    static let ocrCandidate = "ocr-candidate"
    static let arbitrationSelected = "arbitration.selected"
    static let reviewOpened = "review.opened"
    static let noDecision = "no-decision"
    static let cancel = "cancel"

    static let statusSteps: Set<String> = [
        started,
        qrCandidate,
        ocrCandidate,
        noDecision,
        cancel
    ]
}

struct UnifiedSmartScannerCallbackDispatcher {
    let schedule: (@escaping () -> Void) -> Void

    static let main = UnifiedSmartScannerCallbackDispatcher { work in
        DispatchQueue.main.async(execute: work)
    }

    func emitStatus(_ message: String, to callback: @escaping (String) -> Void) {
        schedule {
            callback(message)
        }
    }

    func emitOutput(_ output: UnifiedSmartScanOutput, to callback: @escaping (UnifiedSmartScanOutput) -> Void) {
        schedule {
            callback(output)
        }
    }

    func emitCancel(to callback: @escaping () -> Void) {
        schedule {
            callback()
        }
    }
}

struct UnifiedSmartScannerDecisionState {
    private(set) var latestQRCandidate: SmartScanQRCodeCandidate?
    private(set) var latestOCRCandidate: OCRParsedCandidate?
    private(set) var startedAt: Date?
    private(set) var isTerminal = false

    mutating func begin(now: Date) {
        latestQRCandidate = nil
        latestOCRCandidate = nil
        startedAt = now
        isTerminal = false
    }

    mutating func cancel() -> Bool {
        guard !isTerminal else { return false }
        isTerminal = true
        return true
    }

    mutating func applyQRCode(
        _ candidate: SmartScanQRCodeCandidate,
        now: Date,
        profile: SmartScanFastProfile
    ) -> UnifiedSmartScanOutput? {
        guard !isTerminal else { return nil }
        latestQRCandidate = candidate
        return evaluate(now: now, profile: profile)
    }

    mutating func applyOCRCandidate(
        _ candidate: OCRParsedCandidate,
        now: Date,
        profile: SmartScanFastProfile
    ) -> UnifiedSmartScanOutput? {
        guard !isTerminal else { return nil }
        latestOCRCandidate = candidate
        return evaluate(now: now, profile: profile)
    }

    private mutating func evaluate(now: Date, profile: SmartScanFastProfile) -> UnifiedSmartScanOutput? {
        let elapsed = now.timeIntervalSince(startedAt ?? now)
        let decision = SmartScanArbitrationService.decide(
            qrCandidate: latestQRCandidate,
            ocrCandidate: latestOCRCandidate,
            elapsed: elapsed,
            profile: profile
        )
        guard let output = UnifiedSmartScannerViewController.mapDecisionToOutput(decision) else {
            return nil
        }
        isTerminal = true
        return output
    }
}

final class UnifiedSmartScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onOutput: ((UnifiedSmartScanOutput, Data?) -> Void)?
    var onCancel: (() -> Void)?
    var onStatus: ((String) -> Void)?

    private let session = AVCaptureSession()
    private let ciContext = CIContext()
    private let frameLock = NSLock()
    private var latestFrame: CVPixelBuffer?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    private let metadataOutput = AVCaptureMetadataOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.spoolkid.unifiedscanner.session")
    private let ocrQueue = DispatchQueue(label: "com.spoolkid.unifiedscanner.ocr")
    private let callbackDispatcher = UnifiedSmartScannerCallbackDispatcher.main

    private var isSessionConfigured = false
    private var isSessionRunning = false
    private var decisionState = UnifiedSmartScannerDecisionState()
    private var consensusAccumulator = OCRConsensusAccumulator()
    private var isProcessingFrame = false
    private var hasEmittedQRCandidate = false
    private var hasEmittedOCRCandidate = false
    private var hasEmittedNoDecision = false

    // Quality-hint debounce state — updated by applyQualityHint (ocrQueue) and
    // reset at session start (sessionQueue, before frames begin).
    private var qualityPendingHint: OCRFrameQuality.Hint? = nil
    private var qualityPendingCount = 0
    private var qualityEmittedHint: OCRFrameQuality.Hint? = nil
    private weak var qualityHintLabel: UILabel?
    /// The unsettled consensus the fallback button currently shows — what a
    /// tap accepts, so the button never hands over a reading it did not name.
    /// Written and read on `sessionQueue`.
    private var offeredFallback: OCRParsedCandidate?
    private weak var fallbackButton: UIButton?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupPreviewLayer()
        setupCancelButton()
        setupQualityHintLabel()
        setupFallbackButton()
        setupCameraSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sessionQueue.async { [weak self] in
            self?.startSessionIfNeededOnSessionQueue()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [weak self] in
            self?.stopSessionIfRunningOnSessionQueue()
        }
    }

    private func setupCameraSession() {
        sessionQueue.async { [weak self] in
            self?.configureSessionOnSessionQueue()
        }
    }

    private func configureSessionOnSessionQueue() {
        guard !isSessionConfigured else { return }

        session.beginConfiguration()

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else {
            session.commitConfiguration()
            emitStatus("Unable to access camera input.")
            return
        }
        
        // Enable continuous auto-focus for sharper OCR and QR scanning
        do {
            try camera.lockForConfiguration()
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            }
            if camera.isAutoFocusRangeRestrictionSupported {
                camera.autoFocusRangeRestriction = .near
            }
            camera.unlockForConfiguration()
        } catch {
            // Non-fatal - autofocus configuration is best-effort
        }
        
        session.addInput(input)

        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: sessionQueue)
            metadataOutput.metadataObjectTypes = [.qr]
        }

        videoOutput.setSampleBufferDelegate(self, queue: ocrQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        session.commitConfiguration()
        isSessionConfigured = true
    }

    private func setupPreviewLayer() {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        previewLayer = layer
    }

    private func setupCancelButton() {
        let cancelButton = UIButton(type: .system)
        var config = UIButton.Configuration.plain()
        config.title = "Cancel"
        config.baseForegroundColor = .white
        config.background.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        config.background.cornerRadius = 12
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20)
        let titleFont = UIFont.systemFont(ofSize: 18, weight: .semibold)
        config.attributedTitle = AttributedString("Cancel", attributes: AttributeContainer([.font: titleFont]))
        cancelButton.configuration = config
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        view.addSubview(cancelButton)
        NSLayoutConstraint.activate([
            cancelButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cancelButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])
    }

    private func startSessionIfNeededOnSessionQueue() {
        guard isSessionConfigured, !isSessionRunning else { return }
        decisionState.begin(now: Date())
        consensusAccumulator = OCRConsensusAccumulator()
        hasEmittedQRCandidate = false
        hasEmittedOCRCandidate = false
        hasEmittedNoDecision = false
        qualityPendingHint = nil
        qualityPendingCount = 0
        qualityEmittedHint = nil
        offeredFallback = nil
        DispatchQueue.main.async { [weak self] in
            self?.qualityHintLabel?.isHidden = true
            self?.qualityHintLabel?.text = ""
            self?.fallbackButton?.isHidden = true
        }
        emitStatus(SmartScanTelemetryContract.started)
        session.startRunning()
        isSessionRunning = true
    }

    private func stopSessionIfRunningOnSessionQueue() {
        guard isSessionRunning else { return }
        session.stopRunning()
        isSessionRunning = false
    }

    @objc private func cancelTapped() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let shouldNotify = self.decisionState.cancel()
            self.stopSessionIfRunningOnSessionQueue()
            guard shouldNotify else { return }
            self.emitStatus(SmartScanTelemetryContract.cancel)
            self.emitCancel()
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let payload = metadataObject.stringValue else {
            return
        }

        emitQRCandidateIfNeeded()
        let decisionOutput = decisionState.applyQRCode(
            SmartScanQRCodeCandidate(payload: payload, confidence: 1.0),
            now: Date(),
            profile: .default
        )
        if decisionOutput == nil {
            emitNoDecisionIfNeeded()
        }
        finalizeIfNeededOnSessionQueue(decisionOutput)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !isProcessingFrame else {
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        isProcessingFrame = true

        applyQualityHint(OCRFrameQuality.evaluate(luminanceStats(from: pixelBuffer)))

        // Only a reference is kept here; the JPEG is made once, when the scan
        // emits (`latestFrameJPEGData`). Encoding every frame in front of the
        // Vision request slowed recognition on every device for an image of
        // which only the last one was ever used.
        if UserDefaults.standard.bool(forKey: AppConfig.diagnosticsEnabledKey) {
            frameLock.lock()
            latestFrame = pixelBuffer
            frameLock.unlock()
        }

        let request = VNRecognizeTextRequest { [weak self] request, _ in
            guard let self else { return }
            defer { self.isProcessingFrame = false }
            let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
            let items = observations.compactMap { obs -> (text: String, box: CGRect)? in
                guard let text = obs.topCandidates(1).first?.string else { return nil }
                return (text, obs.boundingBox)
            }
            // Reorder into column-major reading order so column-interleaved labels stop flattening
            // into cross-field adjacency. Boxes ride along, index-aligned, for the archive (schema v3).
            let ordered = OCRLineOrderer.orderedItems(items)
            let lines = ordered.map(\.text)
            guard !lines.isEmpty else { return }

            var candidate = OCRFilamentParserService.parse(lines: lines)
            candidate.rawLineBoxes = ordered.map(\.box)
            self.sessionQueue.async { [weak self] in
                guard let self else { return }
                self.consensusAccumulator.ingest(candidate)
                guard self.consensusAccumulator.isStable,
                      let stable = self.consensusAccumulator.consensus else {
                    self.offerFallbackIfDueOnSessionQueue()
                    self.emitOCRCandidateIfNeeded()
                    self.emitNoDecisionIfNeeded()
                    return
                }
                let decisionOutput = self.decisionState.applyOCRCandidate(
                    stable,
                    now: Date(),
                    profile: .default
                )
                self.emitOCRCandidateIfNeeded()
                if decisionOutput == nil {
                    self.emitNoDecisionIfNeeded()
                }
                self.finalizeIfNeededOnSessionQueue(decisionOutput)
            }
        }

        request.recognitionLevel = .accurate

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        do {
            try handler.perform([request])
        } catch {
            isProcessingFrame = false
        }
    }

    // MARK: - Fallback for a reading that never settles

    /// Shows — or refreshes — "Use This Reading" once the accumulator says the
    /// wait is over. Refreshed on every unsettled frame, so the button always
    /// names the vote a tap would take.
    private func offerFallbackIfDueOnSessionQueue() {
        guard !decisionState.isTerminal,
              consensusAccumulator.offersFallback(now: Date()),
              let consensus = consensusAccumulator.consensus else { return }
        offeredFallback = consensus
        let subtitle = Self.fallbackSubtitle(for: consensus)
        DispatchQueue.main.async { [weak self] in
            guard let button = self?.fallbackButton else { return }
            button.configuration?.subtitle = subtitle
            button.isHidden = false
        }
    }

    @objc private func fallbackTapped() {
        sessionQueue.async { [weak self] in
            guard let self, let candidate = self.offeredFallback else { return }
            let output = self.decisionState.applyOCRCandidate(candidate, now: Date(), profile: .default)
            self.finalizeIfNeededOnSessionQueue(output)
        }
    }

    /// What the fallback button says it will take: brand and filament, or
    /// material when no name was built. Nil when the reading names neither.
    nonisolated static func fallbackSubtitle(for candidate: OCRParsedCandidate) -> String? {
        let filament = candidate.filamentName ?? candidate.material
        let parts = [candidate.brand, filament].compactMap { part -> String? in
            guard let part, !part.isEmpty else { return nil }
            return part
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func setupFallbackButton() {
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.filled()
        config.title = "Use This Reading"
        config.baseBackgroundColor = UIColor(named: "AccentColor") ?? .systemOrange
        config.baseForegroundColor = .white
        config.cornerStyle = .large
        config.titleAlignment = .center
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = .systemFont(ofSize: 18, weight: .semibold)
            return attributes
        }
        button.configuration = config
        button.isHidden = true
        button.accessibilityIdentifier = "smartScan.useThisReading"
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(fallbackTapped), for: .touchUpInside)

        view.addSubview(button)
        let anchor = qualityHintLabel?.topAnchor ?? view.safeAreaLayoutGuide.bottomAnchor
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            button.bottomAnchor.constraint(equalTo: anchor, constant: -16),
            button.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            button.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])
        fallbackButton = button
    }

    private func finalizeIfNeededOnSessionQueue(_ output: UnifiedSmartScanOutput?) {
        guard let output else { return }
        stopSessionIfRunningOnSessionQueue()
        emitOutput(output)
    }

    private func emitNoDecisionIfNeeded() {
        guard !hasEmittedNoDecision else { return }
        hasEmittedNoDecision = true
        emitStatus(SmartScanTelemetryContract.noDecision)
    }

    private func emitQRCandidateIfNeeded() {
        guard !hasEmittedQRCandidate else { return }
        hasEmittedQRCandidate = true
        emitStatus(SmartScanTelemetryContract.qrCandidate)
    }

    private func emitOCRCandidateIfNeeded() {
        guard !hasEmittedOCRCandidate else { return }
        hasEmittedOCRCandidate = true
        emitStatus(SmartScanTelemetryContract.ocrCandidate)
    }

    private func setupQualityHintLabel() {
        let label = UILabel()
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.50)
        label.layer.cornerRadius = 8
        label.layer.masksToBounds = true
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -88),
            label.leadingAnchor.constraint(
                greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(
                lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])
        qualityHintLabel = label
    }

    // Samples the Y plane of a YCbCr pixel buffer to compute glare fraction and
    // luminance spread. Every 8th pixel in each dimension is sampled (O(W*H/64)).
    private func luminanceStats(from pixelBuffer: CVPixelBuffer) -> OCRFrameQuality.Stats {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard CVPixelBufferGetPlaneCount(pixelBuffer) > 0,
              let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else {
            return OCRFrameQuality.Stats(glareFraction: 0, luminanceSpread: 1)
        }
        let width  = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let bytes  = base.assumingMemoryBound(to: UInt8.self)
        let step   = 8
        var whiteCount = 0
        var total      = 0
        var minL: Float = 1
        var maxL: Float = 0
        var row = 0
        while row < height {
            var col = 0
            while col < width {
                let lum = Float(bytes[row * stride + col]) / 255.0
                if lum > OCRFrameQuality.glareLuminanceLevel { whiteCount += 1 }
                if lum < minL { minL = lum }
                if lum > maxL { maxL = lum }
                total += 1
                col += step
            }
            row += step
        }
        return OCRFrameQuality.Stats(
            glareFraction:   total > 0 ? Float(whiteCount) / Float(total) : 0,
            luminanceSpread: total > 0 ? maxL - minL : 1
        )
    }

    // Debounces quality hint changes: a hint (or nil) must be seen for
    // `OCRFrameQuality.debounceFrames` consecutive frames before it is emitted.
    private func applyQualityHint(_ hint: OCRFrameQuality.Hint?) {
        if hint == qualityPendingHint {
            qualityPendingCount += 1
        } else {
            qualityPendingHint = hint
            qualityPendingCount = 1
        }
        guard qualityPendingCount >= OCRFrameQuality.debounceFrames,
              qualityPendingHint != qualityEmittedHint else { return }
        qualityEmittedHint = qualityPendingHint
        emitStatus(hint?.rawValue ?? OCRFrameQuality.normalPrompt)
        let labelText = hint?.rawValue ?? ""
        DispatchQueue.main.async { [weak self] in
            guard let label = self?.qualityHintLabel else { return }
            label.text = labelText
            label.isHidden = labelText.isEmpty
        }
    }

    private func emitStatus(_ message: String) {
        callbackDispatcher.emitStatus(message) { [weak self] value in
            self?.onStatus?(value)
        }
    }

    func latestFrameJPEGData() -> Data? {
        frameLock.lock()
        let frame = latestFrame
        frameLock.unlock()
        guard let frame else { return nil }
        return Self.archiveJPEG(from: frame, context: ciContext)
    }

    /// The label image a diagnostics archive carries: the frame with its long
    /// side capped at 1600 px, JPEG quality 0.7.
    nonisolated static func archiveJPEG(from pixelBuffer: CVPixelBuffer, context: CIContext) -> Data? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = ciImage.extent
        let longest = max(extent.width, extent.height)
        let scale: CGFloat = longest > 1600 ? 1600 / longest : 1.0
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.7)
    }

    private func emitOutput(_ output: UnifiedSmartScanOutput) {
        let imageData = latestFrameJPEGData()
        callbackDispatcher.schedule { [weak self] in
            self?.onOutput?(output, imageData)
        }
    }

    private func emitCancel() {
        callbackDispatcher.emitCancel { [weak self] in
            self?.onCancel?()
        }
    }

    static func mapDecisionToOutput(_ decision: SmartScanDecision) -> UnifiedSmartScanOutput? {
        switch decision {
        case .wait:
            return nil
        case .acceptQR(let payload):
            return .qr(payload)
        case .acceptOCR(let candidate):
            return .ocr(candidate)
        }
    }
}
