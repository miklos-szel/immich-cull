import Foundation

enum ScreenshotDetector {
    /// Heuristic: screenshot-style filename, or a PNG with no camera EXIF.
    static func isScreenshot(_ asset: ImmichAsset) -> Bool {
        guard asset.type == .image else { return false }
        let name = asset.originalFileName.lowercased()
        if name.contains("screenshot") || name.contains("screen shot") || name.contains("screen_shot") {
            return true
        }
        let isPNG = asset.originalMimeType?.lowercased() == "image/png"
        let cameraMake = asset.exifInfo?.make ?? ""
        return isPNG && cameraMake.isEmpty
    }
}
