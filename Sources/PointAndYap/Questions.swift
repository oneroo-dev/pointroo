import Foundation

/// A question an agent asked the user through the ask_user tool.
struct Question: Codable, Equatable {
    var id: String
    /// The project's name, for the user to read.
    var project: String
    /// The agent's folder: only a connection in the same folder can read the answer back.
    var cwd: String
    var agent: String
    var text: String
    var choices: [String]
    var asked: Date
    var answer: String?
    var answered: Date?
    /// Set by "later": the question stays out of the pending list until this time. Files written before this existed have none.
    var snoozedUntil: Date? = nil
}

/// The questions folder is the only link between the app (which will show them) and whichever process runs the tool.
/// One JSON file per question in `Paths.support/questions/<id>.json`; the id is a UUID, so it is safe as a file name.
enum Questions {
    static var folder: URL { Paths.support.appendingPathComponent("questions") }

    /// How often ask_user looks for the answer. Tests lower it.
    nonisolated(unsafe) static var pollInterval: TimeInterval = 1

    /// The id as a canonical UUID, or nil. A name like `../x` never gets through.
    static func validID(_ raw: String) -> String? { UUID(uuidString: raw)?.uuidString }

    static func url(for id: String) -> URL { folder.appendingPathComponent("\(id).json") }

    @discardableResult
    static func ask(project: String, cwd: String, agent: String, text: String, choices: [String], now: Date = Date()) -> Question {
        let question = Question(id: UUID().uuidString, project: project, cwd: cwd, agent: agent, text: text,
                                choices: Array(choices.prefix(4)), asked: now, answer: nil, answered: nil)
        write(question)
        return question
    }

    /// Stores the user's answer. False when the question is gone or already answered.
    @discardableResult
    static func answer(id: String, text: String, now: Date = Date()) -> Bool {
        guard let valid = validID(id) else { return false }
        return Items.locked {
            guard var question = read(valid), question.answer == nil else { return false }
            question.answer = text
            question.answered = now
            return writeUnlocked(question)
        }
    }

    static func get(id: String) -> Question? {
        guard let valid = validID(id) else { return nil }
        return read(valid)
    }

    /// Hides an unanswered question for `minutes` from `now`. False when the question is gone or already answered.
    @discardableResult
    static func snooze(id: String, minutes: Int, now: Date = Date()) -> Bool {
        guard let valid = validID(id) else { return false }
        return Items.locked {
            guard var question = read(valid), question.answer == nil else { return false }
            question.snoozedUntil = now.addingTimeInterval(TimeInterval(minutes) * 60)
            return writeUnlocked(question)
        }
    }

    /// Unanswered questions that are not snoozed at `now`, oldest first.
    static func pending(now: Date = Date()) -> [Question] {
        all().filter { question in
            guard question.answer == nil else { return false }
            guard let until = question.snoozedUntil else { return true }
            return until <= now
        }.sorted { $0.asked < $1.asked }
    }

    static func remove(id: String) {
        guard let valid = validID(id) else { return }
        try? FileManager.default.removeItem(at: url(for: valid))
    }

    /// Deletes questions answered or asked more than `age` seconds ago (a day by default).
    static func cleanup(now: Date = Date(), age: TimeInterval = 24 * 3600) {
        for question in all() {
            let last = question.answered ?? question.asked
            if now.timeIntervalSince(last) > age { remove(id: question.id) }
        }
    }

