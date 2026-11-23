import Foundation

/// From a recorded folder to the timeline (session.md) and crops, all on this Mac. Returns session.md.
enum Process {
    static func run(dir: URL, log: (String) -> Void = { NSLog("pointroo: \($0)") },
                    redactSecrets: Bool = Prefs.redactSecrets, redactor: @escaping Redact.Redactor = Redact.blur,
                    onTimeline: (@MainActor () -> Void)? = nil) async -> String {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("events.json")),
              let events = try? JSONDecoder.iso.decode(SessionEvents.self, from: data) else {
            return "Pointroo: no events.json in \(dir.path)"
        }
        var words: [Word] = []
        let audio = dir.appendingPathComponent("audio.caf")
        let wordsFile = dir.appendingPathComponent("transcript.json")
        if let cached = try? Data(contentsOf: wordsFile), let w = try? JSONDecoder().decode([Word].self, from: cached) {
            words = w
        } else if FileManager.default.fileExists(atPath: audio.path) {
            do {
                words = try await Transcriber.words(from: audio)
                try? JSONEncoder.pretty.encode(words).write(to: wordsFile)
            } catch {
                log("transcription failed: \(error)")
            }
        }
        log("\(words.count) words, \(events.points.count) points, \(events.frames.count) frames")

        if redactSecrets {
            let started = Date()
            let changed = await Redact.redactFrames(dir: dir, files: events.frames.map(\.file), redactor: redactor)
            log("blurred secrets in \(changed) of \(events.frames.count) frames in \(String(format: "%.1f", Date().timeIntervalSince(started))) s")
        }
        let out = Builder.build(dir: dir, events: events, words: words)
        if !words.isEmpty { Router.routeSession(dir, events: events, words: words) }
        if let onTimeline { await onTimeline() }
        return out.markdown
    }
}
