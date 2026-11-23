import AppKit
import Vision

/// Covers secrets (API keys, tokens, private keys) that are visible in screenshots, on this Mac, before any agent can read them.
enum Redact {
    typealias Redactor = (CGImage) -> (image: CGImage, changed: Bool)

    /// The long side of the copy that is sent to text recognition. The boxes are normalized, so they still fit the full image.
    static let recognitionLongSide: CGFloat = 2560
    /// How many frames are read at the same time.
    static let parallelFrames = 3
    /// Written in the session folder once the frames are done, so a second run skips them.
    static let markerName = "redacted"

    private static let labels = try! NSRegularExpression(
        pattern: #"(?i)(?:password|passwd|secret|token|api[ _-]?key)\s*[:=]\s*["']?([^\s"',;]+)"#)
    private static let separators = CharacterSet.whitespacesAndNewlines
        .union(CharacterSet(charactersIn: "\"'`:=,;()[]{}<>|"))
    private static let prefixes: [(prefix: String, minimumRest: Int)] = [
        ("sk-", 16), ("sk_live_", 8), ("pk_live_", 8), ("ghp_", 8), ("gho_", 8), ("github_pat_", 8), ("glpat-", 8),
    ]

    /// True for one token that has a clear secret shape. Plain words, sentences and 40-character git commit ids are not secrets.
    static func isSecret(_ text: String) -> Bool {
        let token = text.trimmingCharacters(in: CharacterSet(charactersIn: ".,;"))
        guard token.count >= 8 else { return false }
        for (prefix, minimumRest) in prefixes where token.hasPrefix(prefix) && token.count - prefix.count >= minimumRest { return true }
        if matches(token, #"^xox[abposr]-[A-Za-z0-9-]{8,}$"#) { return true }
        if matches(token, #"^AKIA[A-Z0-9]{16}$"#) { return true }
        if matches(token, #"^AIza[A-Za-z0-9_-]{35}$"#) { return true }
        if matches(token, #"^eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*$"#) { return true }
        if token.count >= 64, matches(token, #"^[0-9a-fA-F]+$"#) { return true }
        if token.count >= 40, matches(token, #"^[A-Za-z0-9+/_-]+$"#), mixedClasses(token) >= 3 { return true }
        return false
    }

    /// The value after a label ("password: ...") counts only when the value itself looks like a secret.
    static func looksSecretish(_ value: String) -> Bool {
        guard value.count >= 8 else { return false }
        if matches(value, #"^[0-9a-fA-F]{40}$"#) { return false }
        return mixedClasses(value) >= 2 && value.contains { $0.isNumber || !$0.isLetter }
    }

    /// The parts of one line of text that are secrets, so only those get covered and not the whole line.
    static func secretRanges(in line: String) -> [Range<String.Index>] {
        var found: [Range<String.Index>] = []
        let whole = NSRange(line.startIndex..., in: line)
        if line.contains("PRIVATE KEY-----"), line.contains("-----BEGIN") { return [line.startIndex..<line.endIndex] }
        for match in labels.matches(in: line, range: whole) {
            if let range = Range(match.range(at: 1), in: line), looksSecretish(String(line[range])) { found.append(range) }
        }
        var start: String.Index? = nil
        var index = line.startIndex
        func close(at end: String.Index) {
            if let from = start, isSecret(String(line[from..<end])) { found.append(from..<end) }
            start = nil
        }
        while index < line.endIndex {
            if line[index].unicodeScalars.allSatisfy({ separators.contains($0) }) { close(at: index) }
            else if start == nil { start = index }
            index = line.index(after: index)
        }
        close(at: line.endIndex)
        return found
    }

    /// Letters in lower case, upper case, digits and symbols: how many of these four groups the text uses.
    private static func mixedClasses(_ text: String) -> Int {
        var lower = false, upper = false, digit = false, symbol = false
        for character in text {
            if character.isLowercase { lower = true } else if character.isUppercase { upper = true }
            else if character.isNumber { digit = true } else { symbol = true }
        }
        return [lower, upper, digit, symbol].filter { $0 }.count
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    /// Reads the text in the image and fills the box of each secret with a dark block. On any error the image comes back unchanged.
    static func blur(_ image: CGImage) -> (image: CGImage, changed: Bool) {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        let small = scaled(image, longSide: recognitionLongSide)
        do { try VNImageRequestHandler(cgImage: small).perform([request]) } catch { return (image, false) }
        var boxes: [CGRect] = []
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            for range in secretRanges(in: candidate.string) {
                if let box = try? candidate.boundingBox(for: range) { boxes.append(box.boundingBox) }
            }
        }
        guard !boxes.isEmpty else { return (image, false) }
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return (image, false) }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(gray: 0.15, alpha: 1))
        for box in boxes {
            let rect = CGRect(x: box.minX * Double(width), y: box.minY * Double(height),
                              width: box.width * Double(width), height: box.height * Double(height)).insetBy(dx: -3, dy: -3)
            context.fill(rect)
        }
        guard let result = context.makeImage() else { return (image, false) }
        return (result, true)
    }

    private static func scaled(_ image: CGImage, longSide: CGFloat) -> CGImage {
        let long = CGFloat(max(image.width, image.height))
        guard long > longSide else { return image }
        let factor = longSide / long
        let width = Int(CGFloat(image.width) * factor), height = Int(CGFloat(image.height) * factor)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    /// Redacts one JPEG file in place. The file is rewritten (atomically) only when something was covered. Returns whether it was.
    @discardableResult
    static func redactFile(_ url: URL, redactor: Redactor = Redact.blur) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return false }
        let result = redactor(image)
        guard result.changed else { return false }
        return Screen.write(result.image, to: url)
    }

    /// Redacts every frame of a session before anything is built from it. Writes the marker at the end. Returns how many frames changed.
    @discardableResult
    static func redactFrames(dir: URL, files: [String], redactor: @escaping Redactor = Redact.blur) async -> Int {
        let marker = dir.appendingPathComponent(markerName)
        if FileManager.default.fileExists(atPath: marker.path) { return 0 }
        var changed = 0
        await withTaskGroup(of: Bool.self) { group in
            var next = 0
            func addNext() {
                guard next < files.count else { return }
                let url = dir.appendingPathComponent(files[next])
                next += 1
                group.addTask { redactFile(url, redactor: redactor) }
            }
            for _ in 0..<parallelFrames { addNext() }
            while let didChange = await group.next() {
                if didChange { changed += 1 }
                addNext()
            }
        }
        try? Data().write(to: marker, options: .atomic)
        return changed
    }
}
