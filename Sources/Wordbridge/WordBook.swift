import AppKit
import SwiftUI
import UserNotifications

/// A word or phrase you saved, with when to practice it next.
struct SavedWord: Codable, Identifiable, Hashable {
    var id = UUID()
    var term: String
    var meaning: String
    /// The sentence it came from, if any.
    var context: String?
    var added = Date()
    /// Spaced repetition (Leitner boxes): the higher the box, the longer until the next review.
    var box = 0
    var due = Date()
    var reviews = 0
}

/// Your personal dictionary, saved as JSON in Application Support.
@MainActor
final class WordBook: ObservableObject {
    static let shared = WordBook()

    @Published private(set) var words: [SavedWord] = []

    /// Days until the next review, per box.
    private static let intervals: [Double] = [1, 2, 4, 8, 16, 32, 64]

    private var fileURL: URL { ModelLocator.appSupportFolder.appendingPathComponent("words.json") }

    private init() {
        if let data = try? Data(contentsOf: fileURL),
           let words = try? JSONDecoder.iso.decode([SavedWord].self, from: data) {
            self.words = words
        }
    }

    var dueWords: [SavedWord] { words.filter { $0.due <= Date() }.sorted { $0.due < $1.due } }

    func contains(_ term: String) -> Bool {
        let key = Self.key(term)
        return words.contains { Self.key($0.term) == key }
    }

    func add(term: String, meaning: String, context: String?) {
        let term = term.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !term.isEmpty, !contains(term) else { return }
        words.append(SavedWord(term: term, meaning: meaning.trimmingCharacters(in: .whitespacesAndNewlines), context: context))
        save()
        PracticeReminder.enableIfFirstWord()
    }

    func remove(term: String) {
        let key = Self.key(term)
        words.removeAll { Self.key($0.term) == key }
        save()
    }

    func remove(_ word: SavedWord) {
        words.removeAll { $0.id == word.id }
        save()
    }

    enum Answer { case again, hard, good }

    func review(_ word: SavedWord, _ answer: Answer) {
        guard let i = words.firstIndex(where: { $0.id == word.id }) else { return }
        var word = words[i]
        word.reviews += 1
        switch answer {
        case .again:
            word.box = 0
            word.due = Date().addingTimeInterval(10 * 60) // again later today
        case .hard:
            word.due = Date().addingTimeInterval(max(1, Self.intervals[word.box] / 2) * 86_400)
        case .good:
            word.due = Date().addingTimeInterval(Self.intervals[word.box] * 86_400)
            word.box = min(word.box + 1, Self.intervals.count - 1)
        }
        words[i] = word
        save()
    }

    private func save() {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder.iso.encode(words) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private static func key(_ term: String) -> String {
        term.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }
}

private extension JSONEncoder {
    static let iso: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        return encoder
    }()
}

private extension JSONDecoder {
    static let iso: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// A bookmark button that saves a word to your dictionary (or removes it again).
struct SaveWordButton: View {
    let term: String
    let meaning: String
    let context: String?
    var label: String?
    @ObservedObject private var book = WordBook.shared

    var body: some View {
        let saved = book.contains(term)
        Button {
            if saved { book.remove(term: term) } else { book.add(term: term, meaning: meaning, context: context) }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: saved ? "bookmark.fill" : "bookmark")
                if let label { Text(saved ? "Saved" : label) }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(saved ? Color.accentColor : Color.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(saved ? "Remove from My Words" : "Save to My Words for practice")
    }
}

// MARK: - Daily reminder

/// One local notification a day to practice, turned on with the first saved word.
@MainActor
enum PracticeReminder {
    static let enabledKey = "practiceReminder"
    static let hourKey = "practiceReminderHour"
    private static let identifier = "io.github.wordbridge.practice"

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? false }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            reschedule()
        }
    }

    static var hour: Int {
        get { UserDefaults.standard.object(forKey: hourKey) as? Int ?? 10 }
        set {
            UserDefaults.standard.set(newValue, forKey: hourKey)
            reschedule()
        }
    }

    static func enableIfFirstWord() {
        guard UserDefaults.standard.object(forKey: enabledKey) == nil else { return }
        isEnabled = true
    }

    static func reschedule() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard isEnabled else { return }
        let hour = hour
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Time to practice English"
            content.body = "A few of your saved words are waiting — it takes two minutes."
            var time = DateComponents()
            time.hour = hour
            let trigger = UNCalendarNotificationTrigger(dateMatching: time, repeats: true)
            center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }
    }
}

