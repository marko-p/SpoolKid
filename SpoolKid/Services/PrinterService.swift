//
//  PrinterService.swift
//  SpoolKid
//
//  Purpose: The one connection to the printer: live toolhead state, and writes
//  that report success only once the printer's own state shows them. One shared
//  instance from `ContentView`.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Combine
import Foundation
import os.log

enum PrinterConnection: Equatable {
    case notConfigured
    case connecting
    /// The printer answered and wants a sign-in.
    case needsSignIn
    case online
    case offline(String)
}

/// How a toolhead write ended. Only `.confirmed` means the printer shows it.
enum ToolheadWriteOutcome: Equatable {
    case confirmed
    case notConfirmed
    case failed(String)

    var message: String? {
        switch self {
        case .confirmed: nil
        case .notConfirmed: "The printer accepted this but does not show it. Check the toolhead."
        case .failed(let reason): reason
        }
    }
}

@MainActor
final class PrinterService: ObservableObject {
    @Published private(set) var connection: PrinterConnection = .notConfigured
    @Published private(set) var toolheads: [ToolheadState] = []
    @Published private(set) var activity: PrinterActivity = .idle
    @Published private(set) var capabilities: PrinterCapabilities?
    /// What became of the app's assignments, by toolhead index.
    @Published private(set) var notes: [Int: ToolheadNote] = [:]
    /// The Spoolman the printer itself uses, when it has one.
    @Published private(set) var spoolmanServer: String?
    /// The FilaMan server FilaMan's Moonraker component reports to, when the
    /// printer runs it. Only `[filaman] server` is read, never its `api_key`.
    @Published private(set) var filamanServer: String?
    /// The SpoolKid RFID Writer plugin, as the printer reports it.
    @Published private(set) var tagPlugin: PrinterTagPlugin = .notInstalled

    let profile = PrinterProfile.snapmakerU1

    private var transport: PrinterTransport?
    private var status: [String: [String: Any]] = [:]
    /// The printer's object list from connect, which says whether the plugin is there.
    private var objects: [String] = []
    private var watch = ToolheadAssignmentWatch(address: "")
    private let makeTransport: @MainActor (URL) -> PrinterTransport
    private let fetchText: (URL, [String: String]) async -> String?
    /// A POST's HTTP status, nil when nothing answered.
    private let post: (URL, [String: String]) async -> Int?
    /// The base the socket connected on; HTTP calls go to the same place.
    private var base: String?
    private let readCredentials: () -> String?
    private let writeCredentials: (String?) -> Bool
    private let pause: () async -> Void
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.spoolkid", category: "PrinterService")

    private static let subscribed = ["print_task_config", "filament_detect", "print_stats", "virtual_sdcard"]

    init(
        defaults: UserDefaults = .standard,
        makeTransport: @escaping @MainActor (URL) -> PrinterTransport = { MoonrakerSocket(url: $0) },
        fetchText: @escaping (URL, [String: String]) async -> String? = PrinterService.fetchTextOverHTTP,
        post: @escaping (URL, [String: String]) async -> Int? = PrinterService.postOverHTTP,
        readCredentials: @escaping () -> String? = { KeychainStore.read(account: KeychainStore.printerCredentialsAccount) },
        writeCredentials: @escaping (String?) -> Bool = { json in
            json.map { KeychainStore.save($0, account: KeychainStore.printerCredentialsAccount) }
                ?? KeychainStore.delete(account: KeychainStore.printerCredentialsAccount)
        },
        pause: @escaping () async -> Void = { try? await Task.sleep(for: .milliseconds(300)) }
    ) {
        self.defaults = defaults
        self.makeTransport = makeTransport
        self.fetchText = fetchText
        self.post = post
        self.readCredentials = readCredentials
        self.writeCredentials = writeCredentials
        self.pause = pause
        if !(defaults.string(forKey: AppConfig.printerAddressKey) ?? "").isEmpty { connection = .connecting }
    }

    var address: String { defaults.string(forKey: AppConfig.printerAddressKey) ?? "" }

    /// A printer is set up once its address could be connected to; the
    /// Printer tab is shown only then.
    nonisolated static func isConfigured(address: String) -> Bool {
        !candidateBases(for: address.trimmingCharacters(in: .whitespaces)).isEmpty
    }

    /// Forgets the printer and its sign-in; the Printer tab hides again.
    func remove() {
        disconnect()
        _ = writeCredentials(nil)
        defaults.removeObject(forKey: AppConfig.printerAddressKey)
        connection = .notConfigured
    }

