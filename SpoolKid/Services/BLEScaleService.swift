//
//  BLEScaleService.swift
//  SpoolKid
//
//  Purpose: Talk to a Bluetooth kitchen scale. It discovers, connects,
//  subscribes, records a transcript — and, for scales in the AiLink/Elink
//  family, reads the weight (`AiLinkScaleFrame`), learning what the scale
//  means by zero from the way it rests (`AiLinkScaleZero`: the weight is
//  XORed with a per-scale mask, and the mask is the empty-pan reading). Plain-grams scales that zero themselves
//  (`CAScaleFrame`, #21) are read too.
//
//  Lives at app level rather than inside a view: connecting takes seconds, and
//  a scale that reconnects every time a screen appears is unusable on a bench.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Combine
import CoreBluetooth
import os

@MainActor
final class BLEScaleService: NSObject, ObservableObject {

    /// Why the radio cannot be used, when it cannot. Distinguished because the
    /// remedies are different and only one of them is the user's to perform.
    enum Availability: Equatable {
        case unknown
        case unsupported
        case unauthorized
        case poweredOff
        case ready

        var message: String? {
            switch self {
            case .ready, .unknown: return nil
            case .unsupported: return "This device has no Bluetooth LE radio."
            case .unauthorized: return "SpoolKid is not allowed to use Bluetooth. Turn it on for SpoolKid in the iOS Settings app, under Privacy & Security."
            case .poweredOff: return "Bluetooth is switched off. Turn it on in Control Centre or the iOS Settings app."
            }
        }
    }

    /// The one scale this phone weighs with.
    ///
    /// Kept rather than picked per screen because a household owns one kitchen
    /// scale, and being asked to choose it again on every spool is the friction
    /// the owner reported (2026-09-09). The identifier is CoreBluetooth's
    /// per-app peripheral UUID, which is stable across launches — the same key
    /// the learned zero is filed under.
    struct Paired: Codable, Equatable {
        let id: UUID
        let name: String
    }

    struct Discovery: Identifiable, Equatable {
        let id: UUID
        /// Not `let`: a peripheral often advertises anonymously and names itself
        /// a moment later, and a row that stays "(unnamed)" for the rest of the
        /// scan is a row the user cannot identify.
        var name: String
        var rssi: Int
        var advertised: [String]

        /// A peripheral broadcasting no name at all is normal and still worth
        /// listing — a scale may only name itself after connecting.
        static let unnamed = "(unnamed)"
    }

    /// The scale set up in Settings, if there is one. Nil is the whole gate:
    /// no paired scale means no radio, no permission prompt, and no scale
    /// controls on the weighing screens.
    @Published private(set) var paired: Paired?

    @Published private(set) var availability: Availability = .unknown
    @Published private(set) var discoveries: [Discovery] = []
    @Published private(set) var isScanning = false
    @Published private(set) var connected: Discovery?
    @Published private(set) var isConnecting = false
    /// The peripheral this capture is OF, which is not the same as the one
    /// currently on the other end of a link. It survives a disconnect, because
    /// a transcript shared after the scale powered off must still say which
    /// scale it was — the first owner capture said "(not connected)" and
    /// "(not discovered)" for exactly this reason (2026-09-08).
    @Published private(set) var device: Discovery?
    /// The link dropped but we did not ask it to, so a reconnect is pending.
    /// Kitchen scales power down after a few idle seconds; the tester should
    /// be able to put a weight on and have the stream simply resume.
    @Published private(set) var isReconnecting = false
    @Published private(set) var profile: [BLEServiceProfile] = []
    @Published private(set) var log: [BLELogEntry] = []
    private var zero = AiLinkScaleZero()
    /// The most recent frame the decoder understood, and how many notifications
    /// have arrived, both FOR THE CURRENT DEVICE. Held rather than found by
    /// walking `log`, which is shared with the explorer: after exploring one
    /// scale, the next scale would inherit the first one's evidence — and be
    /// called readable, or unreadable, on the strength of it.
    private var latestFrame: AiLinkScaleWeightFrame?
    private var packetsForDevice = 0
    private var silenceWatch: Task<Void, Never>?
    private var lastDecodedGrams: Int?
    @Published private(set) var lastError: String?

