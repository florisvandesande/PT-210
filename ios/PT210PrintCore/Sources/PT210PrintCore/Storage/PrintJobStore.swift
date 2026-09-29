import Foundation

public actor PrintJobStore {
    private let fileManager: FileManager
    private let rootURL: URL

    public init(fileManager: FileManager = .default, rootURL: URL? = nil) throws {
        self.fileManager = fileManager
        if let rootURL {
            self.rootURL = rootURL
        } else if let container = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroup.identifier
        ) {
            self.rootURL = container
        } else {
            throw PrintError.storageUnavailable
        }
        try Self.prepareDirectories(fileManager: fileManager, rootURL: self.rootURL)
    }

    public func savePending(_ job: PrintJob) throws {
        let data = try JSONEncoder.printJobEncoder.encode(job)
        try data.write(to: jobURL(job.id, state: "Pending"), options: [.atomic])
    }

    public func loadPending() throws -> [PrintJob] {
        try jobs(in: "Pending")
    }

    public func markCompleted(_ job: PrintJob) throws {
        try move(job, from: "Pending", to: "Completed")
    }

    public func markFailed(_ job: PrintJob) throws {
        try move(job, from: "Pending", to: "Failed")
    }

    public func delete(_ job: PrintJob) throws {
        for state in ["Pending", "Completed", "Failed"] {
            let url = jobURL(job.id, state: state)
            if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
        }
    }

    public func importAsset(from source: URL, fileExtension: String) throws -> StoredImageReference {
        let filename = UUID().uuidString + "." + fileExtension.lowercased()
        let destination = rootURL.appending(path: "Assets/\(filename)")
        try fileManager.copyItem(at: source, to: destination)
        return StoredImageReference(filename: filename)
    }

    public func assetURL(for reference: StoredImageReference) -> URL {
        rootURL.appending(path: "Assets/\(reference.filename)")
    }

    public func cleanup(now: Date = Date()) throws {
        let cutoff = now.addingTimeInterval(-7 * 24 * 60 * 60)
        for state in ["Completed", "Failed", "Temp"] {
            let directory = rootURL.appending(path: state == "Temp" ? state : "Jobs/\(state)")
            let files = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey]
            )
            for file in files {
                let values = try file.resourceValues(forKeys: [.contentModificationDateKey])
                if values.contentModificationDate.map({ $0 < cutoff }) == true {
                    try fileManager.removeItem(at: file)
                }
            }
        }

        let pendingAssets = Set(try jobs(in: "Pending").compactMap { job -> String? in
            if case .image(let reference) = job.content { return reference.filename }
            return nil
        })
        let assets = try fileManager.contentsOfDirectory(
            at: rootURL.appending(path: "Assets"),
            includingPropertiesForKeys: [.contentModificationDateKey]
        )
        for asset in assets where !pendingAssets.contains(asset.lastPathComponent) {
            let values = try asset.resourceValues(forKeys: [.contentModificationDateKey])
            if values.contentModificationDate.map({ $0 < cutoff }) == true {
                try fileManager.removeItem(at: asset)
            }
        }
    }

    private static func prepareDirectories(fileManager: FileManager, rootURL: URL) throws {
        for path in ["Jobs/Pending", "Jobs/Completed", "Jobs/Failed", "Assets", "Temp", "Diagnostics"] {
            try fileManager.createDirectory(
                at: rootURL.appending(path: path),
                withIntermediateDirectories: true
            )
        }
    }

    private func jobs(in state: String) throws -> [PrintJob] {
        let directory = rootURL.appending(path: "Jobs/\(state)")
        return try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder.printJobDecoder.decode(PrintJob.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private func move(_ job: PrintJob, from source: String, to destination: String) throws {
        let sourceURL = jobURL(job.id, state: source)
        let destinationURL = jobURL(job.id, state: destination)
        guard fileManager.fileExists(atPath: sourceURL.path) else { return }
        if fileManager.fileExists(atPath: destinationURL.path) { try fileManager.removeItem(at: destinationURL) }
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
    }

    private func jobURL(_ id: UUID, state: String) -> URL {
        rootURL.appending(path: "Jobs/\(state)/\(id.uuidString).json")
    }
}

private extension JSONEncoder {
    static var printJobEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var printJobDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
