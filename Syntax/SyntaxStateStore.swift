import Foundation

struct SyntaxPersistedState: Codable {
    var savedAt = Date()
    var currentPath = "/dashboard"
    var pageTitle = "Syntax Sync"
    var isLoggedIn = false
    var dashboard = DashboardSnapshot.empty
    var modules = ModulesSnapshot.empty
    var profile = ProfileSnapshot.empty
    var lessonsByPath: [String: LessonSnapshot] = [:]
    var recentLearningPaths: [String] = []

    static let empty = SyntaxPersistedState()

    var latestLearningPath: String? {
        recentLearningPaths.first
    }

    mutating func storeLesson(_ lesson: LessonSnapshot, for path: String) {
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        lessonsByPath[path] = lesson
        recentLearningPaths.removeAll { $0 == path }
        recentLearningPaths.insert(path, at: 0)
        trimStoredLessons()
    }

    mutating func trimStoredLessons(maxCount: Int = 120) {
        guard recentLearningPaths.count > maxCount else { return }
        let overflowPaths = Array(recentLearningPaths.dropFirst(maxCount))
        recentLearningPaths = Array(recentLearningPaths.prefix(maxCount))
        overflowPaths.forEach { lessonsByPath.removeValue(forKey: $0) }
    }
}

@MainActor
final class SyntaxStateStore {
    static let shared = SyntaxStateStore()

    let fileURL: URL
    private(set) var lastLoadError: String?
    private(set) var lastSaveError: String?

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        let fileManager = FileManager.default
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Syntax", isDirectory: true)
        let fallbackDirectory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Syntax", isDirectory: true)
        let directory = supportDirectory ?? fallbackDirectory

        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("syntax-state.json")
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() -> SyntaxPersistedState? {
        lastLoadError = nil

        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode(SyntaxPersistedState.self, from: data)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        } catch {
            lastLoadError = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func scheduleSave(_ state: SyntaxPersistedState) -> Bool {
        saveNow(state)
    }

    @discardableResult
    private func saveNow(_ state: SyntaxPersistedState) -> Bool {
        lastSaveError = nil

        do {
            let data = try encoder.encode(state)
            try data.write(to: fileURL, options: [.atomic])
            return true
        } catch {
            lastSaveError = error.localizedDescription
            return false
        }
    }
}
