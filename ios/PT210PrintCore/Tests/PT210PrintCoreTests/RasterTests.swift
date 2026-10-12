import Foundation
import XCTest
@testable import PT210PrintCore

final class RasterTests: XCTestCase {
    func testPacksMostSignificantBitFirst() throws {
        let image = try GrayscaleImage(width: 8, height: 1, pixels: [0, 255, 255, 255, 255, 255, 255, 255])
        let bitmap = try Ditherer.process(image, algorithm: .threshold, threshold: 0.5, invert: false)
        XCTAssertEqual(bitmap.data, Data([0x80]))
    }

    func testWidth384Uses48BytesPerRow() throws {
        let image = try GrayscaleImage(width: 384, height: 2, pixels: .init(repeating: 255, count: 768))
        let bitmap = try Ditherer.process(image, algorithm: .threshold, threshold: 0.5, invert: false)
        XCTAssertEqual(bitmap.bytesPerRow, 48)
        XCTAssertEqual(bitmap.data.count, 96)
    }

    func testRasterStripsPreserveEveryRow() throws {
        let bitmap = try MonochromeBitmap(width: 384, height: 50, bytesPerRow: 48, data: Data(repeating: 0xAA, count: 2_400))
        let strips = try ESCPOSRasterEncoder.makeStrips(bitmap: bitmap, rowsPerStrip: 24)
        XCTAssertEqual(strips.count, 3)
        XCTAssertEqual(strips.map(\.count), [1_160, 1_160, 104])
    }

    func testInversionTurnsWhitePixelsBlack() throws {
        let image = try GrayscaleImage(width: 8, height: 1, pixels: .init(repeating: 255, count: 8))
        let bitmap = try Ditherer.process(image, algorithm: .threshold, threshold: 0.5, invert: true)
        XCTAssertEqual(bitmap.data, Data([0xFF]))
    }

    func testFeedUsesBlankRasterRowsForPT210LCompatibility() throws {
        let strips = try ESCPOSRasterEncoder.makeFeedStrips(widthBytes: 48, lines: 3, rowsPerStrip: 24)
        XCTAssertEqual(strips.count, 3)
        XCTAssertTrue(strips.allSatisfy { $0.count == 8 + (48 * 24) })
        XCTAssertTrue(strips.allSatisfy { $0.dropFirst(8).allSatisfy { $0 == 0 } })
    }

    func testZeroFeedLinesSendNoRasterData() throws {
        let strips = try ESCPOSRasterEncoder.makeFeedStrips(widthBytes: 48, lines: 0, rowsPerStrip: 24)
        XCTAssertTrue(strips.isEmpty)
    }
}