    /// What the scale is showing, when SpoolKid can read it. Nil covers all
    /// three of "no scale", "not an AiLink scale" and "its zero is not known
    /// yet" — a screen offering a weight has to be sure of one thing only,
    /// which is that there IS one.
    @Published private(set) var reading: AiLinkScaleReading?
    @Published private(set) var readingAt: Date?
    /// True once a zero has been learned or set. Separated from `reading` so a
    /// screen can say "learning…" rather than looking broken while the scale
    /// is mid-burst on its very first use.
    @Published private(set) var knowsZero = false
    /// Whether the frame behind `reading` is what the scale is showing. The
    /// link drops every five seconds, and a drop in the second before the
    /// settled frame left the screen saying "wait" about a reading that would
    /// never settle (owner, 2026-09-25).
    @Published private(set) var heldFrame: AiLinkScaleZero.HeldFrame = .none

    /// A weighing session pushes a few packets a second; a capture left running
    /// while the user fetches another spool should not grow without bound. The
    /// oldest entries go first — a protocol reveals itself in the most recent
    /// exchange, not the first one.
    static let logCapacity = 2000

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var captureDirectory: URL?
    /// Whether the user still wants this peripheral. Set by `connect`, cleared
    /// only by `disconnect` — every other way the link ends is a drop to be
    /// recovered from, not an instruction to stop.
    private var wantsConnection = false
    /// Characteristics the user has switched OFF. Auto-subscribe consults this
    /// on every reconnect: this scale hangs up every five seconds, and without
    /// it a tester who turns one off watches it come back on moments later —
    /// which is exactly what happened when the owner tried to isolate FEE0
    /// (2026-09-08). A choice the app undoes on its own is not a control.
    private var optedOut: Set<String> = []
    private var markCount = 0
    private let logger = Logger(subsystem: "com.spoolkid", category: "ble")

    /// Asked for before the radio was ready. CoreBluetooth reports its state
    /// asynchronously, so a screen that scans or connects in `onAppear` beats
    /// the answer there — and the request was silently dropped, which is one
    /// half of why the weighing screens listed no scales at all (2026-09-09).
    private var pendingScan = false
    private var pendingConnect = false
    /// A scale asked for by identifier that iOS no longer knows. iOS forgets a
    /// peripheral it has not seen for a while, and `retrievePeripherals` then
    /// comes back empty; until 2026-09-25 that ended the reconnect right there,
    /// with the row still promising one. Now it is looked for by scan, and
    /// `didDiscover` connects the moment it advertises.
    private var awaitedPeripheral: Discovery?
    /// How long before a connect the radio gave up on is tried again.
    static let retryDelay: Duration = .seconds(2)
    /// Signal strength per peripheral, smoothed. Kept beside `discoveries`
    /// rather than inside them so the samples are not republished ten times a
    /// second along with the list.
    private var signals: [UUID: RollingRSSI] = [:]

    override init() {
        super.init()
        paired = Self.storedPairing()
    }

    /// Nil until `start()`. Constructing `CBCentralManager` is what triggers
    /// the system permission prompt, so it is deliberately not done in `init`:
    /// the prompt belongs to the moment the user opens the scale screen, not
    /// to app launch.
    func start() {
        guard central == nil else { return }
        central = CBCentralManager(delegate: self, queue: .main)
    }

    /// Look for peripherals.
    ///
    /// `allowDuplicates` is what keeps signal strength live: without it a
    /// peripheral is reported once and its RSSI never moves again. The jitter
    /// that costs is answered by averaging (`RollingRSSI`), not by seeing less.
    func startScan() {
        guard let central, central.state == .poweredOn else {
            pendingScan = true
            return
        }
        pendingScan = false
        discoveries = []
        signals = [:]
        lastError = nil
        // No service filter. The whole point is that this scale's services are
        // unknown; filtering on a guessed UUID would hide the device we came
        // to find.
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        isScanning = true
    }

    func stopScan() {
        pendingScan = false
        central?.stopScan()
        isScanning = false
    }