    /// The web server first, where the extended firmware and Bespok3D serve
    /// Moonraker, then Moonraker's own port, which stock uses. A typed port is
    /// used as it is.
    nonisolated static func candidateBases(for typed: String) -> [String] {
        guard case .success(let address) = ServerAddress.parse(typed),
              let components = URLComponents(string: address.text) else { return [] }
        if components.port != nil { return [address.text] }
        return [address.text, "\(address.text):7125"]
    }

    nonisolated static func socketURL(base: String) -> URL? {
        guard var components = URLComponents(string: base) else { return nil }
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/websocket"
        return components.url
    }

    /// A spool id means something only to the Spoolman that issued it.
    nonisolated static func sharesSpoolman(printerServer: String?, connectionTarget: String) -> Bool {
        guard let printerServer, let separator = connectionTarget.firstIndex(of: "|") else { return false }
        return connectionTarget[connectionTarget.index(after: separator)...] == ServerAddress.identity(of: printerServer)
    }

    func usageRoute(connectionTarget: String) -> PrinterUsageRoute? {
        PrinterUsageRoute.route(connectionTarget: connectionTarget, spoolmanServer: spoolmanServer, filamanServer: filamanServer)
    }

    func connect() async {
        disconnect()
        let bases = Self.candidateBases(for: address)
        guard !bases.isEmpty else {
            connection = .notConfigured
            return
        }
        connection = .connecting
        for base in bases {
            guard let url = Self.socketURL(base: base) else { continue }
            let candidate = makeTransport(url)
            do {
                try await start(on: candidate, base: base)
                return
            } catch MoonrakerError.unauthorized {
                candidate.close()
                connection = .needsSignIn
                return
            } catch {
                logger.warning("Printer connection failed at \(base, privacy: .public): \(error.localizedDescription, privacy: .public)")
                candidate.close()
            }
        }
        connection = .offline("Can't reach the printer at \(address).")
    }

    func disconnect() {
        transport?.onClosed = nil
        transport?.onNotification = nil
        transport?.close()
        transport = nil
        objects = []
        tagPlugin = .notInstalled
    }

    // MARK: - Sign-in

    private var credentials: PrinterCredentials? {
        PrinterCredentials.decode(readCredentials(), address: address)
    }

    var isSignedIn: Bool { credentials != nil }

    /// Nil on success, else what to tell the user. The password goes to the
    /// printer once and is not kept; it holds the tokens instead.
    func signIn(username: String, password: String) async -> String? {
        for base in Self.candidateBases(for: address) {
            guard let url = Self.socketURL(base: base) else { continue }
            let candidate = makeTransport(url)
            defer { candidate.close() }
            do {
                let reply = try await candidate.call("access.login", params: ["username": username, "password": password])
                let fields = reply.value as? [String: Any]
                guard let token = fields?["token"] as? String else { return "The printer did not sign you in." }
                let signedIn = PrinterCredentials(
                    address: address, token: token, refreshToken: fields?["refresh_token"] as? String
                )
                guard writeCredentials(signedIn.encoded) else { return "Couldn't save the sign-in on this phone." }
                await connect()
                return connection == .online ? nil : "The printer did not accept the sign-in."
            } catch MoonrakerError.unauthorized(let reason) {
                return reason
            } catch {
                continue
            }
        }
        return "Can't reach the printer at \(address)."
    }

    func signIn(apiKey: String) async -> String? {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard writeCredentials(PrinterCredentials(address: address, apiKey: key).encoded) else {
            return "Couldn't save the key on this phone."
        }
        await connect()
        if connection == .online { return nil }
        // A refused key must not stay behind to fail every later connect.
        _ = writeCredentials(nil)
        return connection == .needsSignIn ? "The printer refused this key." : "Can't reach the printer at \(address)."
    }

    func signOut() async {
        _ = writeCredentials(nil)
        await connect()
    }

    /// Identifies with what is stored. An expired token is refreshed once on
    /// the same socket: a failed identify leaves the connection unidentified.
    private func identify(on candidate: PrinterTransport) async throws {
        let fixed: [String: Any] = [
            "client_name": "SpoolKid", "version": Bundle.main.appVersion ?? "0",
            "type": "mobile", "url": "https://github.com/marko-p/SpoolKid"
        ]
        var stored = credentials
        func params() -> [String: Any] {
            fixed.merging(stored?.identifyFields ?? [:]) { _, new in new }
        }
        do {
            _ = try await candidate.call("server.connection.identify", params: params())
        } catch MoonrakerError.unauthorized(let reason) {
            guard let refreshToken = stored?.refreshToken else { throw MoonrakerError.unauthorized(reason) }
            let reply = try await candidate.call("access.refresh_jwt", params: ["refresh_token": refreshToken])
            guard let token = (reply.value as? [String: Any])?["token"] as? String else {
                throw MoonrakerError.unauthorized(reason)
            }
            stored?.token = token
            _ = writeCredentials(stored?.encoded)
            _ = try await candidate.call("server.connection.identify", params: params())
        }
    }

