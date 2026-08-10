import AppKit
import ScreenCaptureKit
import UniformTypeIdentifiers

/// One-shot screenshot of the display the cursor is on.
///
/// Uses ScreenCaptureKit: CGWindowListCreateImage is deprecated and on recent
/// macOS returns a black or desktop-only image once the app is sandboxed by the
/// hardened runtime.
enum ScreenCapture {

    enum CaptureError: LocalizedError {
        case noPermission
        case noDisplay
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .noPermission:
                return L("Нет доступа к записи экрана — включите CodeCoach в «Конфиденциальность и безопасность → Запись экрана»")
            case .noDisplay:
                return L("Не удалось определить экран для снимка")
            case .encodingFailed:
                return L("Не удалось закодировать снимок экрана")
            }
        }
    }

    struct Shot {
        let png: Data
        /// Long edge in pixels after downscaling.
        let longEdge: Int
    }

    /// Fable 5 accepts images up to 2576 px on the long edge and bills up to
    /// ~4784 tokens for one. A coding-problem screenshot stays readable well
    /// below that, and the smaller image is both cheaper and faster to upload —
    /// so downscale, but not so far that the problem text stops being legible.
    private static let maxLongEdge = 1800

    static func captureDisplayUnderCursor() async throws -> Shot {
        guard Permissions.screenRecording == .granted else {
            // The app appears in the Screen Recording pane only after it has
            // asked at least once. Ask right here, so even a bare hotkey press
            // on a fresh install triggers the system prompt (one-shot) and
            // registers the app for manual granting.
            Log.d("capture: no permission -> requesting")
            Permissions.requestScreenRecording()
            throw CaptureError.noPermission
        }

        // onScreenWindowsOnly: false — we want the display, not a window list,
        // and excluding desktop windows keeps the wallpaper out of the filter.
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let targetID = screen?.displayID

        let display = content.displays.first { $0.displayID == targetID }
            ?? content.displays.first
        guard let display else { throw CaptureError.noDisplay }

        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        config.captureResolution = .best
        config.showsCursor = false

        // Exclude our own windows: the panel from a previous problem must not
        // end up inside the screenshot of the next one.
        let ourWindows = content.windows.filter {
            $0.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        let filter = SCContentFilter(display: display, excludingWindows: ourWindows)

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter, configuration: config)

        let scaled = downscale(image, maxLongEdge: maxLongEdge)
        guard let png = pngData(from: scaled) else { throw CaptureError.encodingFailed }

        let edge = max(scaled.width, scaled.height)
        Log.d("capture: display \(display.width)x\(display.height) -> \(scaled.width)x\(scaled.height), \(png.count / 1024) KB")
        return Shot(png: png, longEdge: edge)
    }

    private static func downscale(_ image: CGImage, maxLongEdge: Int) -> CGImage {
        let longEdge = max(image.width, image.height)
        guard longEdge > maxLongEdge else { return image }

        let scale = Double(maxLongEdge) / Double(longEdge)
        let width = Int((Double(image.width) * scale).rounded())
        let height = Int((Double(image.height) * scale).rounded())

        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return image }

        // High interpolation matters here: the model has to read small text off
        // this image, and a cheap resample smears it into unreadable glyphs.
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    private static func pngData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