    func connect(_ discovery: Discovery) {
        guard let central else { return }
        stopScan()
        guard let found = central.retrievePeripherals(withIdentifiers: [discovery.id]).first else {
            awaitedPeripheral = discovery
            wantsConnection = true
            isConnecting = true
            startScan()
            return
        }
        awaitedPeripheral = nil
        // Trying a second scale must let go of the first. Without this the old
        // link stays open with nothing holding a reference to it, and its
        // notifications keep arriving in the same transcript.
        if let previous = peripheral, previous.identifier != discovery.id {
            central.cancelPeripheralConnection(previous)
        }
        peripheral = found
        found.delegate = self
        if device?.id != discovery.id {
            latestFrame = nil
            packetsForDevice = 0
        }
        device = discovery
        // A scale is taught its zero once, not once per session. Restoring
        // BEFORE the first notification arrives is what stops the screen
        // flashing "learning" at a scale it already knows.
        restoreZero(for: discovery.id)
        wantsConnection = true
        isConnecting = true
        central.connect(found)
    }

    func disconnect() {
        wantsConnection = false
        isReconnecting = false
        if awaitedPeripheral != nil {
            awaitedPeripheral = nil
            isConnecting = false
            stopScan()
        }
        guard let central, let peripheral else { return }
        central.cancelPeripheralConnection(peripheral)
    }

    /// Disconnect AND let go of the device.
    ///
    /// `disconnect()` deliberately keeps `device` — the explorer treats it as
    /// the session record, so clearing a dropped link does not cost the
    /// identity of the scale still on the bench. The weighing screens want the
    /// opposite: "Disconnect" there means "I am finished with this scale", and
    /// the row has to offer to choose one again.
    func forget() {
        disconnect()
        device = nil
        reading = nil
        readingAt = nil
        knowsZero = false
        heldFrame = .none
        latestFrame = nil
        packetsForDevice = 0
    }

    /// Subscribing is the point of the screen: a notify-only scale says nothing
    /// until something asks it to.
    func setNotifying(_ on: Bool, characteristicUUID: String) {
        if on { optedOut.remove(characteristicUUID) } else { optedOut.insert(characteristicUUID) }
        guard let peripheral,
              let characteristic = characteristic(peripheral, uuid: characteristicUUID) else { return }
        peripheral.setNotifyValue(on, for: characteristic)
    }

    /// Whether anything has been switched off, so the screen can say so rather
    /// than leaving a tester wondering whether their choice took.
    var hasOptOuts: Bool { !optedOut.isEmpty }

    /// Sends bytes to a characteristic and records what was sent, in line with
    /// whatever comes back.
    ///
    /// Returns whether the write was issued. A control that reports success for
    /// a write it could not perform would send a tester hunting for a reply to
    /// a command that never left the phone.
    @discardableResult
    func write(_ bytes: Data, characteristicUUID: String) -> Bool {
        guard let peripheral,
              let characteristic = characteristic(peripheral, uuid: characteristicUUID) else {
            lastError = "That characteristic is not available right now."
            return false
        }
        let withResponse = characteristic.properties.contains(.write)
        guard withResponse || characteristic.properties.contains(.writeWithoutResponse) else {
            lastError = "\(characteristicUUID) cannot be written to."
            return false
        }
        peripheral.writeValue(bytes, for: characteristic, type: withResponse ? .withResponse : .withoutResponse)
        append(BLELogEntry(at: Date(), content: .note(
            "\(BLETranscript.sentPrefix) \(BLETranscript.hex(bytes)) to \(characteristicUUID)"
        )))
        return true
    }

    func read(characteristicUUID: String) {
        guard let peripheral,
              let characteristic = characteristic(peripheral, uuid: characteristicUUID) else { return }
        peripheral.readValue(for: characteristic)
    }

    /// Files what the scale's own display reads right now, in line with the
    /// bytes around it, optionally with a photograph of that display.
    ///
    /// The photo is written to disk immediately rather than held in memory:
    /// a session can carry a dozen of them, and a capture that runs out of
    /// memory at the bench loses everything recorded before it.
    func mark(grams: Double?, photo: Data? = nil) {
        var filename: String?
        if let photo {
            markCount += 1
            let name = String(format: "mark-%02d.jpg", markCount)
            do {
                try photo.write(to: photoDirectory().appendingPathComponent(name))
                filename = name
            } catch {
                // The number is still worth keeping. Losing the photo demotes
                // the mark to unverified; refusing the mark loses it entirely.
                logger.error("Could not store mark photo: \(error.localizedDescription, privacy: .public)")
                markCount -= 1
            }
        }
        append(BLELogEntry(at: Date(), content: .mark(grams: grams, photo: filename)))
    }

