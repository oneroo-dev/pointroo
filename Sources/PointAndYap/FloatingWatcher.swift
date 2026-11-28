import Foundation

/// Decides when an agent's question opens the kit notice card: only an id that was not pending at the last look.
/// A question that is answered or put off leaves the pending list, so it never shows again by itself; one that comes back after
/// its snooze is a new arrival again.
struct QuestionArrivals {
    private var known: Set<String>?

    init() {}

    /// The ids in `pending` that were not pending at the last call, oldest first as given. The first call only learns the set
    /// and returns nothing, so questions that were already waiting when the app started do not pop up.
    mutating func arrived(_ pending: [String]) -> [String] {
        let previous = known
        known = Set(pending)
        guard let previous else { return [] }
        return pending.filter { !previous.contains($0) }
    }
}

/// What one tick of the watcher should read from the disk.
struct WatcherReads: Equatable {
    var items: Bool
    var questions: Bool
}

/// The choice of what to read on a tick, kept apart from the timer so it can be tested.
/// Items (the route.sent check) are read only inside a read window that opens when a recording stops or a route is written,
/// plus once to learn the starting set. Questions are checked on a slow tick, because one can arrive at any time.
enum WatcherSchedule {
    static let readWindowSeconds: TimeInterval = 30
    static let questionIntervalSeconds: TimeInterval = 5

    /// `windowOpenedAt` is when the read window was last opened (nil if never). `lastQuestionCheck` is when questions were last read.
    /// `needsBaseline` is true until the first item read after the setting went on, so old recordings never look new.
    static func reads(now: Date, windowOpenedAt: Date?, lastQuestionCheck: Date?, needsBaseline: Bool = false,
                      kitFloating: Bool) -> WatcherReads {
        guard kitFloating else { return WatcherReads(items: false, questions: false) }
        var insideWindow = false
        if let windowOpenedAt {
            let age = now.timeIntervalSince(windowOpenedAt)
            insideWindow = age >= 0 && age < readWindowSeconds
        }
        var questionsDue = true
        if let lastQuestionCheck {
            questionsDue = now.timeIntervalSince(lastQuestionCheck) >= questionIntervalSeconds
        }
        return WatcherReads(items: needsBaseline || insideWindow, questions: questionsDue)
    }
}

extension Notification.Name {
    /// Posted when a recording stops or a route is written: the watcher should read items for a while.
    static let floatingReadWindowOpen = Notification.Name("PointrooFloatingReadWindowOpen")
}

/// Ticks once a second, only while the kit floating panels are in use (FloatingChoice), and watches for two things the panels must
/// show even when no window is open: a recording the app sent by itself ("Sent to X / Undo") and a new agent question.
/// What is read on each tick is chosen by WatcherSchedule: items only inside a 30 second read window, questions every 5 seconds.
/// The disk is read on a background queue; the decisions (WebEvents.routeSent, QuestionArrivals) run on the main actor.
/// While the setting is off nothing is read, and the next time it is on the first read starts again from nothing.
@MainActor
final class FloatingWatcher {
    private var webEvents = WebEvents()
    private var arrivals = QuestionArrivals()
    private var timer: Timer?
    private var isReading = false
    /// When the read window was last opened (nil if never). Readable so a test can see that the notification arrived.
    private(set) var windowOpenedAt: Date?
    private var lastQuestionCheck: Date?
    private var hasItemBaseline = false
    private var observer: NSObjectProtocol?
    private let onSent: ([String: Any]) -> Void
    private let onQuestion: () -> Void
    private let now: () -> Date
    private let usesTimer: Bool

    /// Tells the watcher to read items now, for the next 30 seconds. A second call restarts the 30 seconds.
    nonisolated static func openReadWindow() {
        NotificationCenter.default.post(name: .floatingReadWindowOpen, object: nil)
    }

    /// `onSent` gets the route.sent event data; `onQuestion` is called once for each look that finds a new question.
    /// `now` is the clock and `usesTimer` false skips the one second timer (so only the notification is watched); tests set both.
    init(onSent: @escaping ([String: Any]) -> Void, onQuestion: @escaping () -> Void,
         now: @escaping () -> Date = { Date() }, usesTimer: Bool = true) {
        self.onSent = onSent
        self.onQuestion = onQuestion
        self.now = now
        self.usesTimer = usesTimer
    }

    func start() {
        guard observer == nil else { return }
        if usesTimer {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.tick() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        observer = NotificationCenter.default.addObserver(forName: .floatingReadWindowOpen, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { self.windowOpenedAt = self.now() } }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    private func tick() {
        guard FloatingChoice.useKitNow else {
            webEvents = WebEvents()
            arrivals = QuestionArrivals()
            windowOpenedAt = nil
            lastQuestionCheck = nil
            hasItemBaseline = false
            return
        }
        guard !isReading else { return }
        let now = self.now()
        let reads = WatcherSchedule.reads(now: now, windowOpenedAt: windowOpenedAt, lastQuestionCheck: lastQuestionCheck,
                                          needsBaseline: !hasItemBaseline, kitFloating: true)
        guard reads.items || reads.questions else { return }
        if reads.questions { lastQuestionCheck = now }
        isReading = true
        Task.detached(priority: .utility) { [weak self] in
            let items: [Item]? = reads.items ? Items.all() : nil
            let questionIds: [String]? = reads.questions ? Questions.pending().map(\.id) : nil
            await self?.finishRead(items: items, questionIds: questionIds)
        }
    }

    private func finishRead(items: [Item]?, questionIds: [String]?) {
        isReading = false
        guard FloatingChoice.useKitNow else { return }
        if let items {
            hasItemBaseline = true
            for event in webEvents.routeSent(items, projectName: { Projects.name(for: $0) }) {
                onSent(event.data)
            }
        }
        if let questionIds, !arrivals.arrived(questionIds).isEmpty { onQuestion() }
    }
}
