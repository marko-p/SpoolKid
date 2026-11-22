import Foundation

struct WorkflowTraceEvent: Identifiable, Codable, Sendable {
    let id: UUID
    let timestamp: Date
    let path: String
    let step: String
    let details: [String: String]
}

final class WorkflowTraceStore {
    static let shared = WorkflowTraceStore()

    private var events: [WorkflowTraceEvent] = []
    private let lock = NSLock()

    private let maxEvents = 1000

    private init() {}

    static func log(path: String, step: String, details: [String: String] = [:]) {
        WorkflowTraceStore.shared.append(path: path, step: step, details: details)
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        events.removeAll()
    }

    /// Thread-safe snapshot of the current events, for embedding in the OCR archive.
    func exportEvents() -> [WorkflowTraceEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }

    func exportJSONString() -> String {
        lock.lock()
        let snapshot = events
        lock.unlock()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        if let data = try? encoder.encode(snapshot),
           let text = String(data: data, encoding: .utf8) {
            return text
        }

        return "[]"
    }

    private func append(path: String, step: String, details: [String: String]) {
        lock.lock()
        defer { lock.unlock() }

        events.append(
            WorkflowTraceEvent(
                id: UUID(),
                timestamp: Date(),
                path: path,
                step: step,
                details: details
            )
        )

        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
    }
}