    /// How long the scale has been silent. The single most important number on
    /// the screen while marking: a mark taken during a silence cannot be
    /// matched to a reading by anyone, ever, and the tester is the only person
    /// who can still do something about it (owner capture, 2026-09-08 — all
    /// three marks landed in gaps of 20s, 24s and 12s).
    var lastReadingAt: Date? {
        let principal = BLETranscript.principalStream(of: log)?.characteristic
        return log.last { entry in
            guard case .packet(let uuid, _) = entry.content else { return false }
            return principal == nil || uuid == principal
        }?.at
    }

    /// Empties the capture. The device and its service tree are deliberately
    /// kept: clearing a false start should not cost the identity of the scale
    /// still sitting on the bench.
    func clearLog() {
        log = []
        markCount = 0
        if let captureDirectory {
            try? FileManager.default.removeItem(at: captureDirectory)
            self.captureDirectory = nil
        }
    }

    /// The transcript plus every photo, as one zip.
    ///
    /// Built on demand rather than kept current: it is only wanted at the end
    /// of a session, and a stale bundle handed to a Share sheet is worse than
    /// none.
    func makeBundle() throws -> URL {
        let workDir = try DiagnosticBundle.makeWorkDirectory(kind: "scale-capture")
        try Data(transcript.utf8).write(to: workDir.appendingPathComponent("transcript.txt"))
        if let captureDirectory {
            for name in (try? FileManager.default.contentsOfDirectory(atPath: captureDirectory.path)) ?? [] {
                try? FileManager.default.copyItem(
                    at: captureDirectory.appendingPathComponent(name),
                    to: workDir.appendingPathComponent(name)
                )
            }
        }
        return try DiagnosticBundle.zip(directory: workDir)
    }

    /// How many marks carry a photo, and how many do not. Shown on the screen
    /// so a tester can see they have evidence rather than finding out after
    /// the scale is back in its box.
    var markCounts: (verified: Int, unverified: Int, unmatchable: Int) {
        // Packet times pulled out once. Asking `nearestPacketGap` to walk the
        // whole log per mark would rescan two thousand entries a dozen times
        // on every redraw, and this is read from a view body.
        let principal = BLETranscript.principalStream(of: log)
        // Only the stream carrying a reading counts. FFE3's constant hello
        // arrives once per reconnect and says nothing about the weight.
        let packetTimes = log.compactMap { entry -> Date? in
            guard case .packet(let uuid, _) = entry.content else { return nil }
            guard principal == nil || uuid == principal?.characteristic else { return nil }
            return entry.at
        }
        return log.reduce(into: (0, 0, 0)) { counts, entry in
            guard case .mark(_, let photo) = entry.content else { return }
            if photo == nil { counts.1 += 1 } else { counts.0 += 1 }
            let gap = packetTimes.map { abs($0.timeIntervalSince(entry.at)) }.min()
            let spread = principal?.spreadFraction(
                around: entry.at, in: log, window: BLETranscript.matchableWindow
            )
            // A scale that has settled and gone quiet is stable, not absent.
            if BLETranscript.settledWeight(before: entry.at, in: log) != nil { return }
            let tooFar = (gap ?? .greatestFiniteMagnitude) > BLETranscript.matchableWindow
            let tooLively = (spread ?? 0) > BLEStreamDigest.steadyFraction
            if tooFar || tooLively { counts.2 += 1 }
        }
    }

    /// How many marks there are, without the cost of judging each one.
    var markTotal: Int {
        log.count { if case .mark = $0.content { return true } else { return false } }
    }

    var packetCount: Int {
        log.count { if case .packet = $0.content { return true } else { return false } }
    }

    var transcript: String {
        BLETranscript.text(
            title: device?.name ?? "(never connected)",
            identifier: device?.id.uuidString ?? "—",
            advertised: device?.advertised ?? [],
            profile: profile,
            entries: log
        )
    }

    /// What the bytes captured so far amount to, per characteristic. Recomputed
    /// from the log rather than accumulated, so it can never disagree with the
    /// transcript that ships beside it.
    var digests: [BLEStreamDigest] {
        BLEStreamDigest.digests(for: log)
    }

