@preconcurrency import CoreBluetooth
import Foundation
import Observation

public struct DiscoveredPrinter: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let rssi: Int
}

public enum PrinterConnectionState: Sendable, Equatable {
    case unknown
    case bluetoothUnavailable
    case scanning
    case disconnected
    case connecting
    case connected
    case ready
    case busy
    case error(String)
}

@MainActor
@Observable
public final class PT210BluetoothManager: NSObject {
    public private(set) var state: PrinterConnectionState = .unknown
    public private(set) var discoveredPrinters: [DiscoveredPrinter] = []
    public private(set) var connectedPrinterName: String?
    public private(set) var diagnostics = BluetoothDiagnostics()

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var activePeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var pendingServiceIDs = Set<CBUUID>()
    private var knownCandidate: (CBService, CBCharacteristic, CBCharacteristic?, PT210GATTProfile)?
    private var fallbackCandidate: (CBService, CBCharacteristic, CBCharacteristic?)?
    private var continuation: CheckedContinuation<Void, Error>?
    private var connectionTimeoutTask: Task<Void, Never>?
    private var writeContinuation: CheckedContinuation<Void, Error>?
    private var settingsStore: SharedSettingsStore

    public init(settingsStore: SharedSettingsStore = SharedSettingsStore()) {
        self.settingsStore = settingsStore
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    public func startScan() {
        guard central.state == .poweredOn else {
            state = .bluetoothUnavailable
            return
        }
        discoveredPrinters.removeAll()
        peripherals.removeAll()
        state = .scanning
        let services = PT210GATTProfile.known.map { CBUUID(string: $0.serviceUUID) }
        central.scanForPeripherals(withServices: services, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, self.state == .scanning, self.discoveredPrinters.isEmpty else { return }
            self.central.stopScan()
            self.central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }
    }

    public func stopScan() {
        central.stopScan()
        if state == .scanning { state = .disconnected }
    }

    public func connect(to identifier: UUID) async throws {
        guard central.state == .poweredOn else { throw PrintError.bluetoothUnavailable }
        guard let peripheral = peripherals[identifier] ?? central.retrievePeripherals(withIdentifiers: [identifier]).first else {
            throw PrintError.printerNotFound
        }
        central.stopScan()
        activePeripheral = peripheral
        peripheral.delegate = self
        state = .connecting
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                central.connect(peripheral)
                connectionTimeoutTask?.cancel()
                connectionTimeoutTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(12))
                    guard !Task.isCancelled, let self, self.continuation != nil else { return }
                    self.central.cancelPeripheralConnection(peripheral)
                    self.state = .error(PrintError.connectionTimedOut.localizedDescription)
                    self.resumeConnection(throwing: PrintError.connectionTimedOut)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancelConnection() }
        }
    }

    public func reconnectSavedPrinter() async throws {
        for _ in 0..<30 where central.state == .unknown {
            try await Task.sleep(for: .milliseconds(100))
        }
        guard central.state == .poweredOn else { throw PrintError.bluetoothUnavailable }
        let settings = try await settingsStore.load()
        guard let id = settings.peripheralIdentifier else { throw PrintError.printerNotFound }
        try await connect(to: id)
    }

    public func disconnect() {
        guard let activePeripheral else { return }
        central.cancelPeripheralConnection(activePeripheral)
    }

    public func forgetPrinter() async throws {
        disconnect()
        try await settingsStore.forgetPrinter()
    }

    public func send(_ data: Data, pacingMilliseconds: Int) async throws {
        guard let peripheral = activePeripheral, let characteristic = writeCharacteristic else {
            throw PrintError.missingWriteCharacteristic
        }
        state = .busy
        let supportsWithoutResponse = characteristic.properties.contains(.writeWithoutResponse)
        let writeType: CBCharacteristicWriteType = supportsWithoutResponse ? .withoutResponse : .withResponse
        let maximum = max(1, peripheral.maximumWriteValueLength(for: writeType))

        for start in stride(from: 0, to: data.count, by: maximum) {
            try Task.checkCancellation()
            let end = min(start + maximum, data.count)
            let chunk = data[start..<end]
            if writeType == .withoutResponse {
                while !peripheral.canSendWriteWithoutResponse {
                    try await Task.sleep(for: .milliseconds(10))
                    try Task.checkCancellation()
                }
                peripheral.writeValue(chunk, for: characteristic, type: writeType)
            } else {
                try await withCheckedThrowingContinuation { continuation in
                    self.writeContinuation = continuation
                    peripheral.writeValue(chunk, for: characteristic, type: writeType)
                }
            }
            if pacingMilliseconds > 0 { try await Task.sleep(for: .milliseconds(pacingMilliseconds)) }
        }
        state = .ready
    }

    private func cancelConnection() {
        if let activePeripheral { central.cancelPeripheralConnection(activePeripheral) }
        resumeConnection(throwing: PrintError.cancelled)
    }

    private func resumeConnection(throwing error: Error? = nil) {
        guard let continuation else { return }
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        self.continuation = nil
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
    }

    private func profile(for service: CBService, characteristics: [CBCharacteristic]) -> PT210GATTProfile? {
        PT210GATTProfile.known.first { profile in
            service.uuid == CBUUID(string: profile.serviceUUID)
                && characteristics.contains { $0.uuid == CBUUID(string: profile.writeUUID) }
        }
    }

    private func priority(of profile: PT210GATTProfile) -> Int {
        PT210GATTProfile.known.firstIndex(of: profile) ?? .max
    }

    private func finishDiscovery(peripheral: CBPeripheral) async {
        if let candidate = knownCandidate {
            await select(
                peripheral: peripheral,
                service: candidate.0,
                write: candidate.1,
                notify: candidate.2,
                profile: candidate.3
            )
            return
        }
        guard let candidate = fallbackCandidate else {
            state = .error(PrintError.missingWriteCharacteristic.localizedDescription)
            resumeConnection(throwing: PrintError.missingWriteCharacteristic)
            return
        }
        let profile = PT210GATTProfile(
            serviceUUID: candidate.0.uuid.uuidString,
            writeUUID: candidate.1.uuid.uuidString,
            notifyUUID: candidate.2?.uuid.uuidString
        )
        await select(
            peripheral: peripheral,
            service: candidate.0,
            write: candidate.1,
            notify: candidate.2,
            profile: profile
        )
    }

    private func select(
        peripheral: CBPeripheral,
        service: CBService,
        write: CBCharacteristic,
        notify: CBCharacteristic?,
        profile: PT210GATTProfile
    ) async {
        writeCharacteristic = write
        diagnostics.serviceUUID = service.uuid.uuidString
        diagnostics.writeUUID = write.uuid.uuidString
        diagnostics.notifyUUID = notify?.uuid.uuidString
        var propertyNames: [String] = []
        if write.properties.contains(.write) { propertyNames.append("write") }
        if write.properties.contains(.writeWithoutResponse) { propertyNames.append("writeWithoutResponse") }
        if write.properties.contains(.notify) { propertyNames.append("notify") }
        diagnostics.writeProperties = propertyNames.joined(separator: ", ")
        let writeType: CBCharacteristicWriteType = write.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        diagnostics.maximumWriteLength = peripheral.maximumWriteValueLength(for: writeType)
        if let notify { peripheral.setNotifyValue(true, for: notify) }
        try? await settingsStore.updatePrinter(identifier: peripheral.identifier, profile: profile)
        state = .ready
        resumeConnection()
    }
}

