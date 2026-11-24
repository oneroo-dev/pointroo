import Foundation

/// "The next recording is a follow-up to this item": saved when the user clicks "Say more" on a done notice.
struct FollowUpRequest: Codable, Equatable {
    var id: String
    var path: String
    var at: Date
}

/// The one pending follow-up request, kept in `follow-next.json` in the app support folder (next to the queue).
/// It is read once, then removed.
struct FollowUpStore {
    /// A request older than this (before the recording started) is ignored.
    static let maxAge: TimeInterval = 600

    var folder: URL

    init(folder: URL? = nil) {
        self.folder = folder ?? Paths.support
    }

    var file: URL { folder.appendingPathComponent("follow-next.json") }

    /// Saves the request under the queue lock, replacing an older one. False when it could not save.
    @discardableResult
    func save(_ request: FollowUpRequest) -> Bool {
        Items.locked { () -> Bool in
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try JSONEncoder.pretty.encode(request).write(to: file, options: .atomic)
                return true
            } catch {
                return false
            }
        }
    }

    /// Reads the request and removes the file. Nil when there is none, it is broken, or it was saved more than
    /// `maxAge` seconds before the recording started.
    func take(recordingStarted: Date) -> FollowUpRequest? {
        Items.locked { () -> FollowUpRequest? in
            guard let data = try? Data(contentsOf: file) else { return nil }
            try? FileManager.default.removeItem(at: file)
            guard let request = try? JSONDecoder.iso.decode(FollowUpRequest.self, from: data) else { return nil }
            guard recordingStarted.timeIntervalSince(request.at) <= Self.maxAge else { return nil }
            return request
        }
    }

    /// Removes the request, if any.
    func remove() {
        Items.locked { () -> Void in
            try? FileManager.default.removeItem(at: file)
        }
    }
}
