import Foundation

public actor SharedSettingsStore {
    private let defaults: UserDefaults
    private let key = "printer-settings-v1"

    public init(defaults: UserDefaults? = UserDefaults(suiteName: AppGroup.identifier)) {
        self.defaults = defaults ?? .standard
    }

    public func load() throws -> PrinterSettings {
        guard let data = defaults.data(forKey: key) else { return .highQuality }
        return try JSONDecoder().decode(PrinterSettings.self, from: data)
    }

    public func save(_ settings: PrinterSettings) throws {
        defaults.set(try JSONEncoder().encode(settings), forKey: key)
    }

    public func updatePrinter(identifier: UUID, profile: PT210GATTProfile) throws {
        var settings = try load()
        settings.peripheralIdentifier = identifier
        settings.gattProfile = profile
        try save(settings)
    }

    public func forgetPrinter() throws {
        var settings = try load()
        settings.peripheralIdentifier = nil
        settings.gattProfile = nil
        try save(settings)
    }
}
