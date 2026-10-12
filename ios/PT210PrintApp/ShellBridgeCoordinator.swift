import Foundation
import PT210PrintCore

@MainActor
final class ShellBridgeCoordinator {
    typealias Handler = @MainActor (ShellPrintRequest) async throws -> UUID?

    private let store: ShellPrintBridgeStore?
    private let handler: Handler
    private var queue: [ShellPrintRequest] = []
    private var queuedIDs = Set<UUID>()
    private var isProcessing = false

    init(handler: @escaping Handler) {
        self.store = try? ShellPrintBridgeStore()
        self.handler = handler
    }

    func handle(url: URL) {
        guard let id = try? ShellPrintBridge.requestID(from: url) else { return }
        Task { @MainActor [weak self] in
            await self?.enqueue(id: id)
        }
    }

    private func enqueue(id: UUID) async {
        guard let store else { return }
        do {
            let request = try await store.loadRequest(id: id)
            guard queuedIDs.insert(id).inserted else { return }
            queue.append(request)
            processNext()
        } catch {
            try? await store.writeResult(Self.failureResult(id: id, error: error))
        }
    }

    private func processNext() {
        guard !isProcessing, let request = queue.first else { return }
        queue.removeFirst()
        queuedIDs.remove(request.id)
        isProcessing = true

        Task { @MainActor [weak self] in
            guard let self, let store = self.store else { return }
            let started = Date()
            do {
                try await store.writeResult(
                    ShellPrintResult(id: request.id, status: .accepted, message: "Print request accepted.")
                )
                let jobID = try await handler(request)
                let status: ShellPrintResultStatus = request.prepare ? .prepared : .completed
                let message = request.prepare ? "Print job prepared." : "Print job completed."
                try await store.writeResult(
                    ShellPrintResult(
                        id: request.id,
                        status: status,
                        jobID: jobID,
                        message: message,
                        durationSeconds: Date().timeIntervalSince(started)
                    )
                )
            } catch {
                try? await store.writeResult(
                    Self.failureResult(
                        id: request.id,
                        error: error,
                        durationSeconds: Date().timeIntervalSince(started)
                    )
                )
            }
            try? await store.removeRequest(id: request.id)
            isProcessing = false
            processNext()
        }
    }

    private static func failureResult(
        id: UUID,
        error: Error,
        durationSeconds: Double? = nil
    ) -> ShellPrintResult {
        let message = (error as? LocalizedError)?.errorDescription ?? "The print request failed."
        return ShellPrintResult(
            id: id,
            status: .failed,
            message: message,
            errorCode: errorCode(for: error),
            durationSeconds: durationSeconds
        )
    }

    private static func errorCode(for error: Error) -> String {
        switch error {
        case ShellPrintBridgeError.busy: return "busy"
        case ShellPrintBridgeError.invalidRequest: return "invalid_request"
        case ShellPrintBridgeError.invalidURL: return "invalid_url"
        case ShellPrintBridgeError.payloadNotFound: return "payload_not_found"
        case ShellPrintBridgeError.requestNotFound: return "request_not_found"
        case PrintError.bluetoothUnavailable: return "bluetooth_unavailable"
        case PrintError.printerNotFound: return "printer_not_found"
        case PrintError.connectionFailed: return "connection_failed"
        case PrintError.connectionTimedOut: return "connection_timed_out"
        case PrintError.missingWriteCharacteristic: return "missing_write_characteristic"
        case PrintError.writeFailed: return "write_failed"
        case PrintError.renderFailed: return "render_failed"
        case PrintError.unsupportedContent: return "unsupported_content"
        case PrintError.invalidBitmap: return "invalid_bitmap"
        case PrintError.invalidSettings: return "invalid_settings"
        case PrintError.storageUnavailable: return "storage_unavailable"
        case PrintError.inputTooLarge: return "input_too_large"
        case PrintError.cancelled: return "cancelled"
        default: return "print_failed"
        }
    }
}
