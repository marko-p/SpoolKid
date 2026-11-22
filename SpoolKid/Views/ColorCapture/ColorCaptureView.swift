//
//  ColorCaptureView.swift
//  SpoolKid
//
//  Purpose: The camera color capture screen. Gates on camera permission, then
//  shows the live preview or the frozen review in one full-screen frame (so the
//  view-to-image mapping is shared), with the sample circle, the draggable card
//  outline, and the close, guide and size controls. Presented full screen;
//  hands back the chosen hex through `onUse`.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import AVFoundation
import SwiftUI

// MARK: - ColorCaptureView

struct ColorCaptureView: View {
    /// Called with the chosen `RRGGBB` hex when the user taps Use Color; the screen then dismisses.
    let onUse: (String) -> Void

    @StateObject private var model: ColorCaptureModel
    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Environment(\.dismiss) private var dismiss

    init(onUse: @escaping (String) -> Void) {
        self.onUse = onUse
        _model = StateObject(wrappedValue: ColorCaptureModel(source: ColorCaptureCamera()))
    }

    var body: some View {
        Group {
            switch cameraStatus {
            case .authorized:
                ColorCaptureScreen(model: model, onUse: use, onClose: { dismiss() })
            case .notDetermined:
                Color.black.ignoresSafeArea()
            default:
                CameraPermissionView(
                    status: cameraStatus,
                    message: "Camera access is off. Turn it on in iOS Settings to capture a spool's color.",
                    onRequest: { Task { await refreshAndRequestAccess() } },
                    onCancel: { dismiss() }
                )
            }
        }
        .preferredColorScheme(.dark)
        .task { await refreshAndRequestAccess() }
    }

    /// Reads the camera status and, when it is undecided, asks for access and reads it again.
    private func refreshAndRequestAccess() async {
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if cameraStatus == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
            cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        }
    }

    private func use(_ hex: String) {
        onUse(hex)
        dismiss()
    }
}

// MARK: - ColorCaptureScreen

/// Live and review, once camera access is granted.
private struct ColorCaptureScreen: View {
    @ObservedObject var model: ColorCaptureModel
    let onUse: (String) -> Void
    let onClose: () -> Void

