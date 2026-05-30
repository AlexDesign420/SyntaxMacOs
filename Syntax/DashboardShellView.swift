import SwiftUI

struct DashboardShellView: View {
    @EnvironmentObject private var appModel: SyntaxAppModel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.09, blue: 0.26), Color(red: 0.91, green: 0.93, blue: 0.98)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            HStack(spacing: 20) {
                NativeSurfaceView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if appModel.showWebInspector {
                    WebInspectorPanel()
                        .frame(width: 380)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }

                if appModel.showLogs {
                    LogPanel()
                        .frame(width: 420)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(20)
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    appModel.goToSelectedSidebarRoute()
                } label: {
                    Label("Zur Seite", systemImage: "arrow.triangle.branch")
                }

                Button {
                    appModel.reload()
                } label: {
                    Label("Neu laden", systemImage: "arrow.clockwise")
                }

                Toggle(isOn: $appModel.showWebInspector) {
                    Label("Web", systemImage: "macwindow.on.rectangle")
                }
                .toggleStyle(.button)

                Toggle(isOn: $appModel.showLogs) {
                    Label("Logs", systemImage: "text.append")
                }
                .toggleStyle(.button)
            }
        }
    }
}

private struct NativeSurfaceView: View {
    @EnvironmentObject private var appModel: SyntaxAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HeroHeader(
                    title: appModel.dashboardSnapshot.greeting.isEmpty ? "Syntax Sync" : appModel.dashboardSnapshot.greeting,
                    subtitle: appModel.isLoggedIn
                        ? "Dein eigenes App-Layout bleibt mit der Originalseite verbunden."
                        : "Logg dich im rechten Web-Panel ein. Danach lesen wir die echten Inhalte live aus."
                )

                if let lastError = appModel.lastError {
                    ErrorBanner(message: lastError)
                }

                switch appModel.selectedSidebarRoute {
                case .dashboard:
                    DashboardOverview(
                        snapshot: appModel.dashboardSnapshot,
                        onOpen: appModel.openRoute,
                        onOpenExternal: appModel.openExternalURL,
                        onTriggerAction: appModel.triggerBridgeAction
                    )
                case .modules:
                    ModulesOverview(
                        snapshot: appModel.modulesSnapshot,
                        onOpen: appModel.openRoute,
                        onTriggerAction: appModel.triggerBridgeAction
                    )
                case .learning:
                    LearningOverview(
                        snapshot: appModel.lessonSnapshot,
                        onOpen: appModel.openRoute,
                        onTriggerAction: appModel.triggerBridgeAction,
                        onSelectQuizOption: appModel.selectQuizOption,
                        onNavigateLesson: appModel.triggerLessonNavigation
                    )
                case .profile:
                    ProfileOverview(snapshot: appModel.profileSnapshot)
                }
            }
            .padding(28)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(alignment: .topTrailing) {
            StatusChip(
                title: appModel.isLoading ? "Synchronisiert..." : "Live verbunden",
                symbol: appModel.isLoading ? "arrow.triangle.2.circlepath" : "bolt.horizontal.circle"
            )
            .padding(22)
        }
    }
}

private struct WebInspectorPanel: View {
    @EnvironmentObject private var appModel: SyntaxAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Image("BrandMark")
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Originalseite")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        Text("Syntax Sync Web Core")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(SurfacePalette.darkSecondaryText)
                    }
                }
                Text(appModel.currentPath)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(SurfacePalette.darkSecondaryText)
                    .textSelection(.enabled)
            }

            WebViewContainer(webView: appModel.webController.webView)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
        }
        .padding(18)
        .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

private struct LogPanel: View {
    @EnvironmentObject private var appModel: SyntaxAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image("BrandMark")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text("Runtime-Logs")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
            }

            Text(appModel.logger.logFileURL.path())
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(SurfacePalette.darkSecondaryText)
                .textSelection(.enabled)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(appModel.logger.entries.reversed()) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.category.rawValue.uppercased())
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(logColor(for: entry.category))
                            Text(entry.message)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            if !entry.metadata.isEmpty {
                                Text(
                                    entry.metadata
                                        .sorted(by: { $0.key < $1.key })
                                        .map { "\($0.key)=\($0.value)" }
                                        .joined(separator: " ")
                                )
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundStyle(SurfacePalette.secondaryText)
                                .textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        }
        .padding(18)
        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func logColor(for category: SyntaxLogCategory) -> Color {
        switch category {
        case .system: return .blue
        case .state: return .teal
        case .navigation: return .indigo
        case .web: return .purple
        case .error, .stderr: return .red
        case .stdout: return .orange
        }
    }
}

