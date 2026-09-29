import Accelerate
import CoreGraphics
import Foundation

public enum ImageProcessor {
    public static func grayscale(
        image: CGImage,
        targetWidth: Int,
        quality: QualitySettings,
        scaling: ImageScalingMode = .fitWidth,
        calibrationProcessing: CalibrationImageProcessing = .standard
    ) throws -> GrayscaleImage {
        guard targetWidth > 0, targetWidth <= 384 else { throw PrintError.invalidSettings }
        let sourceWidth = CGFloat(image.width)
        let sourceHeight = CGFloat(image.height)
        let width: Int
        let height: Int
        let drawRect: CGRect

        switch scaling {
        case .fitWidth:
            let scale = CGFloat(targetWidth) / sourceWidth
            width = targetWidth
            height = max(1, Int((sourceHeight * scale).rounded()))
            drawRect = CGRect(x: 0, y: 0, width: width, height: height)
        case .actualSize:
            width = min(targetWidth, image.width)
            height = image.height
            drawRect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        case .center:
            let scale = min(1, CGFloat(targetWidth) / sourceWidth)
            let drawnWidth: Int = max(1, Int((sourceWidth * scale).rounded()))
            let drawnHeight: Int = max(1, Int((sourceHeight * scale).rounded()))
            width = targetWidth
            height = drawnHeight
            drawRect = CGRect(
                x: (width - drawnWidth) / 2,
                y: 0,
                width: drawnWidth,
                height: drawnHeight
            )
        case .cropToWidth:
            width = targetWidth
            height = targetWidth
            let scale = max(CGFloat(targetWidth) / sourceWidth, CGFloat(targetWidth) / sourceHeight)
            let drawnWidth = sourceWidth * scale
            let drawnHeight = sourceHeight * scale
            drawRect = CGRect(
                x: (CGFloat(width) - drawnWidth) / 2,
                y: (CGFloat(height) - drawnHeight) / 2,
                width: drawnWidth,
                height: drawnHeight
            )
        }
        var pixels: [UInt8]
        if calibrationProcessing == .lanczos5, scaling == .fitWidth {
            pixels = try highQualityResample(image: image, width: width, height: height)
        } else {
            pixels = [UInt8](repeating: 255, count: width * height)
            guard let context = grayscaleContext(data: &pixels, width: width, height: height) else {
                throw PrintError.renderFailed
            }
            context.interpolationQuality = .high
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(image, in: drawRect)
        }

        let gamma = max(0.1, min(quality.gamma, 4))
        let contrast = max(0, min(quality.contrast, 3))
        let brightness = max(-1, min(quality.brightness, 1)) * 255
        for index in pixels.indices {
            let normalized = pow(Double(pixels[index]) / 255, 1 / gamma)
            let adjusted = ((normalized - 0.5) * contrast + 0.5) * 255 + brightness
            pixels[index] = UInt8(clamping: Int(adjusted.rounded()))
        }

        if calibrationProcessing == .percentileContrast {
            pixels = percentileContrastStretch(pixels, lowerPercent: 0.01, upperPercent: 0.01)
        }

        if let amount = quality.localContrast, amount > 0 {
            pixels = enhanceDetails(
                pixels,
                width: width,
                height: height,
                radius: 5,
                amount: min(amount, 1)
            )
        }
        if let amount = quality.sharpness, amount > 0 {
            pixels = enhanceDetails(
                pixels,
                width: width,
                height: height,
                radius: 1,
                amount: min(amount, 2)
            )
        }
        return try GrayscaleImage(width: width, height: height, pixels: pixels)
    }

    /// Applies an efficient unsharp mask using a box-blurred local average.
    /// A larger radius raises local contrast; a one-pixel radius sharpens edges.
    private static func enhanceDetails(
        _ pixels: [UInt8],
        width: Int,
        height: Int,
        radius: Int,
        amount: Double
    ) -> [UInt8] {
        let integralWidth = width + 1
        var integral = [Int](repeating: 0, count: integralWidth * (height + 1))

        for y in 0..<height {
            var rowSum = 0
            for x in 0..<width {
                rowSum += Int(pixels[y * width + x])
                integral[(y + 1) * integralWidth + x + 1] =
                    integral[y * integralWidth + x + 1] + rowSum
            }
        }

        var output = pixels
        for y in 0..<height {
            let top = max(0, y - radius)
            let bottom = min(height, y + radius + 1)
            for x in 0..<width {
                let left = max(0, x - radius)
                let right = min(width, x + radius + 1)
                let sum = integral[bottom * integralWidth + right]
                    - integral[top * integralWidth + right]
                    - integral[bottom * integralWidth + left]
                    + integral[top * integralWidth + left]
                let count = (right - left) * (bottom - top)
                let localAverage = Double(sum) / Double(count)
                let original = Double(pixels[y * width + x])
                let enhanced = original + (original - localAverage) * amount
                output[y * width + x] = UInt8(clamping: Int(enhanced.rounded()))
            }
        }
        return output
    }

