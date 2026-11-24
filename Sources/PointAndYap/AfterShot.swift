import AppKit
import Foundation

/// The "after" picture for the done banner: when an agent finishes an item, one screenshot of the same spot the user pointed at.
/// It shows the screen as it is now, which may not show the change (another app in front, another Space).
enum AfterShot {
    /// How long the banner waits for the screenshot before it shows without one.
    static let captureTimeout: TimeInterval = 1.5

    /// The crop rectangle in global points for a point on a display: up to 900 x 600, centered on the point and kept inside the display.
    /// This is the same math as the crops Builder cuts, kept here so Builder stays untouched.
    static func cropRect(for point: PointEvent, display: CGRect) -> CGRect {
        let width = min(900.0, display.width), height = min(600.0, display.height)
        var rect = CGRect(x: point.at.x - width / 2, y: point.at.y - height / 2, width: width, height: height)
        rect.origin.x = max(display.minX, min(rect.origin.x, display.maxX - width))
        rect.origin.y = max(display.minY, min(rect.origin.y, display.maxY - height))
        return rect
    }

    /// The same rectangle in image pixels (the image shows the whole display at `scale` pixels per point).
    static func pixelRect(for rect: CGRect, display: CGRect, scale: Double) -> CGRect {
        CGRect(x: (rect.minX - display.minX) * scale, y: (rect.minY - display.minY) * scale,
               width: rect.width * scale, height: rect.height * scale)
    }

    /// The point behind an item's first crop: `crops/NN.jpg` belongs to the point with index NN - 1 in events.json.
    static func firstPoint(of item: Item, in dir: URL) -> PointEvent? {
        guard let crop = item.crops.first, let number = Int(crop.deletingPathExtension().lastPathComponent), number >= 1,
              let data = try? Data(contentsOf: dir.appendingPathComponent("events.json")),
              let events = try? JSONDecoder.iso.decode(SessionEvents.self, from: data) else { return nil }
        return events.points.first { $0.index == number - 1 }
    }

    /// The banner notice for a finished item: the before crop, the session folder and, when it can, the after crop.
    /// An item without crops gets a plain notice and no screenshot.
    static func notice(item: Item, project: String) async -> BannerNotice {
        let dir = Paths.root.appendingPathComponent(item.session)
        var notice = BannerNotice(project: project, note: item.note ?? item.title, itemId: item.id)
        guard let before = item.crops.first, let point = firstPoint(of: item, in: dir) else { return notice }
        notice.before = before
        notice.session = dir
        notice.after = await capture(session: dir, point: point)
        return notice
    }

    /// Takes one screenshot of the display under `point`, crops the same rectangle and writes `after/01.jpg` in the session folder
    /// (an item that is done again overwrites it). Nil when Screen Recording is off, the shot fails or takes longer than the timeout.
    static func capture(session dir: URL, point: PointEvent, timeout: TimeInterval = captureTimeout) async -> URL? {
        guard CGPreflightScreenCaptureAccess() else { return nil }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("pointroo-after-\(UUID().uuidString).jpg")
        let location = CGPoint(x: point.at.x, y: point.at.y)
        let shot = await withTimeout(timeout, cleanup: { try? FileManager.default.removeItem(at: temporary) }) {
            await Screen.capture(at: location, to: temporary)
        }
        guard let shot else { return nil }
        let target = dir.appendingPathComponent("after/01.jpg")
        let rect = cropRect(for: point, display: shot.display)
        let written = await Task.detached(priority: .utility) {
            writeCrop(from: temporary, rect: rect, display: shot.display, scale: shot.scale, to: target)
        }.value
        try? FileManager.default.removeItem(at: temporary)
        return written ? target : nil
    }

    /// Cuts `rect` (global points) out of a full-display image and writes it as a JPEG, at most 1200 px wide, atomically.
    /// With `redactSecrets` (the user's setting by default) the secrets in the cut are blurred before anything is written.
    static func writeCrop(from source: URL, rect: CGRect, display: CGRect, scale: Double, to target: URL,
                          redactSecrets: Bool = Prefs.redactSecrets, redactor: Redact.Redactor = Redact.blur) -> Bool {
        guard let full = NSImage(contentsOf: source)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let cropped = full.cropping(to: pixelRect(for: rect, display: display, scale: scale)) else { return false }
        let cut = redactSecrets ? redactor(cropped).image : cropped
        var image = cut
        if cut.width > 1200 {
            let width = 1200, height = max(1, cut.height * 1200 / cut.width)
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .high
            context.draw(cut, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let scaled = context.makeImage() else { return false }
            image = scaled
        }
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.75]) else { return false }
        do {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Runs `work`; gives nil after `seconds` if it has not finished. When `work` finishes late, its result is dropped and `cleanup` runs.
    static func withTimeout<T: Sendable>(_ seconds: TimeInterval, cleanup: @escaping @Sendable () -> Void = {},
                                         _ work: @escaping @Sendable () async -> T?) async -> T? {
        await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            let gate = OnceGate()
            Task {
                let result = await work()
                if gate.claim() { continuation.resume(returning: result) } else { cleanup() }
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                if gate.claim() { continuation.resume(returning: nil) }
            }
        }
    }
}

/// True for the first caller only.
final class OnceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var taken = false

    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if taken { return false }
        taken = true
        return true
    }
}
