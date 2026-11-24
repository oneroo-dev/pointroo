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

/// Watches, once a second and only while the kit floating panels are in use (FloatingChoice), for two things the panels must show
/// even when no window is open: a recording the app sent by itself ("Sent to X / Undo") and a new agent question.
/// The disk is read on a background queue; the decisions (WebEvents.routeSent, QuestionArrivals) run on the main actor.
/// While the setting is off nothing is read, and the next time it is on the first read starts again from nothing.
@MainActor
final class FloatingWatcher {
    private var webEvents = WebEvents()
    private var arrivals = QuestionArrivals()
    private var timer: Timer?
    private var isReading = false
    private let onSent: ([String: Any]) -> Void
    private let onQuestion: () -> Void

    /// `onSent` gets the route.sent event data; `onQuestion` is called once for each look that finds a new question.
    init(onSent: @escaping ([String: Any]) -> Void, onQuestion: @escaping () -> Void) {
        self.onSent = onSent
        self.onQuestion = onQuestion
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard FloatingChoice.useKitNow else {
            webEvents = WebEvents()
            arrivals = QuestionArrivals()
            return
        }
        guard !isReading else { return }
        isReading = true
        Task.detached(priority: .utility) { [weak self] in
            let items = Items.all()
            let questionIds = Questions.pending().map(\.id)
            await self?.finishRead(items: items, questionIds: questionIds)
        }
    }

    private func finishRead(items: [Item], questionIds: [String]) {
        isReading = false
        guard FloatingChoice.useKitNow else { return }
        for event in webEvents.routeSent(items, projectName: { Projects.name(for: $0) }) {
            onSent(event.data)
        }
        if !arrivals.arrived(questionIds).isEmpty { onQuestion() }
    }
}
