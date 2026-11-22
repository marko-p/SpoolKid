//
//  OCRReviewView.swift
//  SpoolKid
//
//  Purpose: Allows users to review and edit OCR-detected filament data before registration.
//

import SwiftUI
import UIKit
import os.log

private let ocrReviewLogger = Logger(subsystem: "com.spoolkid", category: "OCRReviewView")

struct OCRReviewView: View {
    let candidate: OCRParsedCandidate
    let capturedImageData: Data?
    let onComplete: (OCRReviewOutcome) -> Void

    static let retakeOutcome: OCRReviewOutcome = .retakeSmartScan

    @AppStorage(AppConfig.diagnosticsEnabledKey) private var saveOCRArchives: Bool = false

    @State private var brand: String
    @State private var material: String
    @State private var filamentName: String
    @State private var subtype: String
    @State private var colorHex: String
    @State private var serialNumber: String
    @State private var diameterMM: String
    @State private var netWeightG: String
    @State private var minNozzle: String
    @State private var maxNozzle: String
    @State private var minBed: String
    @State private var maxBed: String
    @State private var color: Color
    
    init(candidate: OCRParsedCandidate, capturedImageData: Data? = nil, onComplete: @escaping (OCRReviewOutcome) -> Void) {
        self.candidate = candidate
        self.capturedImageData = capturedImageData
        self.onComplete = onComplete
        
        _brand = State(initialValue: candidate.brand ?? "")
        _material = State(initialValue: candidate.material ?? "")
        _filamentName = State(initialValue: candidate.filamentName ?? "")
        _subtype = State(initialValue: candidate.subtype ?? "")
        _colorHex = State(initialValue: candidate.colorHex ?? "FFFFFF")
        _serialNumber = State(initialValue: candidate.serialNumber ?? "")
        _diameterMM = State(initialValue: candidate.diameterMM.map { String(format: "%.2f", $0) } ?? "")
        _netWeightG = State(initialValue: candidate.netWeightG.map(String.init) ?? "")
        _minNozzle = State(initialValue: String(candidate.minNozzleTemp ?? 200))
        _maxNozzle = State(initialValue: String(candidate.maxNozzleTemp ?? 220))
        _minBed = State(initialValue: String(candidate.minBedTemp ?? 60))
        _maxBed = State(initialValue: String(candidate.maxBedTemp ?? 60))
        _color = State(initialValue: Color(hex: candidate.colorHex ?? "FFFFFF") ?? .white)
    }
    
    private var derivedData: FilamentTagData {
        let trimmedFilamentName = filamentName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSubtype = subtype.trimmingCharacters(in: .whitespacesAndNewlines)
        return FilamentTagData(
            name: trimmedFilamentName.isEmpty ? nil : trimmedFilamentName,
            material: material,
            subtype: trimmedSubtype.isEmpty ? nil : trimmedSubtype,
            brand: brand,
            colorHex: colorHex,
            minNozzleTemp: Int(minNozzle) ?? 0,
            maxNozzleTemp: Int(maxNozzle) ?? 0,
            minBedTemp: Int(minBed) ?? 0,
            maxBedTemp: Int(maxBed) ?? 0,
            nominalNetWeight: parsedNetWeightG
        )
    }

    private var parsedNetWeightG: Double? {
        Self.normalizedDouble(netWeightG)
    }

    static func buildScanResult(
        candidate: OCRParsedCandidate,
        tagData: FilamentTagData,
        serialNumber: String,
        diameterMM: String,
        filamentName: String,
        subtype: String,
        netWeightG: String
    ) -> ScanResult {
        let parsedNetWeightG = normalizedDouble(netWeightG)
        var normalizedTagData = tagData
        normalizedTagData.nominalNetWeight = parsedNetWeightG

        return ScanResult(
            cardUID: nil,
            tagData: normalizedTagData,
            format: .ocr,
            ocrSerialNumber: trimmedOrNil(serialNumber),
            ocrDiameterMM: normalizedDouble(diameterMM),
            ocrFilamentName: trimmedOrNil(filamentName),
            ocrSubtype: trimmedOrNil(subtype),
            ocrNominalNetWeightG: parsedNetWeightG
        )
    }

    private static func trimmedOrNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedDouble(_ value: String) -> Double? {
        guard let trimmed = trimmedOrNil(value) else { return nil }
        return Double(trimmed)
    }
    
    private var isValid: Bool {
        derivedData.validate() == nil
    }

