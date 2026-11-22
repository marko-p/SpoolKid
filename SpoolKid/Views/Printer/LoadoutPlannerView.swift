//
//  LoadoutPlannerView.swift
//  SpoolKid
//
//  Purpose: Color Matching: a picture, the colours picked from
//  it, and the material. Reached from the Library's Color grouping, printer
//  or no printer.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import PhotosUI
import SwiftUI

enum LoadoutSpools {
    /// The active spools as the planner sees them.
    static func planner(_ spools: [Spool]) -> [LoadoutPlanner.Spool] {
        spools.compactMap { spool in
            let colors = spool.filament.colors
            guard let hex = colors.primaryHex, let material = spool.filament.material else { return nil }
            return LoadoutPlanner.Spool(
                id: spool.id, filamentID: spool.filament.id, title: spool.listTitle, material: material, hex: hex,
                remaining: spool.remainingWeight ?? 0, isMultiColor: colors.isMulti,
                colorHexes: colors.isMulti ? colors.hexes : []
            )
        }
    }

    /// The base material most spools with enough left are made of.
    static func commonMaterial(_ spools: [LoadoutPlanner.Spool], minimumRemaining: Double) -> String? {
        let bases = spools.filter { $0.remaining >= minimumRemaining }.map { MaterialPairing.baseMaterial($0.material) }
        return Dictionary(grouping: bases) { $0 }.max { $0.value.count < $1.value.count }?.key
    }
}

struct LoadoutPlannerView: View {
    /// Where the colors come from when the screen is opened from a shortcut.
    enum Start: Hashable {
        case camera
        case photo(PhotosPickerItem)
    }

    /// Nil opens the screen with nothing chosen yet.
    var start: Start? = nil

    @EnvironmentObject private var store: SpoolDataStore
    @AppStorage(AppConfig.loadoutMinimumRemainingKey) private var minimumRemaining = 10.0
    @AppStorage(AppConfig.loadoutIncludesMultiColorKey) private var includesMultiColor = false

    @State private var image: UIImage?
    @State private var planner: PlannerImage?
    @State private var picks = LoadoutPicks()
    @State private var material = ""
    @State private var takingPhoto = false
    @State private var suggestCount = 4
    @State private var problem: String?
    @State private var planning = false
    /// A pick whose marker was tapped, to confirm removing it.
    @State private var removing: LoadoutPicks.Pick?
    @State private var choosingPhoto = false
    /// Take Photo in the photo sheet: the camera opens once that sheet is gone.
    @State private var cameraAfterSheet = false
    /// The start runs once, not again on returning from a pushed screen.
    @State private var started = false

    private var spools: [LoadoutPlanner.Spool] { LoadoutSpools.planner(store.activeSpools) }
    private var materials: [String] {
        Set(spools.map { MaterialPairing.baseMaterial($0.material) }).sorted()
    }

