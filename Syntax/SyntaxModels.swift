import Foundation

struct DashboardSnapshot: Equatable, Codable {
    var greeting = ""
    var userName = ""
    var liveClassTitle = ""
    var liveClassDescription = ""
    var liveClassAction = ""
    var liveClassPath = ""
    var liveClassExternalURL = ""
    var liveClassActionID = ""
    var currentModuleTitle = ""
    var currentLessonTitle = ""
    var currentLessonDescription = ""
    var currentLessonPath = ""
    var currentLessonActionID = ""
    var modules: [ModuleCard] = []

    static let empty = DashboardSnapshot()

    var hasContent: Bool {
        !greeting.isBlank
        || !userName.isBlank
        || !liveClassTitle.isBlank
        || !currentLessonTitle.isBlank
        || !modules.isEmpty
    }
}

struct ModulesSnapshot: Equatable, Codable {
    var modules: [ModuleProgress] = []

    static let empty = ModulesSnapshot()

    var hasContent: Bool {
        !modules.isEmpty
    }
}

struct ModuleProgress: Equatable, Identifiable, Codable {
    let id: String
    var title: String
    var subtitle: String
    var progressValue: Double
    var routePath: String
    var routeActionID: String
    var continuePath: String
    var continueActionID: String
}

struct ModuleCard: Equatable, Identifiable, Codable {
    let id: String
    var title: String
    var progressLabel: String
    var progressValue: Double
    var routePath: String
    var actionID: String
}

struct LessonSnapshot: Equatable, Codable {
    var routePath = ""
    var breadcrumbs: [String] = []
    var title = ""
    var subtitle = ""
    var progressLabel = ""
    var items: [LessonItem] = []
    var quiz = QuizSnapshot.empty

    static let empty = LessonSnapshot()

    var hasContent: Bool {
        !routePath.isBlank
        || !title.isBlank
        || !subtitle.isBlank
        || !items.isEmpty
        || quiz.hasContent
    }
}

struct LessonItem: Equatable, Identifiable, Codable {
    let id: String
    var title: String
    var subtitle: String
    var statusLabel: String
    var routePath: String
    var actionID: String
}

struct ProfileSnapshot: Equatable, Codable {
    var firstName = ""
    var lastName = ""
    var birthDate = ""
    var gender = ""
    var email = ""
    var phone = ""

    static let empty = ProfileSnapshot()

    var hasContent: Bool {
        !firstName.isBlank
        || !lastName.isBlank
        || !birthDate.isBlank
        || !gender.isBlank
        || !email.isBlank
        || !phone.isBlank
    }
}

struct QuizSnapshot: Equatable, Codable {
    var title = ""
    var modeLabel = ""
    var routePath = ""
    var progressLabel = ""
    var questions: [QuizQuestion] = []
    var canGoBack = false
    var canGoForward = false

    static let empty = QuizSnapshot()

    var isAvailable: Bool {
        !questions.isEmpty
    }

    var hasContent: Bool {
        !title.isBlank || !progressLabel.isBlank || isAvailable
    }
}

struct QuizQuestion: Equatable, Identifiable, Codable {
    let id: String
    var prompt: String
    var hint: String
    var positionLabel: String
    var options: [QuizOption]
}

struct QuizOption: Equatable, Identifiable, Codable {
    let id: String
    var title: String
    var isSelected: Bool
}

struct SyntaxWebState: Equatable {
    var currentPath = "/dashboard"
    var pageTitle = "Syntax Sync"
    var isLoading = false
    var isLoggedIn = false
    var errorMessage: String?
    var dashboard = DashboardSnapshot.empty
    var modules = ModulesSnapshot.empty
    var lesson = LessonSnapshot.empty
    var profile = ProfileSnapshot.empty

    var sidebarRoute: AppSidebarRoute {
        if currentPath.hasPrefix("/dashboard/settings") {
            return .profile
        }
        if currentPath.contains("/lesson/") || currentPath.contains("/lection/") {
            return .learning
        }
        if currentPath.hasPrefix("/dashboard/modules") || currentPath.hasPrefix("/dashboard/module/") {
            return .modules
        }
        return .dashboard
    }
}

private extension String {
    var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private extension KeyedDecodingContainer {
    func decodeStringIfPresent(_ key: Key) throws -> String {
        try decodeIfPresent(String.self, forKey: key) ?? ""
    }

    func decodeDoubleIfPresent(_ key: Key) throws -> Double {
        try decodeIfPresent(Double.self, forKey: key) ?? 0
    }
}

extension DashboardSnapshot {
    private enum CodingKeys: String, CodingKey {
        case greeting
        case userName
        case liveClassTitle
        case liveClassDescription
        case liveClassAction
        case liveClassPath
        case liveClassExternalURL
        case liveClassActionID
        case currentModuleTitle
        case currentLessonTitle
        case currentLessonDescription
        case currentLessonPath
        case currentLessonActionID
        case modules
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        greeting = try container.decodeStringIfPresent(.greeting)
        userName = try container.decodeStringIfPresent(.userName)
        liveClassTitle = try container.decodeStringIfPresent(.liveClassTitle)
        liveClassDescription = try container.decodeStringIfPresent(.liveClassDescription)
        liveClassAction = try container.decodeStringIfPresent(.liveClassAction)
        liveClassPath = try container.decodeStringIfPresent(.liveClassPath)
        liveClassExternalURL = try container.decodeStringIfPresent(.liveClassExternalURL)
        liveClassActionID = try container.decodeStringIfPresent(.liveClassActionID)
        currentModuleTitle = try container.decodeStringIfPresent(.currentModuleTitle)
        currentLessonTitle = try container.decodeStringIfPresent(.currentLessonTitle)
        currentLessonDescription = try container.decodeStringIfPresent(.currentLessonDescription)
        currentLessonPath = try container.decodeStringIfPresent(.currentLessonPath)
        currentLessonActionID = try container.decodeStringIfPresent(.currentLessonActionID)
        modules = try container.decodeIfPresent([ModuleCard].self, forKey: .modules) ?? []
    }
}

extension ModuleProgress {
    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case subtitle
        case progressValue
        case routePath
        case routeActionID
        case continuePath
        case continueActionID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeStringIfPresent(.id)
        title = try container.decodeStringIfPresent(.title)
        subtitle = try container.decodeStringIfPresent(.subtitle)
        progressValue = try container.decodeDoubleIfPresent(.progressValue)
        routePath = try container.decodeStringIfPresent(.routePath)
        routeActionID = try container.decodeStringIfPresent(.routeActionID)
        continuePath = try container.decodeStringIfPresent(.continuePath)
        continueActionID = try container.decodeStringIfPresent(.continueActionID)
    }
}

extension ModuleCard {
    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case progressLabel
        case progressValue
        case routePath
        case actionID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeStringIfPresent(.id)
        title = try container.decodeStringIfPresent(.title)
        progressLabel = try container.decodeStringIfPresent(.progressLabel)
        progressValue = try container.decodeDoubleIfPresent(.progressValue)
        routePath = try container.decodeStringIfPresent(.routePath)
        actionID = try container.decodeStringIfPresent(.actionID)
    }
}

extension LessonItem {
    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case subtitle
        case statusLabel
        case routePath
        case actionID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeStringIfPresent(.id)
        title = try container.decodeStringIfPresent(.title)
        subtitle = try container.decodeStringIfPresent(.subtitle)
        statusLabel = try container.decodeStringIfPresent(.statusLabel)
        routePath = try container.decodeStringIfPresent(.routePath)
        actionID = try container.decodeStringIfPresent(.actionID)
    }
}
