//
//  FilamentColorEditor.swift
//  SpoolKid
//
//  Purpose: The one editor for a filament's color(s), shared by the filament
//  form and Write Tag. A Single | Multi switch; Single is one hex row, Multi
//  is one row per color plus Add Color and a Coextruded | Gradient pattern.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct FilamentColorEditor: View {
    @Binding var colors: FilamentColors
    /// A tag stores no pattern, so Write Tag hides the picker and its footer.
    let showsPattern: Bool
    /// A leading label row, for a host with no section header of its own.
    let title: String?
    /// The host's TD box, when it shows one: a TD1S color scan also fills it
    /// while it is empty. Nil where there is no TD row (Write Tag, or TD hidden).
    let transmissionDistance: Binding<String>?

    init(
        colors: Binding<FilamentColors>,
        showsPattern: Bool = true,
        title: String? = nil,
        transmissionDistance: Binding<String>? = nil
    ) {
        _colors = colors
        self.showsPattern = showsPattern
        self.title = title
        self.transmissionDistance = transmissionDistance
    }

    var body: some View {
        if let title {
            Text(title)
        }

        Picker("Colors", selection: modeBinding) {
            Text("Single").tag(false)
            Text("Multi").tag(true)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("filamentColorEditor.mode")

        ForEach(colors.hexes.indices, id: \.self) { index in
            HStack {
                FilamentColorRow(
                    hex: hexBinding(at: index),
                    label: colors.isMulti ? "Color \(index + 1)" : "Color",
                    transmissionDistance: transmissionDistance
                )

                if colors.isMulti && colors.hexes.count > 2 {
                    Button {
                        colors.removeColor(at: index)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove color \(index + 1)")
                }
            }
        }

        if colors.isMulti {
            Button {
                colors.addColor()
            } label: {
                Label("Add Color", systemImage: "plus.circle.fill")
                    .frame(minHeight: 44, alignment: .leading)
            }
            .disabled(!colors.canAddColor)

            if showsPattern {
                Picker("Pattern", selection: $colors.pattern) {
                    ForEach(FilamentColors.Pattern.allCases, id: \.self) { pattern in
                        Text(pattern.label).tag(pattern)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("filamentColorEditor.pattern")

                Text("Coextruded: the colors run side by side along the whole spool. Gradient: the color shifts along the spool.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var modeBinding: Binding<Bool> {
        Binding(
            get: { colors.isMulti },
            set: { wantsMulti in
                if wantsMulti { colors.switchToMulti() } else { colors.switchToSingle() }
            }
        )
    }

    private func hexBinding(at index: Int) -> Binding<String> {
        Binding(
            get: { colors.hexes.indices.contains(index) ? colors.hexes[index] : "" },
            set: { if colors.hexes.indices.contains(index) { colors.hexes[index] = $0 } }
        )
    }
}

/// One color row: the hex text, the system picker, the camera capture and the
/// TD1S reading, kept in step.
private struct FilamentColorRow: View {
    @Binding var hex: String
    /// "Color" or "Color N": the well's label; the hex field's adds " hex".
    let label: String
    let transmissionDistance: Binding<String>?
    @State private var showsColorCapture = false
    @State private var showsTD1SRead = false

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: hex) ?? Color.swatchFallback },
            set: { if let picked = $0.toHex(), picked != hex { hex = picked } }
        )
    }

    var body: some View {
        HStack {
            TextField("Hex", text: $hex)
                .textInputAutocapitalization(.characters)
                .disableAutocorrection(true)
                .frame(minHeight: 44)
                .accessibilityLabel("\(label) hex")

            ColorPicker("", selection: colorBinding, supportsOpacity: false)
                .labelsHidden()
                .accessibilityLabel(label)

            if ColorCaptureCamera.isAvailable {
                Button {
                    showsColorCapture = true
                } label: {
                    Image(systemName: "camera")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Capture \(label) with camera")
                .accessibilityIdentifier("filamentColorEditor.capture")
            }

            Button {
                showsTD1SRead = true
            } label: {
                Image(systemName: "eyedropper")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Read \(label) from TD1S")
            .accessibilityIdentifier("filamentColorEditor.td1sRead")
        }
        .fullScreenCover(isPresented: $showsColorCapture) {
            ColorCaptureView { hex = $0 }
        }
        .sheet(isPresented: $showsTD1SRead) {
            TD1SReadView(target: .color) { reading in
                hex = reading.hex
                if let transmissionDistance,
                   let text = reading.transmissionDistanceText(replacing: transmissionDistance.wrappedValue) {
                    transmissionDistance.wrappedValue = text
                }
            }
        }
    }
}
