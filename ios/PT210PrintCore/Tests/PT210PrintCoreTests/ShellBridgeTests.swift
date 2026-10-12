import Foundation
import XCTest
@testable import PT210PrintCore

final class ShellBridgeTests: XCTestCase {
    func testHTMLRequestValidationAndURLRoundTrip() throws {
        let id = UUID()
        let request = ShellPrintRequest(
            id: id,
            contentKind: .html,
            htmlFilename: "html",
            cssFilename: "css",
            qualityPresetID: "text"
        )

        XCTAssertNoThrow(try request.validate())
        let url = try XCTUnwrap(URL(string: "pt210print://job?id=\(id.uuidString)"))
        XCTAssertEqual(try ShellPrintBridge.requestID(from: url), id)
    }

    func testInvalidRequestRejectsUnsafePayloadNames() {
        let request = ShellPrintRequest(
            id: UUID(),
            contentKind: .html,
            htmlFilename: "../secret"
        )

        XCTAssertThrowsError(try request.validate()) { error in
            XCTAssertEqual(error as? ShellPrintBridgeError, .invalidRequest)
        }
    }

    func testRequestValidationCoversAllContentKinds() throws {
        let requests = [
            ShellPrintRequest(id: UUID(), contentKind: .text, payloadFilename: "input"),
            ShellPrintRequest(id: UUID(), contentKind: .markdown, payloadFilename: "input"),
            ShellPrintRequest(id: UUID(), contentKind: .html, htmlFilename: "html"),
            ShellPrintRequest(
                id: UUID(),
                contentKind: .file,
                payloadFilename: "input",
                payloadExtension: "html"
            ),
            ShellPrintRequest(
                id: UUID(),
                contentKind: .image,
                payloadFilename: "input",
                payloadExtension: "png"
            )
        ]

        for request in requests {
            XCTAssertNoThrow(try request.validate())
        }
    }

    func testRequestValidationRejectsInvalidOptionsAndExtensions() {
        let invalidRequests = [
            ShellPrintRequest(id: UUID(), contentKind: .text, payloadFilename: "input", copies: 0),
            ShellPrintRequest(id: UUID(), contentKind: .text, payloadFilename: "input", feedLinesAfter: 21),
            ShellPrintRequest(
                id: UUID(),
                contentKind: .image,
                payloadFilename: "input",
                payloadExtension: "svg"
            ),
            ShellPrintRequest(
                id: UUID(),
                contentKind: .html,
                htmlFilename: "html",
                cssFilename: "../css"
            )
        ]

        for request in invalidRequests {
            XCTAssertThrowsError(try request.validate())
        }
    }

    func testBridgeURLRejectsOtherSchemesAndHosts() throws {
        let invalidURLs = [
            URL(string: "https://job?id=\(UUID().uuidString)"),
            URL(string: "pt210print://other?id=\(UUID().uuidString)"),
            URL(string: "pt210print://job?id=not-a-uuid")
        ]

        for url in invalidURLs {
            XCTAssertThrowsError(try ShellPrintBridge.requestID(from: try XCTUnwrap(url)))
        }
    }

    func testStoreReadsRequestAndPayloadAndWritesResult() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pt210-shell-bridge-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ShellPrintBridgeStore(rootURL: root)
        let id = UUID()
        let request = ShellPrintRequest(id: id, contentKind: .text, payloadFilename: "input")
        let requestDirectory = root
            .appendingPathComponent("Bridge/Requests")
            .appendingPathComponent(id.uuidString)
        try FileManager.default.createDirectory(at: requestDirectory, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: requestDirectory.appendingPathComponent("input"))
        try PropertyListEncoder().encode(request).write(to: requestDirectory.appendingPathComponent("request.plist"))

        let loaded = try await store.loadRequest(id: id)
        XCTAssertEqual(loaded, request)
        let payload = try await store.payloadData(for: loaded, filename: "input")
        XCTAssertEqual(payload, Data("hello".utf8))

        let result = ShellPrintResult(id: id, status: .completed, jobID: UUID(), message: "done")
        try await store.writeResult(result)
        let resultURL = root.appendingPathComponent("Bridge/Results/\(id.uuidString).json")
        let decoded = try JSONDecoder().decode(ShellPrintResult.self, from: Data(contentsOf: resultURL))
        XCTAssertEqual(decoded, result)
    }
}