    // MARK: - Internals

    /// Created on the first photo, not on connect: a session that never marks
    /// anything leaves nothing behind in `tmp`.
    private func photoDirectory() throws -> URL {
        if let captureDirectory { return captureDirectory }
        let url = try DiagnosticBundle.makeWorkDirectory(kind: "scale-photos")
        captureDirectory = url
        return url
    }

    private func characteristic(_ peripheral: CBPeripheral, uuid: String) -> CBCharacteristic? {
        peripheral.services?
            .compactMap { $0.characteristics }
            .flatMap { $0 }
            .first { $0.uuid.uuidString == uuid }
    }

    private func append(_ entry: BLELogEntry) {
        log.append(entry)
        if log.count > Self.logCapacity {
            log.removeFirst(log.count - Self.logCapacity)
        }
    }

    /// CoreBluetooth reports permissions as one word each; the user needs the
    /// sentence, so `Availability` carries it.
    private func availability(for state: CBManagerState) -> Availability {
        switch state {
        case .poweredOn: return .ready
        case .poweredOff: return .poweredOff
        case .unauthorized: return .unauthorized
        case .unsupported: return .unsupported
        case .resetting, .unknown: return .unknown
        @unknown default: return .unknown
        }
    }

    fileprivate func properties(of characteristic: CBCharacteristic) -> String {
        var names: [String] = []
        let p = characteristic.properties
        if p.contains(.read) { names.append("read") }
        if p.contains(.write) { names.append("write") }
        if p.contains(.writeWithoutResponse) { names.append("write-no-response") }
        if p.contains(.notify) { names.append("notify") }
        if p.contains(.indicate) { names.append("indicate") }
        return names.isEmpty ? "none" : names.joined(separator: ", ")
    }