private struct DashboardOverview: View {
    let snapshot: DashboardSnapshot
    let onOpen: (String) -> Void
    let onOpenExternal: (String) -> Void
    let onTriggerAction: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionTitle(title: "Heute", subtitle: "Deine wichtigsten Bereiche in einem neuen, nativen Aufbau.")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                FocusCard(
                    eyebrow: snapshot.liveClassTitle.ifBlank("Live"),
                    title: snapshot.liveClassAction.ifBlank("Unterricht & Termine"),
                    message: snapshot.liveClassDescription.ifBlank("Dieser Bereich bleibt direkt mit der Website gekoppelt."),
                    isEnabled: !snapshot.liveClassExternalURL.isEmpty || !snapshot.liveClassPath.isEmpty || !snapshot.liveClassActionID.isEmpty
                ) {
                    if !snapshot.liveClassExternalURL.isEmpty {
                        onOpenExternal(snapshot.liveClassExternalURL)
                    } else if !snapshot.liveClassPath.isEmpty {
                        onOpen(snapshot.liveClassPath)
                    } else if !snapshot.liveClassActionID.isEmpty {
                        onTriggerAction(snapshot.liveClassActionID, "/dashboard")
                    }
                }

                FocusCard(
                    eyebrow: snapshot.currentModuleTitle.ifBlank("Aktuelles Kapitel"),
                    title: snapshot.currentLessonTitle.ifBlank("Lernstand fortsetzen"),
                    message: snapshot.currentLessonDescription.ifBlank("Hier zeigen wir das laufende Kapitel und springen exakt zur Website-Position zurück."),
                    isEnabled: !snapshot.currentLessonPath.isEmpty || !snapshot.currentLessonActionID.isEmpty
                ) {
                    if !snapshot.currentLessonPath.isEmpty {
                        onOpen(snapshot.currentLessonPath)
                    } else if !snapshot.currentLessonActionID.isEmpty {
                        onTriggerAction(snapshot.currentLessonActionID, "/dashboard")
                    }
                }
            }

            SectionTitle(title: "Module", subtitle: "Live aus dem Dashboard gelesen.")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 18)], spacing: 18) {
                ForEach(snapshot.modules) { module in
                    ProgressTile(
                        title: module.title,
                        subtitle: module.progressLabel,
                        progress: module.progressValue
                    ) {
                        if !module.routePath.isEmpty {
                            onOpen(module.routePath)
                        } else if !module.actionID.isEmpty {
                            onTriggerAction(module.actionID, "/dashboard")
                        }
                    }
                    .disabled(module.routePath.isEmpty && module.actionID.isEmpty)
                }
            }
        }
    }
}

private struct ModulesOverview: View {
    let snapshot: ModulesSnapshot
    let onOpen: (String) -> Void
    let onTriggerAction: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionTitle(title: "Modulhub", subtitle: "Fortschritt und Einstiege werden nativ vorbereitet, bleiben aber web-synchron.")

            ForEach(snapshot.modules) { module in
                WideProgressRow(
                    title: module.title,
                    subtitle: module.subtitle,
                    progress: module.progressValue,
                    actionTitle: "Fortsetzen",
                    isEnabled: !module.continuePath.isEmpty || !module.continueActionID.isEmpty || !module.routePath.isEmpty || !module.routeActionID.isEmpty
                ) {
                    if !module.continuePath.isEmpty {
                        onOpen(module.continuePath)
                    } else if !module.continueActionID.isEmpty {
                        onTriggerAction(module.continueActionID, "/dashboard/modules")
                    } else if !module.routePath.isEmpty {
                        onOpen(module.routePath)
                    } else if !module.routeActionID.isEmpty {
                        onTriggerAction(module.routeActionID, "/dashboard/modules")
                    }
                }
            }
        }
    }
}

