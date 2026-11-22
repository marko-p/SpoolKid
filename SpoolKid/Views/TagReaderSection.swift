//
//  TagReaderSection.swift
//  SpoolKid
//
//  Purpose: Backend screen section for SpoolKid as a Spoolman 0.27 tag
//  reader (spec 3): the switch, the name Spoolman shows, and Pair with
//  Spoolman, which makes SpoolKid appear in Spoolman's Recent Readers.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct TagReaderSection: View {
    @EnvironmentObject private var store: SpoolDataStore
    @AppStorage(AppConfig.tagReaderEnabledKey) private var isEnabled: Bool = true
    @AppStorage(AppConfig.tagReaderNameKey) private var storedName: String = ""
    @State private var readerID = ""
    @State private var isPairing = false
    @State private var pairOutcome: TagScanReportOutcome?
    /// The name the last pairing report carried; the result names it, not
    /// whatever the field says now.
    @State private var pairedName = ""

    private var model: String { UIDevice.current.model }

    var body: some View {
        Section {
            Toggle("Act as Spoolman Tag Reader", isOn: $isEnabled)
            LabeledContent("Reader Name") {
                TextField("", text: $storedName, prompt: Text(TagReaderIdentity.defaultName(model: model)))
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .onChange(of: storedName) { _, newValue in
                        let limited = TagReaderIdentity.limited(newValue)
                        if limited != newValue { storedName = limited }
                    }
            }
            Button {
                pair()
            } label: {
                HStack {
                    Text("Pair with Spoolman")
                    Spacer()
                    if isPairing { ProgressView() }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .disabled(!isEnabled || isPairing)
            if let pairOutcome {
                Text(TagReaderText.pairingResult(pairOutcome, name: pairedName))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Tag Reader")
        } footer: {
            Text(TagReaderText.footer(readerID: readerID))
        }
        // Read (and, the first time, generated) here rather than in `body`,
        // which must not write settings.
        .onAppear { readerID = TagReaderIdentity.readerID() }
    }

    private func pair() {
        isPairing = true
        pairOutcome = nil
        let report = TagScanReporter.pairingReport(model: model)
        pairedName = report.name
        Task {
            pairOutcome = await store.reportTagScan(report)
            isPairing = false
        }
    }
}
