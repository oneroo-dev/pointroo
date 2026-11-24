import Foundation

/// What recording.get reports and recording.changed is built from. `phase` is idle, recording, processing or picking.
struct RecordingSnapshot: Equatable {
    var phase: String
    var startedAt: Date?
    var points: Int
    var words: [String] = []
}

/// What picker.get reports: the open project picker. `countdown` is the seconds left before it skips by itself.
struct PickerSnapshot: Equatable {
    struct Choice: Equatable {
        var name: String
        var path: String
        var key: Int
        var suggested: Bool
    }

    var session: String?
    var choices: [Choice]
    var countdown: Int?
}

/// Decides what the page should be told. Snapshot in, events out: no timers, no disk, no web view.
/// Each call compares the snapshot with the one before and returns an event only when something changed.
/// The first call of each kind always returns its event.
struct WebEvents {
    typealias Event = (name: String, data: [String: Any])

    private var itemSignature: [String]?
    private var questionIdentifiers: [String]?
    private var noticeIdentifiers: [String]?
    private var recordingState: (phase: String, pointCount: Int)?

    private var lastStatus: AppStatus?
    private var pickerSignature: String?

    init() {}

    /// `items.changed` {count, open, inProgress} when any item's id, status, note or project changed (or one came or went).
    mutating func items(_ items: [Item]) -> [Event] {
        let signature = items
            .map { "\($0.id)\u{1F}\($0.status)\u{1F}\($0.note ?? "")\u{1F}\($0.project ?? "")" }
            .sorted()
        guard signature != itemSignature else { return [] }
        itemSignature = signature
        let open = items.filter { $0.status == "open" }.count
        let inProgress = items.filter { $0.status == "in_progress" }.count
        return [(name: "items.changed", data: ["count": items.count, "open": open, "inProgress": inProgress])]
    }

    /// `questions.changed` {count} when the set of pending question ids changed.
    mutating func questions(_ questions: [Question]) -> [Event] {
        let identifiers = questions.map(\.id).sorted()
        guard identifiers != questionIdentifiers else { return [] }
        questionIdentifiers = identifiers
        return [(name: "questions.changed", data: ["count": questions.count])]
    }

    /// `notices.changed` {count} when the set of notice ids changed (see Notices.identifiers).
    mutating func notices(_ identifiers: [String]) -> [Event] {
        let sorted = identifiers.sorted()
        guard sorted != noticeIdentifiers else { return [] }
        noticeIdentifiers = sorted
        return [(name: "notices.changed", data: ["count": sorted.count])]
    }

    /// `status.changed` {the AppStatus dictionary} when any part of the status changed.
    mutating func status(_ status: AppStatus) -> [Event] {
        guard status != lastStatus else { return [] }
        lastStatus = status
        return [(name: "status.changed", data: status.dictionary)]
    }

    /// `picker.changed` {open, session?} when the project picker opened or closed (the countdown alone never emits).
    mutating func picker(_ snapshot: PickerSnapshot?) -> [Event] {
        let signature = snapshot.map { "open\u{1F}\($0.session ?? "")" } ?? "closed"
        guard signature != pickerSignature else { return [] }
        pickerSignature = signature
        var data: [String: Any] = ["open": snapshot != nil]
        if let session = snapshot?.session { data["session"] = session }
        return [(name: "picker.changed", data: data)]
    }

    /// `recording.changed` {phase: "idle" | "recording" | "processing" | "picking", pointCount} when the phase or the point count changed.
    mutating func recording(phase: String, pointCount: Int) -> [Event] {
        if let last = recordingState, last.phase == phase, last.pointCount == pointCount { return [] }
        recordingState = (phase: phase, pointCount: pointCount)
        return [(name: "recording.changed", data: ["phase": phase, "pointCount": pointCount])]
    }
}