public struct BluetoothDiagnostics: Sendable, Equatable {
    public var peripheralIdentifier: UUID?
    public var serviceUUID: String?
    public var writeUUID: String?
    public var notifyUUID: String?
    public var writeProperties: String?
    public var maximumWriteLength: Int?
    public var rssi: Int?

    public init() {}
}

extension PT210BluetoothManager: CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            state = central.state == .poweredOn ? .disconnected : .bluetoothUnavailable
        }
    }

    nonisolated public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let advertisedServiceIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
            .map(\.uuidString)
        let manufacturerBytes = (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data)
            .map { Array($0) } ?? []
        Task { @MainActor in
            let reportedName = peripheral.name ?? advertisedName
            let normalizedServices = Set(advertisedServiceIDs.map { CBUUID(string: $0).uuidString })
            let hasPT210LServicePair = normalizedServices.contains(CBUUID(string: "18F0").uuidString)
                && normalizedServices.contains(CBUUID(string: "E7810A71-73AE-499D-8C15-FAA9AEF0C3F2").uuidString)
            let hasLegacyService = [PT210GATTProfile.primary, PT210GATTProfile.alternative].contains { profile in
                normalizedServices.contains(CBUUID(string: profile.serviceUUID).uuidString)
            }
            let manufacturerPrefix: [UInt8] = [0x47, 0x5A, 0x86, 0x67, 0x7A, 0xAA]
            let hasPT210Manufacturer = manufacturerBytes.starts(with: manufacturerPrefix)
            let nameMatches = reportedName.map {
                $0.localizedCaseInsensitiveContains("PT-210")
                    || $0.localizedCaseInsensitiveContains("PT210")
                    || $0.localizedCaseInsensitiveContains("MTP-2")
            } ?? false

            // 18F0 alone is used by many unrelated BLE devices. The tested PT210L
            // advertises a second vendor service and a stable manufacturer prefix.
            guard hasPT210LServicePair || hasPT210Manufacturer || hasLegacyService || nameMatches else { return }

            let suffix = manufacturerBytes.count >= 2
                ? manufacturerBytes.suffix(2).map { String(format: "%02X", $0) }.joined()
                : nil
            let name = reportedName ?? suffix.map { "PT210L_\($0)" } ?? "PT-210 printer"
            peripherals[peripheral.identifier] = peripheral
            let printer = DiscoveredPrinter(id: peripheral.identifier, name: name, rssi: RSSI.intValue)
            discoveredPrinters.removeAll { $0.id == printer.id }
            discoveredPrinters.append(printer)
            discoveredPrinters.sort { $0.rssi > $1.rssi }
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            state = .connected
            connectedPrinterName = peripheral.name ?? "PT-210"
            diagnostics.peripheralIdentifier = peripheral.identifier
            pendingServiceIDs.removeAll()
            knownCandidate = nil
            fallbackCandidate = nil
            peripheral.discoverServices(nil)
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            state = .error(error?.localizedDescription ?? PrintError.connectionFailed.localizedDescription)
            resumeConnection(throwing: PrintError.connectionFailed)
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            writeCharacteristic = nil
            activePeripheral = nil
            connectedPrinterName = nil
            state = error.map { .error($0.localizedDescription) } ?? .disconnected
            if continuation != nil {
                resumeConnection(throwing: error ?? PrintError.connectionFailed)
            }
        }
    }

    nonisolated public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            if error != nil {
                resumeConnection(throwing: PrintError.connectionFailed)
                return
            }
            let services = peripheral.services ?? []
            guard !services.isEmpty else {
                state = .error(PrintError.missingWriteCharacteristic.localizedDescription)
                resumeConnection(throwing: PrintError.missingWriteCharacteristic)
                return
            }
            pendingServiceIDs = Set(services.map(\.uuid))
            for service in services { peripheral.discoverCharacteristics(nil, for: service) }
        }
    }

    nonisolated public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            defer {
                pendingServiceIDs.remove(service.uuid)
                if pendingServiceIDs.isEmpty {
                    Task { @MainActor in await finishDiscovery(peripheral: peripheral) }
                }
            }
            guard error == nil, let characteristics = service.characteristics else { return }
            let notify = characteristics.first { $0.properties.contains(.notify) }
            if let profile = profile(for: service, characteristics: characteristics),
               let write = characteristics.first(where: { $0.uuid == CBUUID(string: profile.writeUUID) }) {
                if knownCandidate.map({ priority(of: profile) < priority(of: $0.3) }) ?? true {
                    knownCandidate = (service, write, notify, profile)
                }
            } else if fallbackCandidate == nil,
                      let write = characteristics.first(where: {
                          $0.properties.contains(.writeWithoutResponse) || $0.properties.contains(.write)
                      }) {
                fallbackCandidate = (service, write, notify)
            }
        }
    }

    nonisolated public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            guard let continuation = writeContinuation else { return }
            writeContinuation = nil
            if let error { continuation.resume(throwing: error) } else { continuation.resume() }
        }
    }
}