    fileprivate func rebuildProfile() {
        guard let peripheral, let services = peripheral.services else {
            profile = []
            return
        }
        profile = services.map { service in
            BLEServiceProfile(
                uuid: service.uuid.uuidString,
                characteristics: (service.characteristics ?? []).map { characteristic in
                    BLECharacteristicProfile(
                        uuid: characteristic.uuid.uuidString,
                        properties: properties(of: characteristic),
                        isNotifying: characteristic.isNotifying,
                        canNotify: characteristic.properties.contains(.notify)
                            || characteristic.properties.contains(.indicate),
                        canRead: characteristic.properties.contains(.read),
                        canWrite: characteristic.properties.contains(.write)
                            || characteristic.properties.contains(.writeWithoutResponse)
                    )
                }
            )
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEScaleService: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        availability = availability(for: central.state)
        if central.state == .poweredOn {
            // Whatever was asked for before the radio answered. Without this a
            // screen's `onAppear` scan is thrown away and the list stays empty
            // forever, which is exactly what it did (owner, 2026-09-09).
            if pendingConnect {
                pendingConnect = false
                ensureConnected()
            } else if wantsConnection, connected == nil, !isConnecting, !isReconnecting,
                      let target = awaitedPeripheral ?? device {
                // The radio went away with a link or a connect pending, and
                // CoreBluetooth cancelled both. Nothing else asks again: the
                // screen that did is still on display and will not re-appear.
                connect(target)
            }
            if pendingScan { startScan() }
        }
        if central.state != .poweredOn {
            isScanning = false
            connected = nil
            isConnecting = false
            isReconnecting = false
            // `profile` survives: it is part of the capture, not part of the
            // link, and the tester may still want to share what they recorded.
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = peripheral.name
            ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? Discovery.unnamed
        let advertised = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?
            .map(\.uuidString) ?? []
        signals[peripheral.identifier, default: RollingRSSI()].add(RSSI.intValue)
        let discovery = Discovery(
            id: peripheral.identifier,
            name: name,
            rssi: signals[peripheral.identifier]?.average ?? RSSI.intValue,
            advertised: advertised
        )
        if let index = discoveries.firstIndex(where: { $0.id == discovery.id }) {
            // Updated in place rather than appended: `allowDuplicates` re-reports
            // the same peripheral several times a second, and a list that grows
            // a row each time is unusable.
            if discoveries[index].name == Discovery.unnamed && name != Discovery.unnamed {
                discoveries[index].name = name
            }
            // Assigned only when it moved: this fires ten times a second, and
            // every assignment republishes the whole list.
            if discoveries[index].rssi != discovery.rssi {
                discoveries[index].rssi = discovery.rssi
            }
            if !advertised.isEmpty { discoveries[index].advertised = advertised }
        } else {
            discoveries.append(discovery)
        }
        if let awaited = awaitedPeripheral, awaited.id == peripheral.identifier {
            connect(awaited)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnecting = false
        let resolved = discoveries.first { $0.id == peripheral.identifier }
            ?? device
            ?? Discovery(id: peripheral.identifier, name: peripheral.name ?? Discovery.unnamed, rssi: 0, advertised: [])
        connected = resolved
        device = resolved
        append(BLELogEntry(at: Date(), content: .note(isReconnecting ? "reconnected" : "connected to \(resolved.name)")))
        isReconnecting = false
        peripheral.discoverServices(nil)
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        isConnecting = false
        lastError = error?.localizedDescription ?? "Could not connect to that peripheral."
        logger.error("BLE connect failed: \(error?.localizedDescription ?? "unknown", privacy: .public)")

        // A connect the radio gave up on is not a scale the user gave up on.
        // A failure mid-reconnect used to leave `isReconnecting` set, which
        // `ensureConnected()` refuses on, so nothing ever tried again while
        // the row said "SpoolKid reconnects on its own" (2026-09-25).
        guard wantsConnection, peripheral == self.peripheral else {
            isReconnecting = false
            return
        }
        isReconnecting = true
        let id = peripheral.identifier
        Task { [weak self] in
            try? await Task.sleep(for: Self.retryDelay)
            // A radio that went away meanwhile reconnects from
            // `centralManagerDidUpdateState` instead.
            guard let self, self.wantsConnection, self.connected == nil,
                  let central = self.central, central.state == .poweredOn,
                  let existing = self.peripheral, existing.identifier == id
            else { return }
            central.connect(existing)
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        connected = nil
        isConnecting = false
        // `profile` and `device` are NOT cleared — they are the record of what
        // was captured, and the transcript is usually shared after the scale
        // has gone to sleep.
        for index in profile.indices {
            for inner in profile[index].characteristics.indices {
                profile[index].characteristics[inner].isNotifying = false
            }
        }
        let reason = error?.localizedDescription ?? "closed by the app"
        let droppedAt = Date()
        append(BLELogEntry(at: droppedAt, content: .note("\(BLETranscript.dropPrefix) — \(reason)")))
        // Whatever the scale sends until the link is back is lost, and that
        // can be the very frame that settles the reading on screen.
        zero.observeLinkDrop(at: droppedAt)
        heldFrame = zero.heldFrame(at: droppedAt)
        if let error {
            logger.error("BLE disconnected: \(error.localizedDescription, privacy: .public)")
        }

        // A scale that powers itself down after a few idle seconds is normal,
        // and re-finding it by hand each time makes a marked-weight session
        // impossible. CoreBluetooth holds a connect request open indefinitely,
        // so the stream simply resumes when the scale wakes.
        if wantsConnection, let existing = self.peripheral {
            isReconnecting = true
            lastError = nil
            central.connect(existing)
        } else {
            self.peripheral = nil
            if let error { lastError = error.localizedDescription }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLEScaleService: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            lastError = error.localizedDescription
            return
        }
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics(nil, for: service)
        }
        rebuildProfile()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error {
            lastError = error.localizedDescription
            return
        }
        // Subscribed automatically, not offered as a switch to find and flip.
        // A notify-only scale says nothing until asked, the ask costs nothing,
        // and the first owner session lost most of its window to hunting for
        // toggles before the scale powered down (2026-09-08). The switches
        // remain, for turning a noisy characteristic back OFF.
        for characteristic in service.characteristics ?? [] where
            (characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate))
            && !optedOut.contains(characteristic.uuid.uuidString) {
            peripheral.setNotifyValue(true, for: characteristic)
        }
        rebuildProfile()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            lastError = error.localizedDescription
            append(BLELogEntry(at: Date(), content: .note(
                "could not subscribe to \(characteristic.uuid.uuidString): \(error.localizedDescription)"
            )))
        } else {
            append(BLELogEntry(at: Date(), content: .note(
                "\(characteristic.isNotifying ? "subscribed to" : "unsubscribed from") \(characteristic.uuid.uuidString)"
            )))
        }
        rebuildProfile()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            lastError = error.localizedDescription
            return
        }
        guard let data = characteristic.value else { return }
        append(BLELogEntry(
            at: Date(),
            content: .packet(characteristic: characteristic.uuid.uuidString, data: data)
        ))
        packetsForDevice += 1
        noteWeight(in: data)
    }
}


