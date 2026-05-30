import Foundation
import Combine
import SwiftUI
import WebKit

@MainActor
final class SyntaxAppModel: ObservableObject {
    @Published var selectedSidebarRoute: AppSidebarRoute = .dashboard
    @Published private(set) var currentPath: String = "/dashboard"
    @Published private(set) var pageTitle: String = "Syntax Sync"
    @Published private(set) var isLoading = false
    @Published private(set) var isLoggedIn = false
    @Published private(set) var lastError: String?
    @Published private(set) var dashboardSnapshot = DashboardSnapshot.empty
    @Published private(set) var modulesSnapshot = ModulesSnapshot.empty
    @Published private(set) var lessonSnapshot = LessonSnapshot.empty
    @Published private(set) var profileSnapshot = ProfileSnapshot.empty
    @Published var showWebInspector = true
    @Published var showLogs = false

    let webController: SyntaxWebController
    let logger: SyntaxLogger
    let stateStore: SyntaxStateStore

    private var hasStarted = false
    private var isApplyingWebState = false
    private var startupBackgroundSyncStarted = false
    private var startupBackgroundPaths: [String] = []
    private var persistedState: SyntaxPersistedState
    private var pendingBridgeAction: PendingBridgeAction?

    init() {
        self.logger = .shared
        self.stateStore = .shared
        self.persistedState = stateStore.load() ?? .empty
        self.webController = SyntaxWebController(logger: logger)
        logger.installRuntimeCaptureIfNeeded()
        if let loadError = stateStore.lastLoadError {
            logger.log(.error, "Persistierter Zustand konnte nicht geladen werden", metadata: ["message": loadError, "path": stateStore.fileURL.path()])
        }
        self.webController.onStateChange = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.apply(state: state)
            }
        }
        self.webController.onBackgroundStateSync = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.mergeBackground(state: state)
            }
        }
        restorePersistedState()
        logger.log(
            .system,
            "AppModel initialisiert",
            metadata: [
                "cachedLessons": "\(persistedState.lessonsByPath.count)",
                "cachePath": stateStore.fileURL.path()
            ]
        )
    }

    func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        let startupPath = preferredStartupPath()
        startupBackgroundPaths = preferredBackgroundRefreshPaths(excluding: startupPath)
        logger.log(.navigation, "Start der Synchronisation", metadata: ["target": startupPath])
        webController.navigate(path: startupPath)
    }

    func goToSelectedSidebarRoute() {
        switch selectedSidebarRoute {
        case .dashboard:
            webController.navigate(path: "/dashboard")
        case .modules:
            webController.navigate(path: "/dashboard/modules")
        case .learning:
            if lessonSnapshot.routePath.isEmpty {
                webController.navigate(path: "/dashboard/modules")
            } else {
                webController.navigate(path: lessonSnapshot.routePath)
            }
        case .profile:
            webController.navigate(path: "/dashboard/settings")
        }
    }

    func handleSidebarSelection(_ route: AppSidebarRoute) {
        logger.log(.navigation, "Sidebar-Auswahl", metadata: ["route": route.rawValue, "isApplyingWebState": "\(isApplyingWebState)"])
        guard selectedSidebarRoute != route else {
            goToSelectedSidebarRoute()
            return
        }
        selectedSidebarRoute = route
        guard !isApplyingWebState else { return }
        goToSelectedSidebarRoute()
    }

    func openRoute(_ path: String) {
        logger.log(.navigation, "Route oeffnen", metadata: ["path": path])
        webController.navigate(path: path)
    }

    func reload() {
        logger.log(.navigation, "WebView neu laden", metadata: ["path": currentPath])
        webController.reload()
    }

    func openExternalURL(_ value: String) {
        logger.log(.navigation, "Externe Route oeffnen", metadata: ["url": value])
        webController.openExternalURLString(value)
    }

    func triggerBridgeAction(_ actionID: String, sourcePath: String) {
        guard !actionID.isEmpty else { return }
        let normalizedSourcePath = sanitizedInternalPath(sourcePath) ?? currentPath
        logger.log(
            .navigation,
            "Bridge-Aktion angefordert",
            metadata: [
                "actionID": actionID,
                "sourcePath": normalizedSourcePath,
                "currentPath": currentPath
            ]
        )

        guard !isLoading, currentPath == normalizedSourcePath else {
            pendingBridgeAction = PendingBridgeAction(actionID: actionID, sourcePath: normalizedSourcePath)
            webController.navigate(path: normalizedSourcePath)
            return
        }

        webController.performBridgeAction(actionID: actionID)
    }

    func selectQuizOption(questionID: String, optionID: String) {
        logger.log(.web, "Quiz-Option ausgewaehlt", metadata: ["questionID": questionID, "optionID": optionID])
        webController.selectQuizOption(questionID: questionID, optionID: optionID)
    }

    func triggerLessonNavigation(forward: Bool) {
        logger.log(.navigation, "Lesson-Navigation", metadata: ["direction": forward ? "forward" : "backward", "path": currentPath])
        webController.triggerLessonNavigation(forward: forward)
    }

    private func apply(state: SyntaxWebState) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.absorb(state: state)
            let mergedState = self.mergedVisibleState(from: state)
            self.logger.log(
                .state,
                "Web-State anwenden",
                metadata: [
                    "currentPath": mergedState.currentPath,
                    "sidebarRoute": mergedState.sidebarRoute.rawValue,
                    "isLoading": "\(mergedState.isLoading)",
                    "isLoggedIn": "\(mergedState.isLoggedIn)"
                ]
            )
            self.isApplyingWebState = true
            self.currentPath = mergedState.currentPath
            self.pageTitle = mergedState.pageTitle
            self.isLoading = mergedState.isLoading
            self.isLoggedIn = mergedState.isLoggedIn
            self.lastError = mergedState.errorMessage
            self.dashboardSnapshot = mergedState.dashboard
            self.modulesSnapshot = mergedState.modules
            self.lessonSnapshot = mergedState.lesson
            self.profileSnapshot = mergedState.profile
            self.selectedSidebarRoute = mergedState.sidebarRoute
            self.isApplyingWebState = false

            self.persistCurrentState()

            if mergedState.isLoggedIn, !self.startupBackgroundSyncStarted {
                self.startupBackgroundSyncStarted = true
                self.webController.startBackgroundRefresh(paths: self.startupBackgroundPaths)
            }

            self.performPendingBridgeActionIfPossible(using: mergedState)
        }
    }

    private func mergeBackground(state: SyntaxWebState) {
        absorb(state: state)

        switch route(for: state.currentPath) {
        case .dashboard:
            dashboardSnapshot = persistedState.dashboard
        case .modules:
            modulesSnapshot = persistedState.modules
        case .learning:
            if state.currentPath == currentPath, let cachedLesson = persistedState.lessonsByPath[state.currentPath] {
                lessonSnapshot = cachedLesson
            }
        case .profile:
            profileSnapshot = persistedState.profile
        }

        persistCurrentState()
    }

    private func restorePersistedState() {
        let cachedCurrentPath = sanitizedInternalPath(persistedState.currentPath) ?? "/dashboard"
        currentPath = cachedCurrentPath
        pageTitle = persistedState.pageTitle
        isLoggedIn = persistedState.isLoggedIn
        dashboardSnapshot = persistedState.dashboard
        modulesSnapshot = persistedState.modules
        profileSnapshot = persistedState.profile
        selectedSidebarRoute = route(for: cachedCurrentPath)

        if let cachedLesson = persistedState.lessonsByPath[cachedCurrentPath] {
            lessonSnapshot = cachedLesson
        } else if let latestLearningPath = persistedState.latestLearningPath,
                  let cachedLesson = persistedState.lessonsByPath[latestLearningPath] {
            lessonSnapshot = cachedLesson
        }
    }

    private func absorb(state: SyntaxWebState) {
        if state.dashboard.hasContent {
            persistedState.dashboard = state.dashboard
        }

        let normalizedModules = normalizedModules(from: state.modules, dashboard: state.dashboard.hasContent ? state.dashboard : persistedState.dashboard)
        if normalizedModules.hasContent {
            persistedState.modules = normalizedModules
        }

        if state.profile.hasContent {
            persistedState.profile = state.profile
        }

        let statePath = sanitizedInternalPath(state.currentPath) ?? currentPath
        if route(for: statePath) == .learning {
            let lessonToStore = state.lesson.hasContent
                ? state.lesson
                : (state.lesson.routePath.isEmpty ? LessonSnapshot(routePath: statePath, breadcrumbs: [], title: "", subtitle: "", progressLabel: "", items: [], quiz: .empty) : state.lesson)

            if lessonToStore.hasContent {
                persistedState.storeLesson(lessonToStore, for: statePath)
            }
        }

        persistedState.currentPath = statePath
        persistedState.pageTitle = state.pageTitle
        persistedState.isLoggedIn = state.isLoggedIn
        persistedState.savedAt = Date()
    }

    private func mergedVisibleState(from state: SyntaxWebState) -> SyntaxWebState {
        var merged = state

        if !merged.dashboard.hasContent {
            merged.dashboard = persistedState.dashboard
        }

        merged.modules = normalizedModules(from: merged.modules, dashboard: merged.dashboard.hasContent ? merged.dashboard : persistedState.dashboard)
        if !merged.modules.hasContent {
            merged.modules = persistedState.modules
        }

        if !merged.profile.hasContent {
            merged.profile = persistedState.profile
        }

        let statePath = sanitizedInternalPath(merged.currentPath) ?? currentPath
        if route(for: statePath) == .learning {
            if let cachedLesson = persistedState.lessonsByPath[statePath] {
                if !merged.lesson.hasContent || merged.lesson.routePath != statePath {
                    merged.lesson = cachedLesson
                }
            } else if merged.lesson.routePath != statePath && !merged.lesson.hasContent {
                merged.lesson = .empty
            }
        }

        return merged
    }

    private func persistCurrentState() {
        persistedState.savedAt = Date()
        persistedState.currentPath = sanitizedInternalPath(currentPath) ?? "/dashboard"
        persistedState.pageTitle = pageTitle
        persistedState.isLoggedIn = isLoggedIn

        if dashboardSnapshot.hasContent {
            persistedState.dashboard = dashboardSnapshot
        }

        if modulesSnapshot.hasContent {
            persistedState.modules = modulesSnapshot
        }

        if profileSnapshot.hasContent {
            persistedState.profile = profileSnapshot
        }

        if route(for: currentPath) == .learning, lessonSnapshot.hasContent {
            persistedState.storeLesson(lessonSnapshot, for: currentPath)
        }

        if !stateStore.scheduleSave(persistedState) {
            let message = stateStore.lastSaveError ?? "Unbekannter Speicherfehler"
            lastError = "Gescrapte Daten konnten nicht gespeichert werden."
            logger.log(.error, "Persistierter Zustand konnte nicht gespeichert werden", metadata: ["message": message, "path": stateStore.fileURL.path()])
        }
    }

    private func preferredStartupPath() -> String {
        sanitizedInternalPath(persistedState.currentPath)
        ?? sanitizedInternalPath(persistedState.latestLearningPath)
        ?? "/dashboard"
    }

    private func normalizedModules(from modules: ModulesSnapshot, dashboard: DashboardSnapshot) -> ModulesSnapshot {
        guard !modules.modules.isEmpty else { return modules }

        var normalized = modules
        for index in normalized.modules.indices {
            let dashboardModule = dashboard.modules.indices.contains(index) ? dashboard.modules[index] : nil
            let title = normalized.modules[index].title.trimmingCharacters(in: .whitespacesAndNewlines)
            let isPlaceholderTitle = title.isEmpty || title == "ModulübersichtFortsetzen" || title == "ModulubersichtFortsetzen"

            if isPlaceholderTitle, let dashboardModule {
                normalized.modules[index].title = dashboardModule.title
            }

            if normalized.modules[index].subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let dashboardModule {
                normalized.modules[index].subtitle = dashboardModule.progressLabel
            }

            if normalized.modules[index].progressValue <= 0, let dashboardModule {
                normalized.modules[index].progressValue = dashboardModule.progressValue
            }

            if normalized.modules[index].routePath.isEmpty, let dashboardModule {
                normalized.modules[index].routePath = dashboardModule.routePath
            }
        }

        return normalized
    }

    private func preferredBackgroundRefreshPaths(excluding visiblePath: String) -> [String] {
        var paths = ["/dashboard", "/dashboard/modules", "/dashboard/settings"]

        if let currentPersistedPath = sanitizedInternalPath(persistedState.currentPath) {
            paths.append(currentPersistedPath)
        }

        paths.append(contentsOf: persistedState.recentLearningPaths.prefix(12).compactMap(sanitizedInternalPath))

        var uniquePaths: [String] = []
        for path in paths where path != visiblePath && !uniquePaths.contains(path) {
            uniquePaths.append(path)
        }
        return uniquePaths
    }

    private func performPendingBridgeActionIfPossible(using state: SyntaxWebState) {
        guard let pendingBridgeAction else { return }
        guard !state.isLoading else { return }

        let statePath = sanitizedInternalPath(state.currentPath) ?? state.currentPath
        guard statePath == pendingBridgeAction.sourcePath else { return }

        self.pendingBridgeAction = nil
        logger.log(
            .navigation,
            "Bridge-Aktion wird ausgefuehrt",
            metadata: [
                "actionID": pendingBridgeAction.actionID,
                "sourcePath": pendingBridgeAction.sourcePath
            ]
        )
        webController.performBridgeAction(actionID: pendingBridgeAction.actionID)
    }

    private func sanitizedInternalPath(_ path: String?) -> String? {
        guard let path, path.hasPrefix("/dashboard") else { return nil }
        return path
    }

    private func route(for path: String) -> AppSidebarRoute {
        if path.hasPrefix("/dashboard/settings") {
            return .profile
        }
        if path.contains("/lesson/") || path.contains("/lection/") {
            return .learning
        }
        if path.hasPrefix("/dashboard/modules") || path.hasPrefix("/dashboard/module/") {
            return .modules
        }
        return .dashboard
    }
}

private struct PendingBridgeAction {
    let actionID: String
    let sourcePath: String
}

enum AppSidebarRoute: String, CaseIterable, Hashable, Identifiable {
    case dashboard
    case modules
    case learning
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .modules: return "Module"
        case .learning: return "Lernen"
        case .profile: return "Profil"
        }
    }

    var symbolName: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .modules: return "rectangle.stack"
        case .learning: return "book.pages"
        case .profile: return "person.crop.circle"
        }
    }
}