    /// View-space center of the circle when the current drag began.
    @State private var dragStartCenter: CGPoint?
    /// Bottom edge of the top bar in the stage's space; the card label stays below it.
    @State private var topBarBottom: CGFloat = 0
    /// Top edge of the review panel in screen space; the review photo fills the space above it.
    @State private var reviewPanelTop: CGFloat?

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                stage(size: geometry.size)
            }
            .ignoresSafeArea()

            GeometryReader { available in
                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 0)
                    bottomControls(maxScrollHeight: available.size.height * 0.35)
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear { model.onAppear() }
        .onDisappear { model.onDisappear() }
        .sheet(isPresented: $model.showsGuide, onDismiss: { model.dismissGuide() }) {
            ColorCaptureGuideView(onStart: { model.dismissGuide() })
                .preferredColorScheme(.dark)
        }
    }

    // MARK: Stage

    /// The full-screen camera or photo layer with the circle and the card outline.
    private func stage(size: CGSize) -> some View {
        let photoSize = photoSize(in: size)
        let mapping = model.imageSize.map { AspectFillMapping(viewSize: photoSize, imageSize: $0) }
        // Live fills the screen; review lays the photo out in the space above the panel,
        // so the circle and the card outline are never under it.
        return ZStack(alignment: .top) {
            Color.black
            ZStack {
                Color.black
                if model.phase == .review, let image = model.frozenImage {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .frame(width: photoSize.width, height: photoSize.height)
                        .clipped()
                } else if model.phase != .review {
                    ColorCapturePreview(session: model.previewSession)
                }

                circle(size: photoSize, mapping: mapping)

                if model.phase != .capturing, let card = model.activeCard ?? model.suggestedCard, let mapping {
                    ReferenceCardOutline(
                        card: card,
                        mapping: mapping,
                        minLabelY: topBarBottom + 26,
                        onChange: { model.setUserCard($0) },
                        onRemove: { model.removeCard() },
                        isSuggestion: model.activeCard == nil)
                }
            }
            .frame(width: photoSize.width, height: photoSize.height)
        }
        .frame(width: size.width, height: size.height)
        .coordinateSpace(name: ColorCaptureStageSpace.name)
        .onAppear { updateMapping(size: size) }
        .onChange(of: size) { _, newSize in updateMapping(size: newSize) }
        .onChange(of: model.imageSize) { _, _ in updateMapping(size: size) }
        .onChange(of: model.phase) { _, _ in updateMapping(size: size) }
        .onChange(of: reviewPanelTop) { _, _ in updateMapping(size: size) }
    }

    /// The area the photo (or preview) occupies: the whole stage, except in review, where it ends at the panel.
    private func photoSize(in size: CGSize) -> CGSize {
        guard model.phase == .review, let top = reviewPanelTop, top > 0 else { return size }
        return CGSize(width: size.width, height: min(max(top, 1), size.height))
    }

    private func updateMapping(size: CGSize) {
        let photo = photoSize(in: size)
        guard photo.width > 0, photo.height > 0, let imageSize = model.imageSize else { return }
        model.mapping = AspectFillMapping(viewSize: photo, imageSize: imageSize)
    }

    @ViewBuilder
    private func circle(size: CGSize, mapping: AspectFillMapping?) -> some View {
        let diameter = 2 * model.circleRadius * size.width
        let isReview = model.phase == .review
        let center: CGPoint = {
            if isReview, let mapping { return mapping.viewPoint(fromImage: model.circleCenter) }
            return CGPoint(x: size.width / 2, y: size.height / 2)
        }()
        let hitSize = max(diameter, 44)
        ZStack {
            Circle().stroke(Color.black.opacity(0.5), lineWidth: 4)
            Circle().stroke(Color.white, lineWidth: 2)
        }
        .frame(width: diameter, height: diameter)
        .frame(width: hitSize, height: hitSize)
        .contentShape(Circle())
        .gesture(
            DragGesture(coordinateSpace: .named(ColorCaptureStageSpace.name))
                .onChanged { value in
                    guard isReview, let mapping else { return }
                    // The circle keeps its offset from the finger: start center plus translation.
                    let start = dragStartCenter ?? center
                    dragStartCenter = start
                    // Clamped to the photo rect, so the circle cannot be dragged under the panel.
                    let target = CGPoint(
                        x: min(max(start.x + value.translation.width, 0), mapping.viewSize.width),
                        y: min(max(start.y + value.translation.height, 0), mapping.viewSize.height))
                    model.moveCircle(to: mapping.imagePoint(fromView: target))
                }
                .onEnded { _ in dragStartCenter = nil })
        .position(center)
        .allowsHitTesting(isReview)
    }

    // MARK: Chrome

    private var topBar: some View {
        ZStack {
            HStack {
                chromeButton(systemImage: "xmark", label: "Close", identifier: "colorCapture.close", action: onClose)
                Spacer()
                chromeButton(
                    systemImage: "questionmark", label: "Color capture guide",
                    identifier: "colorCapture.guide") { model.showsGuide = true }
            }
            if model.phase == .live {
                lightPill
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { topBarBottom = proxy.frame(in: .global).maxY }
                    .onChange(of: proxy.frame(in: .global).maxY) { _, newValue in topBarBottom = newValue }
            })
    }

    private var lightPill: some View {
        let tooDark = model.lightLevel == .tooDark
        return Label(tooDark ? "Too dark – add light" : "Light OK", systemImage: tooDark ? "cloud" : "sun.max")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tooDark ? Color.statusWarning : Color.white)
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background(.black.opacity(0.55), in: Capsule())
    }

    private func chromeButton(
        systemImage: String, label: String, identifier: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.55), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private func bottomControls(maxScrollHeight: CGFloat) -> some View {
        if model.phase == .review {
            ColorCaptureReviewView(model: model, maxScrollHeight: maxScrollHeight, onUse: onUse)
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { reviewPanelTop = proxy.frame(in: .global).minY }
                            .onChange(of: proxy.frame(in: .global).minY) { _, newValue in reviewPanelTop = newValue }
                    })
                .onDisappear { reviewPanelTop = nil }
        } else {
            ColorCaptureLiveControls(model: model)
        }
    }
}

// MARK: - ColorCaptureSizeSlider

/// The sample circle's size, shared by live and review.
struct ColorCaptureSizeSlider: View {
    @ObservedObject var model: ColorCaptureModel

    var body: some View {
        HStack(spacing: 12) {
            Text("Size")
                .font(.subheadline)
            Slider(value: $model.circleRadius, in: ColorCaptureModel.radiusRange)
                .accessibilityLabel("Size")
                .accessibilityIdentifier("colorCapture.sizeSlider")
        }
        .frame(minHeight: 44)
    }
}