// MARK: - Reading a weight

extension BLEScaleService {

    /// Feed a notification to the decoders. Frames that are neither AiLink nor
    /// plain-grams weight frames fall straight through: the explorer still
    /// records everything, and a scale from another family simply never
    /// produces a reading. Internal for tests.
    func noteWeight(in data: Data) {
        let frame: AiLinkScaleWeightFrame
        if let aiLink = AiLinkScaleFrame.weightFrame(from: data) {
            frame = aiLink
        } else if let plain = CAScaleFrame.weightFrame(from: data) {
            // The scale zeroes itself, so nothing is learned for it. Its mask, 0,
            // is still persisted, so the next connection knows the zero before
            // the first frame instead of asking for an empty pan.
            if zero.learnsZero { zero = .selfZeroing }
            frame = plain
        } else {
            return
        }
        // Reading a weight IS the pairing. Nothing else is worth remembering a
        // scale for, and a "paired" scale that never produces a number would
        // put a dead control on two screens. This also pairs a scale explored
        // from Diagnostics — correctly: if it decodes, it is supported.
        confirmPairing()
        latestFrame = frame
        let arrivedAt = Date()
        zero.observe(value: frame.masked, isSettled: frame.isSettled, at: arrivedAt)
        heldFrame = zero.heldFrame(at: arrivedAt)
        publishReading(frame)
        watchForSilence()
    }

    /// True once any packet has parsed as a weight frame SpoolKid understands.
    /// The explorer says so loudly: for a scale in a family we already read,
    /// the whole exploration collapses into a confirmation.
    var canDecode: Bool { latestFrame != nil }

    /// Record what the tester has stated is an empty pan, and take it as zero.
    /// One button doing both, because they are the same fact.
    func markPanEmpty() {
        setZeroToCurrentReading()
        append(BLELogEntry(at: Date(), content: .panEmpty))
    }

    private func publishReading(_ frame: AiLinkScaleWeightFrame) {
        knowsZero = zero.mask != nil
        guard let grams = zero.grams(of: frame.masked) else {
            reading = nil
            return
        }
        reading = AiLinkScaleReading(grams: grams, isSettled: frame.isSettled, sequence: frame.sequence)
        readingAt = Date()
        fileDecodedWeight(grams, isSettled: frame.isSettled)
    }

    /// File a settled weight into the transcript, once per plateau.
    ///
    /// Once per plateau and not once per packet: a settled scale repeats itself
    /// until the load changes, and a transcript with the same line four hundred
    /// times is a transcript nobody reads.
    private func fileDecodedWeight(_ grams: Int, isSettled: Bool) {
        guard isSettled, grams != lastDecodedGrams else { return }
        lastDecodedGrams = grams
        append(BLELogEntry(at: Date(), content: .decoded(grams: grams)))
    }

    /// A scale that has stopped talking is resting, and a rest it did not mark
    /// settled is an empty pan. Retrospective detection would be simpler but
    /// only notices at the NEXT burst — which is one spool too late, since the
    /// silence before the first spool is the one that teaches the zero.
    ///
    /// The first wait is the follow-up window: past it, the frame held is
    /// either final or cut off, and the screen can say which.
    private func watchForSilence() {
        silenceWatch?.cancel()
        silenceWatch = Task { [weak self] in
            try? await Task.sleep(for: .seconds(AiLinkScaleZero.followUpWindow))
            guard !Task.isCancelled, let self else { return }
            self.heldFrame = self.zero.heldFrame(at: Date())
            try? await Task.sleep(for: .seconds(AiLinkScaleZero.restingSilence - AiLinkScaleZero.followUpWindow))
            guard !Task.isCancelled else { return }
            self.zero.observeSilence()
            self.knowsZero = self.zero.mask != nil
            self.persistZero()
            // Publish straight away. The zero is learned FROM the silence, so
            // waiting for the next packet to show a weight means waiting for
            // the scale to be disturbed — 35 seconds of blank screen on the
            // owner's device (2026-09-08), which read as "it does not work".
            if let frame = self.latestFrame { self.publishReading(frame) }
        }
    }

