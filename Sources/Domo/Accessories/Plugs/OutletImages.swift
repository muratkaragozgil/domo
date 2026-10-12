import AppKit
import UniformTypeIdentifiers

/// Pictures people give their own outlets (their actual monitor, lamp…).
/// They stay on this Mac, never in the repo:
/// ~/Library/Application Support/Domo/Outlet Images/<strip id>.<channel>.png
enum OutletImages {
    static let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: "Domo/Outlet Images", directoryHint: .isDirectory)

    private static var cache: [String: NSImage] = [:]

    static func image(for key: String) -> NSImage? {
        if let cached = cache[key] { return cached }
        let url = directory.appending(path: "\(key).png")
        guard FileManager.default.fileExists(atPath: url.path), let image = NSImage(contentsOf: url) else { return nil }
        cache[key] = image
        return image
    }

    /// Asks for an image file and stores a 256px PNG copy. Returns false if cancelled.
    static func choose(for key: String, title: String) -> Bool {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a picture for \(title). A cut-out PNG looks best."
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return (try? save(from: url, for: key)) != nil
    }

    static func remove(for key: String) {
        try? FileManager.default.removeItem(at: directory.appending(path: "\(key).png"))
        cache[key] = nil
    }

    private static func save(from source: URL, for key: String) throws {
        guard let image = NSImage(contentsOf: source), image.size.width > 0, image.size.height > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let scale = min(1, 256 / max(image.size.width, image.size.height))
        let size = NSSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { throw CocoaError(.fileWriteUnknown) }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: directory.appending(path: "\(key).png"), options: .atomic)
        cache[key] = nil
    }
}