// MARK: - Practice window

@MainActor
final class PracticeModel: ObservableObject {
    enum Tab { case practice, words }
    @Published var tab: Tab = .practice
    @Published var current: SavedWord?
    @Published var revealed = false
    @Published var search = ""
    @Published private(set) var doneThisSession = 0

    func next() {
        revealed = false
        current = WordBook.shared.dueWords.first
    }

    func answer(_ answer: WordBook.Answer) {
        guard let current else { return }
        WordBook.shared.review(current, answer)
        doneThisSession += 1
        next()
    }
}

struct PracticeView: View {
    @ObservedObject var model: PracticeModel
    @ObservedObject var book = WordBook.shared

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $model.tab) {
                Text("Practice (\(book.dueWords.count))").tag(PracticeModel.Tab.practice)
                Text("My Words (\(book.words.count))").tag(PracticeModel.Tab.words)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.top, 14)
            .padding(.bottom, 10)
            Divider()
            switch model.tab {
            case .practice: practice
            case .words: list
            }
        }
        .frame(minWidth: 440, minHeight: 380)
        .environment(\.layoutDirection, .leftToRight)
    }

    // MARK: Practice

    @ViewBuilder
    private var practice: some View {
        if let word = model.current {
            VStack(spacing: 18) {
                Spacer(minLength: 10)
                Text(word.term)
                    .font(.system(size: 30, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                if let context = word.context, !context.isBlank, context != word.term {
                    DirectionalText(string: "“\(context)”", language: AppLanguage.direction(for: context).source)
                        .font(.callout)
                        .italic()
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                }
                if model.revealed {
                    DirectionalText(string: word.meaning, language: word.meaning.containsHebrew ? .hebrew : .english)
                        .font(.title2.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                    HStack(spacing: 10) {
                        answerButton("Again", key: "1", color: .red) { model.answer(.again) }
                        answerButton("Hard", key: "2", color: .orange) { model.answer(.hard) }
                        answerButton("Got it", key: "3", color: .green) { model.answer(.good) }
                    }
                } else {
                    Button("Show Meaning") { model.revealed = true }
                        .keyboardShortcut(.space, modifiers: [])
                        .controlSize(.large)
                    Text("Try to remember what it means first.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 10)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 10) {
                Image(systemName: book.words.isEmpty ? "bookmark" : "checkmark.seal.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(book.words.isEmpty ? Color.secondary : Color.green)
                Text(book.words.isEmpty ? "No saved words yet" : "All done for now")
                    .font(.title3.weight(.semibold))
                Text(book.words.isEmpty
                     ? "Save words with the bookmark button in word by word, translations and “How do I say…”."
                     : nextReviewText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { model.next() }
        }
    }

    private var nextReviewText: String {
        let reviewed = model.doneThisSession > 0 ? "You reviewed \(model.doneThisSession) words. " : ""
        guard let next = book.words.map(\.due).min() else { return reviewed }
        return reviewed + "Next review " + next.formatted(.relative(presentation: .named)) + "."
    }

    private func answerButton(_ title: String, key: KeyEquivalent, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).frame(minWidth: 70)
        }
        .controlSize(.large)
        .tint(color)
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(key, modifiers: [])
    }

    // MARK: List

    private var list: some View {
        VStack(spacing: 0) {
            TextField("Search", text: $model.search)
                .textFieldStyle(.roundedBorder)
                .padding(10)
            List {
                ForEach(filtered) { word in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(word.term).font(.body.weight(.medium))
                            DirectionalText(string: word.meaning, language: word.meaning.containsHebrew ? .hebrew : .english)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(word.due <= Date() ? "due" : word.due.formatted(.relative(presentation: .named)))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Button {
                            book.remove(word)
                        } label: {
                            Image(systemName: "trash").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove")
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var filtered: [SavedWord] {
        let query = model.search.trimmingCharacters(in: .whitespaces).lowercased()
        let sorted = book.words.sorted { $0.added > $1.added }
        guard !query.isEmpty else { return sorted }
        return sorted.filter { $0.term.lowercased().contains(query) || $0.meaning.lowercased().contains(query) }
    }
}

@MainActor
final class PracticeWindowController {
    private var window: NSWindow?
    private let model = PracticeModel()

    func show() {
        model.tab = .practice
        model.next()
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: PracticeView(model: model)))
            window.title = "Practice English"
            window.styleMask = [.titled, .closable, .resizable]
            window.setContentSize(NSSize(width: 480, height: 420))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