private struct LearningOverview: View {
    let snapshot: LessonSnapshot
    let onOpen: (String) -> Void
    let onTriggerAction: (String, String) -> Void
    let onSelectQuizOption: (String, String) -> Void
    let onNavigateLesson: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionTitle(title: snapshot.title.ifBlank("Lernansicht"), subtitle: snapshot.subtitle.ifBlank("Diese Ansicht ist die Grundlage fuer native Aufgaben- und Quiz-Screens."))

            if !snapshot.progressLabel.isEmpty {
                StatusChip(title: snapshot.progressLabel, symbol: "chart.bar.doc.horizontal")
            }

            if snapshot.quiz.isAvailable {
                QuizExperienceView(
                    quiz: snapshot.quiz,
                    onSelectOption: onSelectQuizOption,
                    onNavigate: onNavigateLesson
                )
            }

            ForEach(snapshot.items) { item in
                LessonItemRow(item: item) {
                    if !item.routePath.isEmpty {
                        onOpen(item.routePath)
                    } else if !item.actionID.isEmpty, !snapshot.routePath.isEmpty {
                        onTriggerAction(item.actionID, snapshot.routePath)
                    }
                }
                .disabled(item.routePath.isEmpty && (item.actionID.isEmpty || snapshot.routePath.isEmpty))
            }

            if snapshot.items.isEmpty {
                EmptyStateCard(
                    title: "Noch keine Lesson-Daten gelesen",
                    message: "Oeffne rechts eine Kapitel-, Aufgaben- oder Quiz-Seite. Danach fuellen wir diese native Ansicht automatisch."
                )
            }
        }
    }
}

private struct ProfileOverview: View {
    let snapshot: ProfileSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionTitle(title: "Profil", subtitle: "Auch Formulardaten koennen wir spaeter aus dem nativen UI zur Originalseite zurueckschreiben.")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                InfoCard(title: "Vorname", value: snapshot.firstName)
                InfoCard(title: "Nachname", value: snapshot.lastName)
                InfoCard(title: "Geburtsdatum", value: snapshot.birthDate)
                InfoCard(title: "Geschlecht", value: snapshot.gender)
                InfoCard(title: "E-Mail", value: snapshot.email)
                InfoCard(title: "Telefon", value: snapshot.phone)
            }
        }
    }
}

struct AppSidebar: View {
    let selectedRoute: AppSidebarRoute
    let onSelectRoute: (AppSidebarRoute) -> Void

    var body: some View {
        List {
            HStack(spacing: 12) {
                Image("BrandMark")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Syntax Sync")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("Native shell")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(SurfacePalette.secondaryText)
                }
            }
            .listRowSeparator(.hidden)

            ForEach(AppSidebarRoute.allCases) { route in
                Button {
                    onSelectRoute(route)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: route.symbolName)
                            .frame(width: 18)
                        Text(route.title)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(selectedRoute == route ? Color.accentColor.opacity(0.18) : Color.clear)
                        .padding(.vertical, 2)
                )
            }
        }
        .navigationTitle("Syntax")
    }
}

private struct HeroHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 16) {
                Image("BrandMark")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
                VStack(alignment: .leading, spacing: 10) {
                    Text(title)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text(subtitle)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(SurfacePalette.secondaryText)
                }
            }
        }
    }
}

private struct SectionTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 21, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(SurfacePalette.secondaryText)
        }
    }
}

private struct FocusCard: View {
    let eyebrow: String
    let title: String
    let message: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(eyebrow.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.40, green: 0.39, blue: 0.96))
            Text(title)
                .font(.system(size: 19, weight: .bold, design: .rounded))
            Text(message)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.82))
                .lineLimit(5)
            Spacer(minLength: 0)
            Button("Oeffnen", action: action)
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.32, green: 0.28, blue: 0.93))
                .disabled(!isEnabled)
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [Color(red: 0.09, green: 0.10, blue: 0.24), Color(red: 0.19, green: 0.10, blue: 0.31)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .foregroundStyle(.white)
        .opacity(isEnabled ? 1 : 0.72)
    }
}

