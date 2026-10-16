import AppKit
import ScreenCaptureKit

enum CaptureError: Error, CustomStringConvertible {
    case noScreenPermission
    case noWindow(String)

    var description: String {
        switch self {
        case .noScreenPermission:
            return "Screen Recording permission missing. Grant it in System Settings > Privacy & Security > Screen Recording, then restart appshot."
        case .noWindow(let app):
            return "No on-screen window found for \(app)."
        }
    }
}

enum WindowCapture {
    static var hasScreenPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Front-most normal on-screen window of `pid` (CGWindowList is ordered front to back).
    static func frontWindowID(pid: pid_t) -> CGWindowID? {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for info in list {
            guard let owner = info[kCGWindowOwnerPID as String] as? Int32, owner == pid,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let number = info[kCGWindowNumber as String] as? UInt32
            else { continue }
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha <= 0 { continue }
            if let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
               let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
               rect.width < 50 || rect.height < 50 { continue }
            return CGWindowID(number)
        }
        return nil
    }

    static func capture(pid: pid_t, appName: String) async throws -> (image: CGImage, title: String?, frame: CGRect) {
        guard hasScreenPermission else {
            _ = CGRequestScreenCaptureAccess()
            throw CaptureError.noScreenPermission
        }
        guard let windowID = frontWindowID(pid: pid) else { throw CaptureError.noWindow(appName) }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureError.noWindow(appName)
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        let config = SCStreamConfiguration()
        config.width = max(1, Int(filter.contentRect.width * scale))
        config.height = max(1, Int(filter.contentRect.height * scale))
        config.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return (image, window.title, window.frame)  // frame: global top-left-origin points
    }
}