    /// Take the current reading as an empty pan. The correction the screens
    /// offer when the number disagrees with the scale's own display.
    ///
    /// Only against a frame that can be the empty pan. The one SpoolKid holds
    /// may be the spool on its way off, cut short by a link drop; zeroing
    /// against that saves a zero a spool's weight out, and the next spool
    /// reads roughly double.
    func setZeroToCurrentReading() {
        guard let value = zero.zeroCandidate(at: Date()), let frame = latestFrame else { return }
        zero.setZero(value)
        publishReading(frame)
        persistZero()
    }

    /// Whether the frame held can be taken as the empty pan. Read by views;
    /// `heldFrame` publishes the moment it can change.
    var canSetZero: Bool { zero.zeroCandidate(at: Date()) != nil }

    // MARK: Remembering it

    /// Load the zero learned for this peripheral on a previous run, so a scale
    /// is taught once rather than once per session.
    func restoreZero(for peripheral: UUID) {
        zero = AiLinkScaleZero(mask: Self.storedMasks()[peripheral.uuidString])
        knowsZero = zero.mask != nil
        heldFrame = .none
        reading = nil
        lastDecodedGrams = nil
        // A scale we already know should show its weight without waiting to be
        // disturbed, if the capture already holds a frame.
        if let frame = latestFrame { publishReading(frame) }
    }

    private func persistZero() {
        guard let mask = zero.mask, let id = device?.id else { return }
        var masks = Self.storedMasks()
        guard masks[id.uuidString] != mask else { return }
        masks[id.uuidString] = mask
        guard let encoded = try? JSONEncoder().encode(masks) else { return }
        UserDefaults.standard.set(encoded, forKey: AppConfig.bleScaleZeroMasksKey)
    }

    // MARK: - The paired scale

    /// Bring the paired scale back, if there is one.
    ///
    /// Called from the weighing screens on appear. Cheap and idempotent: an
    /// existing link is left alone, and there is nothing to do at all for a
    /// user who has never set a scale up — which is what keeps the Bluetooth
    /// permission prompt off screens about spools.
    func ensureConnected() {
        guard let paired else { return }
        start()
        guard connected?.id != paired.id, !isConnecting, !isReconnecting else { return }
        guard let central, central.state == .poweredOn else {
            pendingConnect = true
            return
        }
        connect(Discovery(id: paired.id, name: paired.name, rssi: 0, advertised: []))
    }

    /// Remember the connected scale, once it has proved it can be read.
    ///
    /// The proof is the point. "Connected" is not a working scale — four of the
    /// owner's sessions connected to a scale nobody could read a gram from.
    private func confirmPairing() {
        guard let device, paired?.id != device.id else { return }
        let entry = Paired(id: device.id, name: device.name)
        paired = entry
        guard let encoded = try? JSONEncoder().encode(entry) else { return }
        UserDefaults.standard.set(encoded, forKey: AppConfig.bleScalePairedKey)
    }

    /// Let go of the scale entirely — the link, the reading, and the memory of
    /// it. Its learned zero stays: re-pairing the same scale should not make
    /// the user teach it again.
    func unpair() {
        paired = nil
        UserDefaults.standard.removeObject(forKey: AppConfig.bleScalePairedKey)
        forget()
    }

    private static func storedPairing() -> Paired? {
        guard let data = UserDefaults.standard.data(forKey: AppConfig.bleScalePairedKey) else { return nil }
        return try? JSONDecoder().decode(Paired.self, from: data)
    }

    private static func storedMasks() -> [String: UInt16] {
        guard let data = UserDefaults.standard.data(forKey: AppConfig.bleScaleZeroMasksKey),
              let masks = try? JSONDecoder().decode([String: UInt16].self, from: data)
        else { return [:] }
        return masks
    }
}
