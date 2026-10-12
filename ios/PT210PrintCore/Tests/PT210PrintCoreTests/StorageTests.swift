import Foundation
import XCTest
@testable import PT210PrintCore

final class StorageTests: XCTestCase {
    func testPendingJobsRoundTrip() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try PrintJobStore(rootURL: root)
        let job = PrintJob(content: .plainText("Safe sample"), source: .mainApp)
        try await store.savePending(job)
        let loaded = try await store.loadPending()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].content, job.content)
    }

    func testContentDetectionUsesFileExtension() throws {
        let root = FileManager.default.temporaryDirectory
        let markdown = root.appendingPathComponent("\(UUID().uuidString).md")
        try Data("# Heading".utf8).write(to: markdown)
        defer { try? FileManager.default.removeItem(at: markdown) }
        XCTAssertEqual(try ContentDetector.content(for: markdown), .markdown("# Heading"))
    }
}