    private func buildFinalValues() -> OCRArchiveWorkflow.Final {
        OCRArchiveWorkflow.Final(
            material: Self.trimmedOrNil(material),
            subtype: Self.trimmedOrNil(subtype),
            brand: Self.trimmedOrNil(brand),
            filamentName: Self.trimmedOrNil(filamentName),
            colorHex: Self.trimmedOrNil(colorHex),
            serialNumber: Self.trimmedOrNil(serialNumber),
            diameterMM: Self.normalizedDouble(diameterMM),
            netWeightG: Self.normalizedDouble(netWeightG).map { Int($0) },
            minNozzleTemp: Int(minNozzle),
            maxNozzleTemp: Int(maxNozzle),
            minBedTemp: Int(minBed),
            maxBedTemp: Int(maxBed)
        )
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section("Filament Details") {
                    HStack {
                        Text("Brand")
                        Spacer()
                        OCRConfidenceBadge(confidence: candidate.confidenceByField[.brand] ?? .none)
                        TextField("e.g. Bambu", text: $brand)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Material")
                        Spacer()
                        OCRConfidenceBadge(confidence: candidate.confidenceByField[.material] ?? .none)
                        TextField("e.g. PLA", text: $material)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Filament Name")
                        Spacer()
                        OCRConfidenceBadge(confidence: candidate.confidenceByField[.filamentName] ?? .none)
                        TextField("e.g. Matte PLA", text: $filamentName)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Subtype")
                        Spacer()
                        OCRConfidenceBadge(confidence: candidate.confidenceByField[.subtype] ?? .none)
                        TextField("e.g. Matte", text: $subtype)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Serial")
                        Spacer()
                        OCRConfidenceBadge(confidence: candidate.confidenceByField[.serialNumber] ?? .none)
                        TextField("e.g. 24K01234", text: $serialNumber)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Diameter (mm)")
                        Spacer()
                        OCRConfidenceBadge(confidence: candidate.confidenceByField[.diameterMM] ?? .none)
                        TextField("e.g. 1.75", text: $diameterMM)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Net Weight (g)")
                        Spacer()
                        OCRConfidenceBadge(confidence: candidate.confidenceByField[.netWeightG] ?? .none)
                        TextField("e.g. 1000", text: $netWeightG)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    ColorPicker("Color", selection: $color, supportsOpacity: false)
                        .onChange(of: color) { _, newColor in
                            if let hex = newColor.toHex(), hex != colorHex {
                                colorHex = hex
                            }
                        }
                    HStack {
                        Text("Color Hex")
                        Spacer()
                        TextField("FFFFFF", text: $colorHex)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: colorHex) { _, newHex in
                                if let newColor = Color(hex: newHex), newColor.toHex() != color.toHex() {
                                    color = newColor
                                }
                            }
                    }
                }
                
                Section("Temperatures") {
                    HStack {
                        Text("Nozzle (°C)")
                        Spacer()
                        TextField("Min", text: $minNozzle)
                            .keyboardType(.numberPad)
                            .frame(width: 50)
                        Text("-")
                        TextField("Max", text: $maxNozzle)
                            .keyboardType(.numberPad)
                            .frame(width: 50)
                    }
                    HStack {
                        Text("Bed (°C)")
                        Spacer()
                        TextField("Min", text: $minBed)
                            .keyboardType(.numberPad)
                            .frame(width: 50)
                        Text("-")
                        TextField("Max", text: $maxBed)
                            .keyboardType(.numberPad)
                            .frame(width: 50)
                    }
                }
            }
            .navigationTitle("Review Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onComplete(.cancel) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") {
                        let result = Self.buildScanResult(
                            candidate: candidate,
                            tagData: derivedData,
                            serialNumber: serialNumber,
                            diameterMM: diameterMM,
                            filamentName: filamentName,
                            subtype: subtype,
                            netWeightG: netWeightG
                        )
                        keepCaptureIfDiagnosticsOn()
                        onComplete(.proceedToScanHub(result))
                    }
                    .disabled(!isValid)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Retake Scan") {
                        onComplete(Self.retakeOutcome)
                    }
                }
            }
            .keyboardDoneBar()
        }
    }

    /// Files the reviewed scan for the Diagnostics screen to share later.
    ///
    /// Runs on the way out rather than behind a button: the corrections the
    /// user just made are the most valuable part of a capture, and they only
    /// exist at this moment. Failing is not worth interrupting the scan flow
    /// for — a lost capture costs one sample, a blocked Continue costs the
    /// spool the user was actually adding.
    private func keepCaptureIfDiagnosticsOn() {
        guard saveOCRArchives else { return }
        do {
            let built = try OCRArchiveBuilder().makeArchiveDirectory(
                candidate: candidate,
                final: buildFinalValues(),
                imageData: capturedImageData
            )
            try DiagnosticCaptureStore.keep(built)
            WorkflowTraceStore.log(
                path: "ocr",
                step: "archive.kept",
                details: ["hasImage": capturedImageData != nil ? "true" : "false"]
            )
        } catch {
            ocrReviewLogger.error("Could not keep OCR capture: \(error)")
        }
    }
}
