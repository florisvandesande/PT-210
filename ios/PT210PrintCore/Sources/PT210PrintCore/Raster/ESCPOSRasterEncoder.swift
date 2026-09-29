import Foundation

public enum ESCPOSRasterEncoder {
    /// PT210L firmware does not reliably implement the ESC/POS `ESC d n`
    /// command. Feeding white raster rows uses the same proven transport path
    /// as printed content and therefore works consistently on this model.
    public static func makeFeedStrips(
        widthBytes: Int,
        lines: Int,
        dotsPerLine: Int = 24,
        rowsPerStrip: Int
    ) throws -> [Data] {
        guard lines >= 0, dotsPerLine > 0, rowsPerStrip > 0 else {
            throw PrintError.invalidSettings
        }
        guard lines > 0 else { return [] }
        let rows = lines * dotsPerLine
        let bitmap = try MonochromeBitmap(
            width: widthBytes * 8,
            height: rows,
            bytesPerRow: widthBytes,
            data: Data(repeating: 0, count: widthBytes * rows)
        )
        return try makeStrips(bitmap: bitmap, rowsPerStrip: rowsPerStrip)
    }

    public static func makeStrips(
        bitmap: MonochromeBitmap,
        rowsPerStrip: Int
    ) throws -> [Data] {
        guard rowsPerStrip > 0 else { throw PrintError.invalidSettings }
        var strips: [Data] = []
        var firstRow = 0

        while firstRow < bitmap.height {
            let rows = min(rowsPerStrip, bitmap.height - firstRow)
            var strip = try ESCPos.rasterHeader(widthBytes: bitmap.bytesPerRow, rows: rows)
            let start = firstRow * bitmap.bytesPerRow
            let end = start + rows * bitmap.bytesPerRow
            strip.append(bitmap.data[start..<end])
            strips.append(strip)
            firstRow += rows
        }
        return strips
    }
}
