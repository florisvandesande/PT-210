import Foundation
import Testing
@testable import PT210PrintCore

@Test func pendingJobsRoundTrip() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try PrintJobStore(rootURL: root)
    let job = PrintJob(content: .plainText("Safe sample"), source: .mainApp)
    try await store.savePending(job)
    let loaded = try await store.loadPending()
    #expect(loaded.count == 1)
    #expect(loaded[0].content == job.content)
}

@Test func contentDetectionUsesFileExtension() throws {
    let root = FileManager.default.temporaryDirectory
    let markdown = root.appending(path: "\(UUID().uuidString).md")
    try Data("# Heading".utf8).write(to: markdown)
    defer { try? FileManager.default.removeItem(at: markdown) }
    #expect(try ContentDetector.content(for: markdown) == .markdown("# Heading"))
}
