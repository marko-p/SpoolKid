//
//  MIDICaptureService.swift
//  SpoolKid
//
//  Purpose: Listens to every USB MIDI source the iPhone sees — a Biqu TD1S on
//  firmware 2.0.1+ is one — and records what arrives, for the TD1S capture
//  screen. CoreMIDI reads class-compliant USB MIDI with no MFi and no
//  permission prompt.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Combine
import CoreMIDI
import Foundation
import os

@MainActor
final class MIDICaptureService: ObservableObject {
    @Published private(set) var sources: [MIDICapture.Source] = []
    @Published private(set) var packets: [MIDICapture.Packet] = []
    @Published private(set) var isRecording = false
    @Published private(set) var errorMessage: String?

    private let logger = Logger(subsystem: "com.spoolkid", category: "midi-capture")
    private var port = MIDIPortRef()
    private var setupObserver: NSObjectProtocol?
    private var recordingStartedAt = Date()

    /// The app's one CoreMIDI client, created on first use and never disposed.
    /// Disposing an app's last client lets the MIDI server exit, after which
    /// every MIDIClientCreate in this process fails until the app is killed —
    /// the "TD1S stops working after idling" bug. Ports come and go per screen;
    /// the client stays.
    private static var sharedClient = MIDIClientRef()
    private static let setupChanged = Notification.Name("SpoolKid.MIDISetupChanged")

    private static func client() -> (MIDIClientRef, OSStatus) {
        if sharedClient != 0 { return (sharedClient, noErr) }
        var created = MIDIClientRef()
        let status = MIDIClientCreateWithBlock("SpoolKid TD1S" as CFString, &created) { notification in
            guard notification.pointee.messageID == .msgSetupChanged else { return }
            NotificationCenter.default.post(name: setupChanged, object: nil)
        }
        // A failed create leaves the ref at 0, so the next screen retries.
        if status == noErr { sharedClient = created }
        return (sharedClient, status)
    }

    /// Creates this screen's input port on the shared client and connects
    /// every source present. Called when the screen appears; a second call
    /// is a no-op.
    func start() {
        guard port == 0 else { return }
        errorMessage = nil
        let (client, clientStatus) = Self.client()
        guard clientStatus == noErr else { return fail("CoreMIDI client", clientStatus) }
        // MIDI 1.0 protocol: CoreMIDI then delivers the device's messages as
        // UMP types 1–3, which `UMPDecoder` turns back into MIDI 1.0 bytes.
        let status = MIDIInputPortCreateWithProtocol(client, "Input" as CFString, ._1_0, &port) { [weak self] list, sourceRef in
            let received = Self.packetWords(list)
            let sourceID = Int32(truncatingIfNeeded: Int(bitPattern: sourceRef))
            Task { @MainActor in self?.record(received, from: sourceID) }
        }
        guard status == noErr else {
            port = 0
            return fail("CoreMIDI input port", status)
        }
        setupObserver = NotificationCenter.default.addObserver(
            forName: Self.setupChanged, object: nil, queue: .main
        ) { [weak self] _ in
            // Delivered on the main queue, so already main-actor isolated.
            MainActor.assumeIsolated { self?.connectSources() }
        }
        connectSources()
    }

    /// Releases this screen's port. The shared client is deliberately kept.
    func stop() {
        if let setupObserver { NotificationCenter.default.removeObserver(setupObserver) }
        setupObserver = nil
        if port != 0 { MIDIPortDispose(port) }
        port = 0
        isRecording = false
    }

    func startRecording() {
        packets = []
        recordingStartedAt = Date()
        isRecording = true
    }

    func stopRecording() { isRecording = false }

    /// The recording, frozen with what the TD1S screen showed.
    func capture(note: String, displayedTD: String, displayedHex: String) -> MIDICapture {
        MIDICapture(
            capturedAt: recordingStartedAt, sources: sources, packets: packets,
            note: note, displayedTD: displayedTD, displayedHex: displayedHex
        )
    }

    func discardRecording() {
        packets = []
        isRecording = false
    }

    // MARK: - Internals

    private func connectSources() {
        guard port != 0 else { return }
        var found: [MIDICapture.Source] = []
        for index in 0..<MIDIGetNumberOfSources() {
            let source = MIDIGetSource(index)
            var uniqueID: Int32 = 0
            MIDIObjectGetIntegerProperty(source, kMIDIPropertyUniqueID, &uniqueID)
            // The unique ID rides along as the connection's refCon, so each
            // packet can say which source sent it. Reconnecting an already
            // connected source is harmless.
            MIDIPortConnectSource(port, source, UnsafeMutableRawPointer(bitPattern: Int(uniqueID)))
            found.append(MIDICapture.Source(
                name: Self.string(source, kMIDIPropertyDisplayName) ?? "MIDI source \(index + 1)",
                manufacturer: Self.string(source, kMIDIPropertyManufacturer),
                model: Self.string(source, kMIDIPropertyModel),
                uniqueID: uniqueID
            ))
        }
        sources = found
    }

    private func record(_ received: [[UInt32]], from sourceID: Int32) {
        guard isRecording else { return }
        let name = sources.first { $0.uniqueID == sourceID }?.name ?? "Unknown source"
        let offset = Int(Date().timeIntervalSince(recordingStartedAt) * 1000)
        packets.append(contentsOf: received.map { MIDICapture.Packet(offsetMs: offset, source: name, words: $0) })
    }

    private func fail(_ what: String, _ status: OSStatus) {
        errorMessage = "\(what) could not be created (error \(status))."
        logger.error("\(what, privacy: .public) failed: \(status)")
    }

    /// Copies each packet's words out on CoreMIDI's thread; the list is only
    /// valid for the duration of the callback. Read through a raw pointer so
    /// a packet longer than the struct's fixed 64-word tuple is not cut short.
    nonisolated private static func packetWords(_ list: UnsafePointer<MIDIEventList>) -> [[UInt32]] {
        list.unsafeSequence().map { packet in
            let count = Int(packet.pointee.wordCount)
            let offset = MemoryLayout<MIDIEventPacket>.offset(of: \.words) ?? 0
            let words = UnsafeRawPointer(packet).advanced(by: offset).assumingMemoryBound(to: UInt32.self)
            return Array(UnsafeBufferPointer(start: words, count: count))
        }
    }

    private static func string(_ object: MIDIObjectRef, _ property: CFString) -> String? {
        var value: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(object, property, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
