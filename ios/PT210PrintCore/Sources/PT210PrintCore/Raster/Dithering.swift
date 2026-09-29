import Accelerate
import Foundation

public struct GrayscaleImage: Sendable {
    public let width: Int
    public let height: Int
    public let pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) throws {
        guard width > 0, height > 0, pixels.count == width * height else {
            throw PrintError.invalidBitmap
        }
        self.width = width
        self.height = height
        self.pixels = pixels
    }
}

public enum Ditherer {
    public static func process(
        _ source: GrayscaleImage,
        algorithm: DitheringAlgorithm,
        threshold: Double,
        invert: Bool
    ) throws -> MonochromeBitmap {
        let limit = UInt8(clamping: Int(max(0, min(threshold, 1)) * 255))
        let output: [Bool] = switch algorithm {
        case .threshold: source.pixels.map { $0 < limit }
        case .bayer4x4: bayer(source, threshold: threshold)
        case .floydSteinberg: diffusion(source, threshold: limit, atkinson: false)
        case .atkinson: diffusion(source, threshold: limit, atkinson: true)
        }
        return try pack(output, width: source.width, height: source.height, invert: invert)
    }

    /// Uses Apple's reproducible, uniform blue-noise conversion so repeated
    /// diagnostic prints contain exactly the same dot pattern.
    public static func processReproducibleBlueNoise(
        _ source: GrayscaleImage,
        threshold: Double,
        invert: Bool
    ) throws -> MonochromeBitmap {
        let bytesPerRow = (source.width + 7) / 8
        var adjusted = source.pixels
        let offset = Int((max(0, min(threshold, 1)) - 0.5) * 255)
        if offset != 0 {
            for index in adjusted.indices {
                adjusted[index] = UInt8(clamping: Int(adjusted[index]) - offset)
            }
        }
        var data = Data(repeating: 0, count: bytesPerRow * source.height)
        let result = adjusted.withUnsafeMutableBytes { sourceBytes in
            data.withUnsafeMutableBytes { destinationBytes in
                var sourceBuffer = vImage_Buffer(
                    data: sourceBytes.baseAddress,
                    height: vImagePixelCount(source.height),
                    width: vImagePixelCount(source.width),
                    rowBytes: source.width
                )
                var destinationBuffer = vImage_Buffer(
                    data: destinationBytes.baseAddress,
                    height: vImagePixelCount(source.height),
                    width: vImagePixelCount(source.width),
                    rowBytes: bytesPerRow
                )
                let dither = kvImageConvert_DitherOrderedReproducible
                    | kvImageConvert_OrderedUniformBlue
                return vImageConvert_Planar8toPlanar1(
                    &sourceBuffer,
                    &destinationBuffer,
                    nil,
                    Int32(bitPattern: dither),
                    vImage_Flags(kvImageNoFlags)
                )
            }
        }
        guard result == kvImageNoError else { throw PrintError.renderFailed }

        // vImage uses set bits for white; ESC/POS uses set bits for heated
        // (black) dots. Flip once, or preserve vImage's polarity for invert.
        if !invert {
            for index in data.indices { data[index] = ~data[index] }
        }
        return try MonochromeBitmap(
            width: source.width,
            height: source.height,
            bytesPerRow: bytesPerRow,
            data: data
        )
    }

    private static func bayer(_ source: GrayscaleImage, threshold: Double) -> [Bool] {
        let matrix = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
        return source.pixels.enumerated().map { index, value in
            let x = index % source.width
            let y = index / source.width
            let adjusted = (Double(matrix[(y % 4) * 4 + (x % 4)]) + 0.5) / 16
            let combined = max(0, min(1, adjusted + threshold - 0.5))
            return Double(value) / 255 < combined
        }
    }

    private static func diffusion(
        _ source: GrayscaleImage,
        threshold: UInt8,
        atkinson: Bool
    ) -> [Bool] {
        var values = source.pixels.map(Double.init)
        var black = Array(repeating: false, count: values.count)

        func add(_ x: Int, _ y: Int, _ error: Double, _ factor: Double) {
            guard x >= 0, y >= 0, x < source.width, y < source.height else { return }
            let i = y * source.width + x
            values[i] = max(0, min(255, values[i] + error * factor))
        }

        for y in 0..<source.height {
            for x in 0..<source.width {
                let i = y * source.width + x
                let old = values[i]
                let new = old < Double(threshold) ? 0.0 : 255.0
                black[i] = new == 0
                let error = old - new
                if atkinson {
                    for (dx, dy) in [(1, 0), (2, 0), (-1, 1), (0, 1), (1, 1), (0, 2)] {
                        add(x + dx, y + dy, error, 1.0 / 8.0)
                    }
                } else {
                    add(x + 1, y, error, 7.0 / 16.0)
                    add(x - 1, y + 1, error, 3.0 / 16.0)
                    add(x, y + 1, error, 5.0 / 16.0)
                    add(x + 1, y + 1, error, 1.0 / 16.0)
                }
            }
        }
        return black
    }

    private static func pack(
        _ black: [Bool],
        width: Int,
        height: Int,
        invert: Bool
    ) throws -> MonochromeBitmap {
        let bytesPerRow = (width + 7) / 8
        var data = Data(repeating: 0, count: bytesPerRow * height)
        for y in 0..<height {
            for x in 0..<width where black[y * width + x] != invert {
                data[y * bytesPerRow + x / 8] |= UInt8(0x80 >> (x % 8))
            }
        }
        return try MonochromeBitmap(width: width, height: height, bytesPerRow: bytesPerRow, data: data)
    }
}