    private func start(on candidate: PrinterTransport, base: String) async throws {
        try await identify(on: candidate)
        let info = try await candidate.call("printer.info", params: [:]).value as? [String: Any]
        let listed = try await candidate.call("printer.objects.list", params: [:]).value as? [String: Any]
        let config = try? await candidate.call("server.config", params: [:]).value as? [String: Any]
        let objects = listed?["objects"] as? [String] ?? []
        let configFiles = (config?["files"] as? [[String: Any]] ?? []).compactMap { $0["filename"] as? String }
        let stack = PrinterStack.detect(
            softwareVersion: info?["software_version"] as? String ?? "", objects: objects, configFiles: configFiles
        )
        let sections = config?["config"] as? [String: Any]
        let spoolman = (sections?["spoolman"] as? [String: Any])?["server"] as? String
        let filaman = (sections?["filaman"] as? [String: Any])?["server"] as? String

        var readerMode = PrinterReaderMode.unknown
        if stack == .extendedFirmware, let url = URL(string: "\(base)/server/files/config/extended/extended2.cfg"),
           let text = await fetchText(url, credentials?.httpHeaders ?? [:]) {
            readerMode = PrinterReaderMode.parse(extendedConfig: text)
        }

        self.objects = objects
        let watched = Self.subscribed + (objects.contains(PrinterTagPlugin.objectName) ? [PrinterTagPlugin.objectName] : [])
        let subscription = Dictionary(uniqueKeysWithValues: watched.map { ($0, NSNull() as Any) })
        let reply = try await candidate.call("printer.objects.subscribe", params: ["objects": subscription])
        status = [:]
        watch = .load(address: address, defaults: defaults)
        merge((reply.value as? [String: Any])?["status"] as? [String: Any] ?? [:])

        candidate.onNotification = { [weak self] method, params in
            guard method == "notify_status_update", let update = params.first as? [String: Any] else { return }
            self?.merge(update)
        }
        candidate.onClosed = { [weak self] in
            guard let self else { return }
            self.transport = nil
            self.connection = .offline("Lost the connection to the printer.")
        }
        transport = candidate
        self.base = base
        spoolmanServer = spoolman
        filamanServer = filaman
        capabilities = .of(stack, readerMode: readerMode, hasSpoolman: spoolman != nil)
        connection = .online
    }

    /// Moonraker pushes only the fields that changed.
    private func merge(_ update: [String: Any]) {
        for (object, fields) in update {
            guard let fields = fields as? [String: Any] else { continue }
            status[object, default: [:]].merge(fields) { _, new in new }
        }
        // Assigned only on a change: a print pushes progress constantly, and
        // every assignment redraws the tab.
        let parsed = (0..<profile.toolheadCount).compactMap { ToolheadState.parse(index: $0, status: status) }
        if parsed != toolheads { toolheads = parsed }
        let current = PrinterActivity.parse(status: status)
        if current != activity { activity = current }
        let plugin = PrinterTagPlugin.parse(objects: objects, status: status[PrinterTagPlugin.objectName])
        if plugin != tagPlugin { tagPlugin = plugin }
        refreshNotes()
    }

    // MARK: - Writes

    func assign(_ assignment: ToolheadAssignment, toolhead: Int, force: Bool) async -> ToolheadWriteOutcome {
        if let refused = await send(PrinterCommands.assign(assignment, toolhead: toolhead, force: force)) { return refused }
        let outcome = await readBack(toolhead) { PrinterCommands.confirms(assignment, state: $0) }
        if outcome == .confirmed { setWatched(assignment, toolhead: toolhead) }
        return outcome
    }

    /// The tab's Refresh. Asks each toolhead that has a tag to read it again,
    /// so a tag rewritten in place shows up without a reload. No
    /// `FILAMENT_DT_CLEAR` first, as paxx12's page has: that would wipe
    /// assignments, and a toolhead without a tag is left alone for the same
    /// reason. Nil when all were sent, else why not.
    func refresh() async -> String? {
        guard connection == .online else {
            await connect()
            return nil
        }
        guard !activity.blocksWrites else { return nil }
        for toolhead in toolheads where toolhead.tagUID != nil {
            if let refused = await send(PrinterCommands.reRead(toolhead: toolhead.index)) { return refused.message }
        }
        return nil
    }