    var body: some View {
        List {
            imageSection
            if !picks.picks.isEmpty { colorsSection }
            materialSection
            Section {
                Button("Match Colors") { planning = true }
                .disabled(picks.picks.isEmpty || material.isEmpty)
            }
            if let problem {
                Text(problem).font(.body).foregroundStyle(.red)
            }
        }
        .navigationTitle("Color Matching")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $planning) {
            LoadoutPlanView(
                picks: picks, material: material, minimumRemaining: minimumRemaining, includesMultiColor: includesMultiColor
            )
        }
        .sheet(isPresented: $choosingPhoto, onDismiss: {
            if cameraAfterSheet { cameraAfterSheet = false; takingPhoto = true }
        }) {
            PhotoSourceSheet {
                cameraAfterSheet = true
                choosingPhoto = false
            } onPhoto: { item in
                choosingPhoto = false
                load(item)
            }
        }
        .onAppear {
            pickMaterial()
            guard !started else { return }
            started = true
            switch start {
            case .camera: takingPhoto = CameraCaptureView.isAvailable
            case .photo(let item): load(item)
            case nil: break
            }
        }
        .confirmationDialog(
            removingTitle,
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible,
            presenting: removing
        ) { pick in
            Button("Remove Color", role: .destructive) { picks.remove(id: pick.id) }
        }
        .sheet(isPresented: $takingPhoto) {
            CameraCaptureView { data in
                takingPhoto = false
                if let data, let photo = UIImage(data: data) { use(photo) }
            }
            .ignoresSafeArea()
        }
    }

    private var imageSection: some View {
        Section {
            if let image {
                PlannerImageView(image: image, picks: picks.picks, onTap: tapped) { removing = $0 }
                Stepper("Suggest \(suggestCount) Colors", value: $suggestCount, in: 2...LoadoutPicks.cap)
                Button("Suggest Colors") { suggest() }
            }
            Button { choosingPhoto = true } label: {
                Label(image == nil ? "Choose a Photo" : "Choose Another Photo", systemImage: "photo")
            }
        } header: {
            Text("Pick Colors From")
        } footer: {
            Text(image == nil
                 ? "Colors are read as the photo shows them, with no white balance correction."
                 : "Tap the picture to pick a color. Tap a number to remove its color.")
        }
    }

    private var colorsSection: some View {
        Section {
            ForEach(picks.picks) { pick in
                HStack(spacing: 12) {
                    FilamentSwatch(colors: FilamentColors(hexes: [pick.hex], pattern: .coextruded), size: 32)
                    Text(pick.hex).font(.body.monospaced())
                }
                .contextMenu {
                    Button("Remove", role: .destructive) { picks.remove(id: pick.id) }
                }
            }
            .onMove { picks.move(from: $0, to: $1) }
            .onDelete { offsets in
                offsets.map { picks.picks[$0].id }.forEach { picks.remove(id: $0) }
            }
        } header: {
            HStack {
                Text("Colors")
                Spacer()
                EditButton().textCase(nil)
            }
        }
    }

    private var materialSection: some View {
        Section {
            Picker("Primary Material", selection: $material) {
                ForEach(materials, id: \.self) { Text($0).tag($0) }
            }
            Stepper("At Least \(Int(minimumRemaining)) g Left", value: $minimumRemaining, in: 0...1000, step: 10)
            Toggle("Include Multi-Color Spools", isOn: $includesMultiColor)
        } header: {
            Text("Material")
        } footer: {
            if includesMultiColor {
                Text("A multi-color spool can match on any of its colors, but it always prints all of them.")
            }
        }
    }

    private func tapped(_ point: CGPoint) {
        guard let hex = planner?.color(at: point) else { return }
        let added = picks.add(hex: hex, point: .init(x: point.x, y: point.y))
        problem = added ? nil : "\(LoadoutPicks.cap) colors is the most you can pick."
    }

    private func suggest() {
        for suggested in planner?.suggestedColors(count: suggestCount) ?? [] {
            picks.add(hex: suggested.hex, point: .init(x: suggested.point.x, y: suggested.point.y))
        }
    }

    private var removingTitle: String {
        guard let removing, let index = picks.picks.firstIndex(where: { $0.id == removing.id }) else { return "Remove Color" }
        return "Remove Color \(index + 1)?"
    }

    private func use(_ photo: UIImage) {
        guard let read = PlannerImage(image: photo) else {
            problem = "This picture can't be read."
            return
        }
        image = photo
        planner = read
        // The picks belong to the picture they were tapped on.
        picks = LoadoutPicks()
        problem = nil
    }

    private func load(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self), let photo = UIImage(data: data) {
                use(photo)
            } else {
                problem = "This picture can't be read."
            }
        }
    }

    /// A visit starts empty; nothing is kept between visits (owner, 2026-11-13).
    private func pickMaterial() {
        if material.isEmpty || !materials.contains(material) {
            material = LoadoutSpools.commonMaterial(spools, minimumRemaining: minimumRemaining) ?? ""
        }
    }
}

/// The picture with a numbered marker on each pick. Tapping a marker asks to
/// remove its pick; tapping anywhere else picks a color.
private struct PlannerImageView: View {
    let image: UIImage
    let picks: [LoadoutPicks.Pick]
    let onTap: (CGPoint) -> Void
    let onTapMarker: (LoadoutPicks.Pick) -> Void

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .overlay {
                GeometryReader { proxy in
                    ZStack(alignment: .topLeading) {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { location in
                                onTap(CGPoint(x: location.x / proxy.size.width, y: location.y / proxy.size.height))
                            }
                        ForEach(Array(picks.enumerated()), id: \.element.id) { index, pick in
                            if let point = pick.point {
                                Button { onTapMarker(pick) } label: {
                                    Text("\(index + 1)")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                        .frame(width: 24, height: 24)
                                        .background(Circle().fill(.black.opacity(0.7)))
                                        .overlay(Circle().stroke(.white, lineWidth: 1))
                                        // A finger-sized target around the small marker.
                                        .frame(width: 44, height: 44)
                                        .contentShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Color \(index + 1), \(pick.hex)")
                                .accessibilityHint("Asks to remove this color.")
                                .position(x: point.x * proxy.size.width, y: point.y * proxy.size.height)
                            }
                        }
                    }
                }
            }
            .listRowInsets(EdgeInsets())
            .accessibilityLabel("Picture. Tap to pick a color.")
    }
}