    private static func all() -> [Question] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { file in
            (try? Data(contentsOf: file)).flatMap { try? JSONDecoder.iso.decode(Question.self, from: $0) }
        }
    }

    private static func read(_ id: String) -> Question? {
        (try? Data(contentsOf: url(for: id))).flatMap { try? JSONDecoder.iso.decode(Question.self, from: $0) }
    }

    private static func write(_ question: Question) {
        _ = Items.locked { writeUnlocked(question) }
    }

    private static func writeUnlocked(_ question: Question) -> Bool {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONEncoder.pretty.encode(question).write(to: url(for: question.id), options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

/// The app touches `Paths.support/app-heartbeat` every 2 s. The file is one line of JSON:
/// `{"questions":false,"time":1764000000.5}` where `time` is Unix seconds and `questions` says the app can show questions.
/// A tool running in another process (the stdio bridge answering by itself) reads it to know whether anyone can see a question.
enum Heartbeat {
    static var file: URL { Paths.support.appendingPathComponent("app-heartbeat") }
    static let interval: TimeInterval = 2
    static let staleAfter: TimeInterval = 6

    struct Reading: Equatable {
        var time: Date
        var questions: Bool
    }

    static func write(now: Date = Date(), questions: Bool) {
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        let object: [String: Any] = ["questions": questions, "time": now.timeIntervalSince1970]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
        try? data.write(to: file, options: .atomic)
    }

    static func read() -> Reading? {
        guard let data = try? Data(contentsOf: file),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let seconds = object["time"] as? Double else { return nil }
        return Reading(time: Date(timeIntervalSince1970: seconds), questions: object["questions"] as? Bool ?? false)
    }

    /// The app is running when the heartbeat is no older than `staleAfter`.
    static func isFresh(now: Date = Date()) -> Bool {
        guard let reading = read() else { return false }
        return now.timeIntervalSince(reading.time) <= staleAfter
    }

    /// Cleans old questions, writes the first beat at once and then one every 2 s. Called once at launch.
    /// `questions` stays false until a panel exists that can show them.
    /// The timer runs in the common run loop modes, so an open menu or a window drag does not pause it.
    @discardableResult
    static func start(questions: Bool = false) -> Timer {
        Questions.cleanup()
        write(questions: questions)
        let timer = Timer(timeInterval: interval, repeats: true) { _ in write(questions: questions) }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}

extension MCPConnection {
    static let notRunningText = "Pointroo is not running, so I can't show your question. Ask in chat."
    static let noPanelText = "Pointroo can't show your question yet. Ask in chat."

    /// The ask_user tool: asks the user, waits for the answer, or only waits for an earlier question (`question_id`).
    func askUser(_ a: [String: Any]) -> [String: Any] {
        let seconds = (a["timeout_seconds"] as? Int) ?? (a["timeout_seconds"] as? Double).map { Int($0) } ?? MCPServer.defaultWait
        let timeout = MCPServer.waitTimeout(seconds)

        if let raw = a["question_id"] as? String, !raw.isEmpty {
            guard let id = Questions.validID(raw) else { return MCPServer.error("question_id is not valid") }
            guard let existing = Questions.get(id: id), existing.cwd == cwd else {
                return MCPServer.text("There is no question with that id. It may have expired. Ask again if you still need an answer.")
            }
            return waitForAnswer(existing, timeout: timeout)
        }

        guard let text = (a["question"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return MCPServer.error("question missing")
        }
        guard let beat = Heartbeat.read(), Heartbeat.isFresh() else { return MCPServer.text(Self.notRunningText) }
        guard beat.questions else { return MCPServer.text(Self.noPanelText) }
        let choices = ((a["choices"] as? [Any]) ?? []).compactMap { $0 as? String }.filter { !$0.isEmpty }
        let question = Questions.ask(project: Projects.name(for: cwd), cwd: cwd, agent: agent, text: text, choices: choices)
        return waitForAnswer(question, timeout: timeout)
    }

    private func waitForAnswer(_ question: Question, timeout: Int) -> [String: Any] {
        let deadline = Date().addingTimeInterval(TimeInterval(timeout))
        while true {
            if let current = Questions.get(id: question.id), let answer = current.answer {
                return MCPServer.text("The user answered: \"\(answer)\"")
            }
            guard isOpen() else {
                Questions.remove(id: question.id)
                return MCPServer.text("The connection is closed.")
            }
            if !Heartbeat.isFresh() {
                Questions.remove(id: question.id)
                return MCPServer.text(Self.notRunningText)
            }
            if Date() >= deadline { break }
            Thread.sleep(forTimeInterval: Questions.pollInterval)
        }
        return MCPServer.text("No answer yet (question \(question.id)). Carry on with other work and call ask_user again with question_id \"\(question.id)\" to check.")
    }
}
