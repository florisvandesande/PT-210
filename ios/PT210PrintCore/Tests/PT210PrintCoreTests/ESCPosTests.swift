import Foundation
import XCTest
@testable import PT210PrintCore

final class ESCPosTests: XCTestCase {
    func testInitializeCommandHasExactBytes() {
        XCTAssertEqual(ESCPos.initialize, Data([0x1B, 0x40]))
    }

    func testEnergyCommandHasExactBytes() throws {
        XCTAssertEqual(try ESCPos.energy(.init(
            maxHeatingDots: 7,
            heatingTime: 120,
            heatingInterval: 2,
            brightness: 0,
            contrast: 1,
            gamma: 1,
            threshold: 0.5,
            dithering: .threshold,
            invert: false
        )), Data([0x1B, 0x37, 7, 120, 2]))
    }

    func testInvalidHeatingDotsAreRejected() {
        XCTAssertThrowsError(try ESCPos.energy(.init(
            maxHeatingDots: 8,
            heatingTime: 120,
            heatingInterval: 2,
            brightness: 0,
            contrast: 1,
            gamma: 1,
            threshold: 0.5,
            dithering: .threshold,
            invert: false
        )))
    }

    func testRasterHeaderUsesLittleEndianDimensions() throws {
        XCTAssertEqual(try ESCPos.rasterHeader(widthBytes: 48, rows: 300), Data([
            0x1D, 0x76, 0x30, 0x00, 48, 0, 44, 1
        ]))
    }
}
