import Foundation

public enum ESCPos {
    public static let initialize = Data([0x1B, 0x40])

    public static func align(_ alignment: PrintAlignment) -> Data {
        let value: UInt8 = switch alignment {
        case .leading: 0
        case .center: 1
        case .trailing: 2
        }
        return Data([0x1B, 0x61, value])
    }

    public static func energy(_ settings: QualitySettings) throws -> Data {
        guard settings.maxHeatingDots <= 7 else { throw PrintError.invalidSettings }
        return Data([0x1B, 0x37, settings.maxHeatingDots, settings.heatingTime, settings.heatingInterval])
    }

    public static func feed(lines: Int) -> Data {
        Data([0x1B, 0x64, UInt8(clamping: lines)])
    }

    public static func rasterHeader(widthBytes: Int, rows: Int) throws -> Data {
        guard (1...65_535).contains(widthBytes), (1...65_535).contains(rows) else {
            throw PrintError.invalidBitmap
        }
        return Data([
            0x1D, 0x76, 0x30, 0x00,
            UInt8(widthBytes & 0xFF), UInt8((widthBytes >> 8) & 0xFF),
            UInt8(rows & 0xFF), UInt8((rows >> 8) & 0xFF)
        ])
    }
}