private struct ProgressTile: View {
    let title: String
    let subtitle: String
    let progress: Double
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.leading)
                ProgressView(value: progress)
                    .tint(Color(red: 0.39, green: 0.84, blue: 0.57))
                Text(subtitle.ifBlank("Fortschritt wird geladen"))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(SurfacePalette.secondaryText)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
            .background(SurfacePalette.lightCardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct WideProgressRow: View {
    let title: String
    let subtitle: String
    let progress: Double
    let actionTitle: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text(subtitle.ifBlank("Synchronisiert"))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(SurfacePalette.secondaryText)
                ProgressView(value: progress)
                    .tint(Color(red: 0.39, green: 0.84, blue: 0.57))
            }

            Spacer()

            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.07, green: 0.10, blue: 0.27))
                .disabled(!isEnabled)
        }
        .padding(20)
        .opacity(isEnabled ? 1 : 0.72)
        .background(SurfacePalette.lightCardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct LessonItemRow: View {
    let item: LessonItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.leading)
                    Text(item.subtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(SurfacePalette.secondaryText)
                        .lineLimit(3)
                }
                Spacer()
                if !item.statusLabel.isEmpty {
                    Text(item.statusLabel)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color(red: 0.91, green: 0.88, blue: 0.99), in: Capsule())
                        .foregroundStyle(Color(red: 0.35, green: 0.26, blue: 0.94))
                }
            }
            .padding(18)
            .background(SurfacePalette.lightCardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct QuizExperienceView: View {
    let quiz: QuizSnapshot
    let onSelectOption: (String, String) -> Void
    let onNavigate: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionTitle(
                title: quiz.title.ifBlank("Quiz"),
                subtitle: quiz.modeLabel.ifBlank("Native Quizansicht mit Live-Synchronisierung zur Website.")
            )

            ForEach(quiz.questions) { question in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(question.positionLabel)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.35, green: 0.26, blue: 0.94))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(red: 0.91, green: 0.88, blue: 0.99), in: Capsule())
                        Spacer()
                    }

                    Text(question.prompt)
                        .font(.system(size: 19, weight: .bold, design: .rounded))

                    if !question.hint.isEmpty {
                        Text(question.hint)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(SurfacePalette.secondaryText)
                    }

                    ForEach(question.options) { option in
                        Button {
                            onSelectOption(question.id, option.id)
                        } label: {
                            HStack(spacing: 14) {
                                Circle()
                                    .fill(option.isSelected ? Color(red: 0.35, green: 0.26, blue: 0.94) : Color.white)
                                    .frame(width: 16, height: 16)
                                    .overlay(
                                        Circle()
                                            .stroke(option.isSelected ? Color(red: 0.35, green: 0.26, blue: 0.94) : Color.gray.opacity(0.35), lineWidth: 2)
                                    )

                                Text(option.title)
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color.primary)
                                    .multilineTextAlignment(.leading)

                                Spacer()
                            }
                            .padding(16)
                            .background(
                                option.isSelected ? Color(red: 0.93, green: 0.90, blue: 1.0) : Color.white.opacity(0.80),
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
                .background(SurfacePalette.lightCardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }

            HStack(spacing: 12) {
                Button {
                    onNavigate(false)
                } label: {
                    Label("Zurueck", systemImage: "arrow.left")
                }
                .buttonStyle(.bordered)
                .disabled(!quiz.canGoBack)

                Button {
                    onNavigate(true)
                } label: {
                    Label("Weiter", systemImage: "arrow.right")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.07, green: 0.10, blue: 0.27))
                .disabled(!quiz.canGoForward)
            }
        }
    }
}

private struct InfoCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(SurfacePalette.subtleText)
            Text(value.ifBlank("Nicht verfuegbar"))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .lineLimit(2)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SurfacePalette.lightCardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct EmptyStateCard: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
            Text(message)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(SurfacePalette.secondaryText)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SurfacePalette.lightCardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct StatusChip: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.78), in: Capsule())
    }
}

private extension String {
    func ifBlank(_ fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }
}

private enum SurfacePalette {
    static let lightCardBackground = Color.white.opacity(0.84)
    static let secondaryText = Color(red: 0.24, green: 0.28, blue: 0.38)
    static let subtleText = Color(red: 0.41, green: 0.46, blue: 0.56)
    static let darkSecondaryText = Color.white.opacity(0.74)
}
