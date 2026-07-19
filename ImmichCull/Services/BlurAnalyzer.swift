import UIKit

enum BlurAnalyzer {
    /// Sharpness as the variance of a 4-neighbour Laplacian over a small
    /// grayscale render. Lower values mean blurrier images.
    static func sharpnessScore(of image: UIImage) -> Double {
        guard let cgImage = image.cgImage else { return 0 }
        let maxSide = 160.0
        let scale = min(1, maxSide / Double(max(cgImage.width, cgImage.height)))
        let width = max(3, Int(Double(cgImage.width) * scale))
        let height = max(3, Int(Double(cgImage.height) * scale))

        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .low
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return 0 }

        var sum = 0.0
        var sumOfSquares = 0.0
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let index = y * width + x
                let laplacian = 4 * Int(pixels[index])
                    - Int(pixels[index - 1]) - Int(pixels[index + 1])
                    - Int(pixels[index - width]) - Int(pixels[index + width])
                let value = Double(laplacian)
                sum += value
                sumOfSquares += value * value
            }
        }
        let count = Double((width - 2) * (height - 2))
        let mean = sum / count
        return sumOfSquares / count - mean * mean
    }
}
