import Foundation
import Testing
@testable import PT210PrintCore

@Test func initializeCommandHasExactBytes() {
    #expect(ESCPos.initialize == Data([0x1B, 0x40]))
}

@Test func energyCommandHasExactBytes() throws {
    #expect(try ESCPos.energy(.init(
        maxHeatingDots: 7,
        heatingTime: 120,
        heatingInterval: 2,
        brightness: 0,
        contrast: 1,
        gamma: 1,
        threshold: 0.5,
        dithering: .threshold,
        invert: false
    )) == Data([0x1B, 0x37, 7, 120, 2]))
}

@Test func invalidHeatingDotsAreRejected() {
    #expect(throws: PrintError.self) {
        try ESCPos.energy(.init(
            maxHeatingDots: 8,
            heatingTime: 120,
            heatingInterval: 2,
            brightness: 0,
            contrast: 1,
            gamma: 1,
            threshold: 0.5,
            dithering: .threshold,
            invert: false
        ))
    }
}

@Test func rasterHeaderUsesLittleEndianDimensions() throws {
    #expect(try ESCPos.rasterHeader(widthBytes: 48, rows: 300) == Data([
        0x1D, 0x76, 0x30, 0x00, 48, 0, 44, 1
    ]))
}
