import Foundation

public enum ShellPrintContentKind: String, Codable, Sendable {
    case text
    case markdown
    case html
    case file
    case image
}

public struct ShellPrintRequest: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public let version: Int
    public let id: UUID
    public let contentKind: ShellPrintContentKind
    public let htmlFilename: String?
    public let cssFilename: String?
    public let payloadFilename: String?
    public let payloadExtension: String?
    public let qualityPresetID: String?
    public let copies: Int
    public let feedLinesAfter: Int
    public let prepare: Bool

    public init(
        version: Int = ShellPrintRequest.currentVersion,
        id: UUID,
        contentKind: ShellPrintContentKind,
        htmlFilename: String? = nil,
        cssFilename: String? = nil,
        payloadFilename: String? = nil,
        payloadExtension: String? = nil,
        qualityPresetID: String? = nil,
        copies: Int = 1,
        feedLinesAfter: Int = 3,
        prepare: Bool = false
    ) {
        self.version = version
        self.id = id
        self.contentKind = contentKind
        self.htmlFilename = htmlFilename
        self.cssFilename = cssFilename
        self.payloadFilename = payloadFilename
        self.payloadExtension = payloadExtension
        self.qualityPresetID = qualityPresetID
        self.copies = copies
        self.feedLinesAfter = feedLinesAfter
        self.prepare = prepare
    }

    public func validate() throws {
        guard version == Self.currentVersion,
              copies >= 1, copies <= 20,
              feedLinesAfter >= 0, feedLinesAfter <= 20 else {
            throw ShellPrintBridgeError.invalidRequest
        }

        if let qualityPresetID,
           !["text", "imageHighQuality", "custom", "fast", "balanced", "highQuality"].contains(qualityPresetID) {
            throw ShellPrintBridgeError.invalidRequest
        }

        switch contentKind {
        case .html:
            guard htmlFilename == "html",
                  payloadFilename == nil,
                  payloadExtension == nil else { throw ShellPrintBridgeError.invalidRequest }
            if let cssFilename { guard cssFilename == "css" else { throw ShellPrintBridgeError.invalidRequest } }
        case .text, .markdown:
            guard payloadFilename == "input",
                  payloadExtension == nil,
                  htmlFilename == nil,
                  cssFilename == nil else { throw ShellPrintBridgeError.invalidRequest }
        case .file, .image:
            guard payloadFilename == "input",
                  htmlFilename == nil,
                  cssFilename == nil,
                  let payloadExtension,
                  ContentDetector.supportedExtensions.contains(payloadExtension.lowercased()) else {
                throw ShellPrintBridgeError.invalidRequest
            }
        }
    }
}

public enum ShellPrintResultStatus: String, Codable, Sendable {
    case accepted
    case completed
    case prepared
    case failed
}

public struct ShellPrintResult: Codable, Sendable, Equatable {
    public let id: UUID
    public let status: ShellPrintResultStatus
    public let jobID: UUID?
    public let message: String?
    public let errorCode: String?
    public let durationSeconds: Double?

    public init(
        id: UUID,
        status: ShellPrintResultStatus,
        jobID: UUID? = nil,
        message: String? = nil,
        errorCode: String? = nil,
        durationSeconds: Double? = nil
    ) {
        self.id = id
        self.status = status
        self.jobID = jobID
        self.message = message
        self.errorCode = errorCode
        self.durationSeconds = durationSeconds
    }
}

public enum ShellPrintBridgeError: LocalizedError, Sendable, Equatable {
    case invalidURL
    case invalidRequest
    case requestNotFound
    case payloadNotFound
    case busy

    public var errorDescription: String? {
        switch self {
        case .invalidURL: "The PT-210 Print URL is invalid."
        case .invalidRequest: "The PT-210 Print shell request is invalid."
        case .requestNotFound: "The PT-210 Print shell request was not found."
        case .payloadNotFound: "The PT-210 Print shell payload was not found."
        case .busy: "PT-210 Print is already processing another print job."
        }
    }
}

public enum ShellPrintBridge {
    public static let urlScheme = "pt210print"
    public static let urlHost = "job"

    public static func requestID(from url: URL) throws -> UUID {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == urlScheme,
              components.host == urlHost,
              let value = components.queryItems?.first(where: { $0.name == "id" })?.value,
              let id = UUID(uuidString: value) else {
            throw ShellPrintBridgeError.invalidURL
        }
        return id
    }
}

public actor ShellPrintBridgeStore {
    public let rootURL: URL
    private let fileManager: FileManager

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

    public func loadRequest(id: UUID) throws -> ShellPrintRequest {
        let url = requestURL(id)
        guard fileManager.fileExists(atPath: url.path) else {
            throw ShellPrintBridgeError.requestNotFound
        }
        let request = try PropertyListDecoder().decode(ShellPrintRequest.self, from: Data(contentsOf: url))
        guard request.id == id else { throw ShellPrintBridgeError.invalidRequest }
        try request.validate()
        return request
    }

    public func payloadData(for request: ShellPrintRequest, filename: String) throws -> Data {
        guard [request.htmlFilename, request.cssFilename, request.payloadFilename]
            .compactMap({ $0 })
            .contains(filename) else {
            throw ShellPrintBridgeError.invalidRequest
        }
        let url = requestDirectoryURL(request.id).appendingPathComponent(filename)
        guard fileManager.fileExists(atPath: url.path) else {
            throw ShellPrintBridgeError.payloadNotFound
        }
        return try Data(contentsOf: url)
    }

    public func writeResult(_ result: ShellPrintResult) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(result).write(to: resultURL(result.id), options: [.atomic])
    }

    public func removeRequest(id: UUID) throws {
        let directory = requestDirectoryURL(id)
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
    }

    public func removeResult(id: UUID) throws {
        let url = resultURL(id)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func requestURL(_ id: UUID) -> URL {
        requestDirectoryURL(id).appendingPathComponent("request.plist")
    }

    private func requestDirectoryURL(_ id: UUID) -> URL {
        rootURL
            .appendingPathComponent("Bridge", isDirectory: true)
            .appendingPathComponent("Requests", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func resultURL(_ id: UUID) -> URL {
        rootURL
            .appendingPathComponent("Bridge", isDirectory: true)
            .appendingPathComponent("Results", isDirectory: true)
            .appendingPathComponent("\(id.uuidString).json")
    }

    private static func prepareDirectories(fileManager: FileManager, rootURL: URL) throws {
        for path in ["Bridge/Requests", "Bridge/Results"] {
            try fileManager.createDirectory(
                at: rootURL.appendingPathComponent(path),
                withIntermediateDirectories: true
            )
        }
    }
}