    public static func monochrome(
        image: CGImage,
        settings: PrinterSettings,
        calibrationProcessing: CalibrationImageProcessing = .standard
    ) throws -> MonochromeBitmap {
        let contentWidth = settings.render.pageWidthPixels - (settings.render.horizontalMargin * 2)
        let gray = try grayscale(
            image: image,
            targetWidth: contentWidth,
            quality: settings.quality,
            scaling: settings.render.imageScaling,
            calibrationProcessing: calibrationProcessing
        )
        let content = if calibrationProcessing == .reproducibleBlueNoise {
            try Ditherer.processReproducibleBlueNoise(
                gray,
                threshold: settings.quality.threshold,
                invert: settings.quality.invert
            )
        } else {
            try Ditherer.process(
                gray,
                algorithm: settings.quality.dithering,
                threshold: settings.quality.threshold,
                invert: settings.quality.invert
            )
        }
        return try addMargins(
            content,
            pageWidth: settings.render.pageWidthPixels,
            horizontal: settings.render.horizontalMargin,
            top: settings.render.topMargin,
            bottom: settings.render.bottomMargin
        )
    }

    private static func grayscaleContext(
        data: UnsafeMutableRawPointer,
        width: Int,
        height: Int
    ) -> CGContext? {
        CGContext(
            data: data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )
    }

    /// Draws at up to four times the printer resolution and lets vImage use
    /// its high-quality resampling filter for the final 384-dot reduction.
    private static func highQualityResample(
        image: CGImage,
        width: Int,
        height: Int
    ) throws -> [UInt8] {
        let factor = min(4, max(1, image.width / max(1, width)))
        let sourceWidth = width * factor
        let sourceHeight = height * factor
        var sourcePixels = [UInt8](repeating: 255, count: sourceWidth * sourceHeight)
        guard let context = grayscaleContext(
            data: &sourcePixels,
            width: sourceWidth,
            height: sourceHeight
        ) else { throw PrintError.renderFailed }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: sourceWidth, height: sourceHeight))

        var destinationPixels = [UInt8](repeating: 255, count: width * height)
        let result = sourcePixels.withUnsafeMutableBytes { sourceBytes in
            destinationPixels.withUnsafeMutableBytes { destinationBytes in
                var source = vImage_Buffer(
                    data: sourceBytes.baseAddress,
                    height: vImagePixelCount(sourceHeight),
                    width: vImagePixelCount(sourceWidth),
                    rowBytes: sourceWidth
                )
                var destination = vImage_Buffer(
                    data: destinationBytes.baseAddress,
                    height: vImagePixelCount(height),
                    width: vImagePixelCount(width),
                    rowBytes: width
                )
                return vImageScale_Planar8(
                    &source,
                    &destination,
                    nil,
                    vImage_Flags(kvImageHighQualityResampling)
                )
            }
        }
        guard result == kvImageNoError else { throw PrintError.renderFailed }
        return destinationPixels
    }

    /// Ignores the brightest and darkest one percent before stretching the
    /// remaining tones. This avoids one outlier pixel controlling the range.
    private static func percentileContrastStretch(
        _ pixels: [UInt8],
        lowerPercent: Double,
        upperPercent: Double
    ) -> [UInt8] {
        guard !pixels.isEmpty else { return pixels }
        var histogram = [Int](repeating: 0, count: 256)
        for pixel in pixels { histogram[Int(pixel)] += 1 }
        let lowerTarget = Int(Double(pixels.count) * lowerPercent)
        let upperTarget = Int(Double(pixels.count) * upperPercent)
        var accumulated = 0
        var lower = 0
        for value in 0..<256 {
            accumulated += histogram[value]
            if accumulated >= lowerTarget { lower = value; break }
        }
        accumulated = 0
        var upper = 255
        for value in stride(from: 255, through: 0, by: -1) {
            accumulated += histogram[value]
            if accumulated >= upperTarget { upper = value; break }
        }
        guard upper > lower else { return pixels }
        let range = upper - lower
        return pixels.map { pixel in
            UInt8(clamping: (Int(pixel) - lower) * 255 / range)
        }
    }

    private static func addMargins(
        _ source: MonochromeBitmap,
        pageWidth: Int,
        horizontal: Int,
        top: Int,
        bottom: Int
    ) throws -> MonochromeBitmap {
        let bytesPerRow = (pageWidth + 7) / 8
        let height = top + source.height + bottom
        var data = Data(repeating: 0, count: bytesPerRow * height)
        for y in 0..<source.height {
            for x in 0..<source.width {
                let sourceByte = source.data[y * source.bytesPerRow + x / 8]
                guard sourceByte & (0x80 >> (x % 8)) != 0 else { continue }
                let destinationX = x + horizontal
                data[(y + top) * bytesPerRow + destinationX / 8] |= UInt8(0x80 >> (destinationX % 8))
            }
        }
        return try MonochromeBitmap(width: pageWidth, height: height, bytesPerRow: bytesPerRow, data: data)
    }
}