    /// Tells FilaMan's Moonraker component which spool a toolhead holds, so it
    /// counts that toolhead's use against it. Confirmed by its reply alone:
    /// the component offers no read-back here.
    func assignFilaManSpool(_ spoolID: Int, toolhead: Int) async -> ToolheadWriteOutcome {
        guard !activity.blocksWrites else { return .failed("The printer is busy with a print.") }
        guard transport != nil, let base,
              let url = URL(string: base + PrinterCommands.filamanSpoolPath(toolhead: toolhead, spoolID: spoolID)) else {
            return .failed(MoonrakerError.notConnected.localizedDescription)
        }
        switch await post(url, credentials?.httpHeaders ?? [:]) {
        case 200?: return .confirmed
        case let status?:
            logger.error("FilaMan spool assignment refused: HTTP \(status, privacy: .public)")
            return .failed("The printer's FilaMan component refused it (HTTP \(status)).")
        case nil: return .failed("The printer's FilaMan component didn't answer.")
        }
    }

    func reRead(toolhead: Int) async -> ToolheadWriteOutcome {
        await send(PrinterCommands.reRead(toolhead: toolhead)) ?? .confirmed
    }

    func clear(toolhead: Int) async -> ToolheadWriteOutcome {
        if let refused = await send(PrinterCommands.clear(toolhead: toolhead)) { return refused }
        // Forgotten first: this clear is the user's own, not news to report.
        setWatched(nil, toolhead: toolhead)
        return await readBack(toolhead) { !$0.hasData }
    }

    /// The note has been seen: stop watching this toolhead.
    func acknowledgeNote(toolhead: Int) {
        guard notes[toolhead] != nil else { return }
        setWatched(nil, toolhead: toolhead)
    }

    private func setWatched(_ assignment: ToolheadAssignment?, toolhead: Int) {
        watch.assignments[toolhead] = assignment
        watch.save(to: defaults)
        refreshNotes()
    }

    private func refreshNotes() {
        let current = watch.notes(for: toolheads)
        if current != notes { notes = current }
    }

    /// The printer can answer a command before its state shows the result
    /// (`FILAMENT_DT_CLEAR` did, on a U1 2026-11-07), so one early read would
    /// call a done write undone. Asks for about three seconds.
    private func readBack(_ toolhead: Int, until shown: (ToolheadState) -> Bool) async -> ToolheadWriteOutcome {
        for attempt in 0..<10 {
            if attempt > 0 { await pause() }
            await refreshConfig()
            if let state = toolheads.first(where: { $0.index == toolhead }), shown(state) { return .confirmed }
        }
        return .notConfirmed
    }

    /// Nil once the printer ran the command.
    private func send(_ gcode: String) async -> ToolheadWriteOutcome? {
        guard !activity.blocksWrites else { return .failed("The printer is busy with a print.") }
        guard let transport else { return .failed(MoonrakerError.notConnected.localizedDescription) }
        do {
            _ = try await transport.call("printer.gcode.script", params: ["script": gcode])
            return nil
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func refreshConfig() async {
        guard let transport else { return }
        let query = ["print_task_config": NSNull() as Any, "filament_detect": NSNull() as Any]
        guard let reply = try? await transport.call("printer.objects.query", params: ["objects": query]) else { return }
        merge((reply.value as? [String: Any])?["status"] as? [String: Any] ?? [:])
    }

    nonisolated private static func postOverHTTP(_ url: URL, headers: [String: String]) async -> Int? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return nil }
        return (response as? HTTPURLResponse)?.statusCode
    }

    nonisolated private static func fetchTextOverHTTP(_ url: URL, headers: [String: String]) async -> String? {
        var request = URLRequest(url: url)
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

extension PrinterService: PrinterTagGateway {
    func readTag(toolhead: Int, expectedUID: String?) async -> Result<PrinterTagRead, PrinterTagError> {
        await PrinterTagClient.read(transport: transport, toolhead: toolhead, expectedUID: expectedUID)
    }

    func writeTag(toolhead: Int, expectedUID: String, pages: [(page: Int, data: Data)],
                  password: Data?, allowConfig: Bool) async -> Result<Int, PrinterTagError> {
        await PrinterTagClient.write(transport: transport, toolhead: toolhead, expectedUID: expectedUID,
                                     pages: pages, password: password, allowConfig: allowConfig)
    }
}
