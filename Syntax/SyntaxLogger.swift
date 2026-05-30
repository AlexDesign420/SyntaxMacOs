import Foundation
import Combine

@MainActor
final class SyntaxLogger: ObservableObject {
    static let shared = SyntaxLogger()

    @Published private(set) var entries: [SyntaxLogEntry] = []

    let logFileURL: URL
    let fallbackLogFileURL: URL

    private let maxEntries = 400
    private let fileHandle: FileHandle?
    private var captureInstalled = false
    private var stderrPipe: Pipe?
    private var stdoutPipe: Pipe?

    private init() {
        let fileManager = FileManager.default
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Syntax", isDirectory: true)
        let fallbackDirectory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Syntax", isDirectory: true)
        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Syntax", isDirectory: true)
        let directory = supportDirectory ?? fallbackDirectory
        let fallbackFileDirectory = cachesDirectory ?? fallbackDirectory

        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: fallbackFileDirectory, withIntermediateDirectories: true)
        self.logFileURL = directory.appendingPathComponent("syntax-debug.log")
        self.fallbackLogFileURL = fallbackFileDirectory.appendingPathComponent("syntax-debug.log")

        if !fileManager.fileExists(atPath: logFileURL.path()) {
            fileManager.createFile(atPath: logFileURL.path(), contents: nil)
        }
        if !fileManager.fileExists(atPath: fallbackLogFileURL.path()) {
            fileManager.createFile(atPath: fallbackLogFileURL.path(), contents: nil)
        }

        self.fileHandle = try? FileHandle(forWritingTo: logFileURL)
        self.fileHandle?.seekToEndOfFile()

        log(.system, "Logger initialisiert", metadata: ["path": logFileURL.path(), "fallbackPath": fallbackLogFileURL.path()])
    }

    func installRuntimeCaptureIfNeeded() {
        guard !captureInstalled else { return }
        captureInstalled = true
        stderrPipe = Pipe()
        stdoutPipe = Pipe()

        if let stderrPipe {
            dup2(stderrPipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)
            stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                Task { @MainActor [weak self] in
                    self?.consumeRuntimeData(data, source: .stderr)
                }
            }
        }

        if let stdoutPipe {
            dup2(stdoutPipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
            stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                Task { @MainActor [weak self] in
                    self?.consumeRuntimeData(data, source: .stdout)
                }
            }
        }

        log(.system, "Runtime-Capture aktiviert")
    }

    func log(_ category: SyntaxLogCategory, _ message: String, metadata: [String: String] = [:]) {
        let entry = SyntaxLogEntry(
            timestamp: Date(),
            category: category,
            message: message,
            metadata: metadata
        )

        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }

        let line = entry.persistedLine + "\n"
        if let data = line.data(using: .utf8) {
            try? fileHandle?.write(contentsOf: data)
            appendFallbackLine(data)
        }
    }

    private func appendFallbackLine(_ data: Data) {
        if let fallbackHandle = try? FileHandle(forWritingTo: fallbackLogFileURL) {
            _ = try? fallbackHandle.seekToEnd()
            try? fallbackHandle.write(contentsOf: data)
            try? fallbackHandle.close()
        } else if let text = String(data: data, encoding: .utf8) {
            let existing = (try? String(contentsOf: fallbackLogFileURL, encoding: .utf8)) ?? ""
            try? (existing + text).write(to: fallbackLogFileURL, atomically: true, encoding: .utf8)
        }
    }

    private func consumeRuntimeData(_ data: Data, source: SyntaxLogCategory) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !shouldIgnoreRuntimeLogLine($0) }
            .forEach { line in
                log(source, line)
            }
    }

    private func shouldIgnoreRuntimeLogLine(_ line: String) -> Bool {
        let ignoredFragments = [
            "GetSafeBrowsingEnabledState response with error: Connection invalid",
            "GetDatabases response with error: Connection invalid",
            "Encountered error when trying to get databases: Connection invalid",
            "makeImagePlus:3799: *** ERROR: 'WEBP'-_reader->initImage[0] failed err=-50",
            "WebPageProxy::didFailProvisionalLoadForFrame",
            "NSURLErrorDomain, code=-999",
            "SOAuthorizationCoordinator::tryAuthorize (2): Attempting to perform subframe navigation.",
            "containerToPush is nil, will not push anything to candidate receiver"
        ]

        return ignoredFragments.contains { line.contains($0) }
    }
}

struct SyntaxLogEntry: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let category: SyntaxLogCategory
    let message: String
    let metadata: [String: String]

    var persistedLine: String {
        let formatter = ISO8601DateFormatter()
        let meta = metadata.isEmpty
            ? ""
            : " " + metadata
                .sorted(by: { $0.key < $1.key })
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " ")
        return "[\(formatter.string(from: timestamp))] [\(category.rawValue)] \(message)\(meta)"
    }
}

enum SyntaxLogCategory: String {
    case system = "system"
    case state = "state"
    case navigation = "navigation"
    case web = "web"
    case error = "error"
    case stdout = "stdout"
    case stderr = "stderr"
}
