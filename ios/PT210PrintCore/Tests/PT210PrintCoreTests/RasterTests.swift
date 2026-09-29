import Foundation
import Testing
@testable import PT210PrintCore

@Test func packsMostSignificantBitFirst() throws {
    let image = try GrayscaleImage(width: 8, height: 1, pixels: [0, 255, 255, 255, 255, 255, 255, 255])
    let bitmap = try Ditherer.process(image, algorithm: .threshold, threshold: 0.5, invert: false)
    #expect(bitmap.data == Data([0x80]))
}

@Test func width384Uses48BytesPerRow() throws {
    let image = try GrayscaleImage(width: 384, height: 2, pixels: .init(repeating: 255, count: 768))
    let bitmap = try Ditherer.process(image, algorithm: .threshold, threshold: 0.5, invert: false)
    #expect(bitmap.bytesPerRow == 48)
    #expect(bitmap.data.count == 96)
}

@Test func rasterStripsPreserveEveryRow() throws {
    let bitmap = try MonochromeBitmap(width: 384, height: 50, bytesPerRow: 48, data: Data(repeating: 0xAA, count: 2_400))
    let strips = try ESCPOSRasterEncoder.makeStrips(bitmap: bitmap, rowsPerStrip: 24)
    #expect(strips.count == 3)
    #expect(strips.map(\.count) == [1_160, 1_160, 104])
}

@Test func inversionTurnsWhitePixelsBlack() throws {
    let image = try GrayscaleImage(width: 8, height: 1, pixels: .init(repeating: 255, count: 8))
    let bitmap = try Ditherer.process(image, algorithm: .threshold, threshold: 0.5, invert: true)
    #expect(bitmap.data == Data([0xFF]))
}

@Test func feedUsesBlankRasterRowsForPT210LCompatibility() throws {
    let strips = try ESCPOSRasterEncoder.makeFeedStrips(
        widthBytes: 48,
        lines: 3,
        rowsPerStrip: 24
    )
    #expect(strips.count == 3)
    #expect(strips.allSatisfy { $0.count == 8 + (48 * 24) })
    #expect(strips.allSatisfy { $0.dropFirst(8).allSatisfy { $0 == 0 } })
}

@Test func zeroFeedLinesSendNoRasterData() throws {
    let strips = try ESCPOSRasterEncoder.makeFeedStrips(
        widthBytes: 48,
        lines: 0,
        rowsPerStrip: 24
    )
    #expect(strips.isEmpty)
}
