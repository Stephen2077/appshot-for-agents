import AppKit

struct Record: Codable {
    var app: String
    var bundle_id: String
    var window_title: String
    var text: String
    var text_source: String   // "accessibility" | "ocr" | "none"
    var char_count: Int
    var nodes_visited: Int
    var truncated: Bool       // AX walk hit a limit (nodes / chars / depth / 3 s)
    var timestamp: String
    var image_path: String
    var json_path: String
}

enum Store {
    static let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".appshot", isDirectory: true)
    static var imageURL: URL { directory.appendingPathComponent("latest.png") }
    static var jsonURL: URL { directory.appendingPathComponent("latest.json") }

    static func png(from image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    /// Writes ~/.appshot/latest.png + latest.json (atomically) and puts the image on the clipboard.
    static func save(image: CGImage, record: Record) throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        guard let pngData = png(from: image) else {
            throw NSError(domain: "appshot", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG encoding failed"])
        }
        try pngData.write(to: imageURL, options: .atomic)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(record).write(to: jsonURL, options: .atomic)

        copyToClipboard(image: image, png: pngData)
    }

    static func copyToClipboard(image: CGImage, png pngData: Data? = nil) {
        guard let pngData = pngData ?? png(from: image) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([.png, .tiff], owner: nil)
        pb.setData(pngData, forType: .png)
        if let tiff = NSBitmapImageRep(cgImage: image).tiffRepresentation {
            pb.setData(tiff, forType: .tiff)
        }
    }

    static func timestamp() -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = .current
        return f.string(from: Date())
    }
}
