import Foundation
import AppKit
import WebKit

@MainActor
final class SyntaxWebController: NSObject {
    let webView: WKWebView
    var onStateChange: ((SyntaxWebState) -> Void)?
    var onBackgroundStateSync: ((SyntaxWebState) -> Void)?
    private let logger: SyntaxLogger

    private var state = SyntaxWebState()
    private let baseURL = URL(string: "https://app.syntax-institut.de")!
    private let allowedHost = URL(string: "https://app.syntax-institut.de")!.host
    private let backgroundWebView: WKWebView
    private var backgroundRefreshQueue: [String] = []
    private var isBackgroundRefreshRunning = false
    private var observers: [NSKeyValueObservation] = []

    init(logger: SyntaxLogger) {
        self.logger = logger
        let config = Self.makeConfiguration()
        let backgroundConfig = Self.makeConfiguration()
        self.webView = WKWebView(frame: .zero, configuration: config)
        self.backgroundWebView = WKWebView(frame: .zero, configuration: backgroundConfig)
        super.init()

        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        backgroundWebView.navigationDelegate = self
        installObservers()
        logger.log(.web, "WebController initialisiert")
    }

    private static func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController = WKUserContentController()
        return configuration
    }

    func loadDashboard() {
        logger.log(.navigation, "Dashboard laden")
        navigate(path: "/dashboard")
    }

    func navigate(path: String) {
        guard let url = normalizedNavigationURL(for: path) else {
            logger.log(.error, "Navigation blockiert", metadata: ["path": path])
            return
        }
        logger.log(.navigation, "Navigation starten", metadata: ["path": url.path()])
        webView.load(URLRequest(url: url))
    }

    func reload() {
        logger.log(.navigation, "Reload ausgeloest", metadata: ["path": state.currentPath])
        webView.reload()
    }

    func openExternalURLString(_ value: String) {
        guard let url = URL(string: value) else {
            logger.log(.error, "Externe URL ungueltig", metadata: ["url": value])
            return
        }

        if let host = url.host, host == allowedHost, url.path(percentEncoded: false).hasPrefix("/dashboard") {
            navigate(path: url.path(percentEncoded: false))
            return
        }

        logger.log(.navigation, "Externe URL geoeffnet", metadata: ["url": value])
        NSWorkspace.shared.open(url)
    }

    func startBackgroundRefresh(paths: [String]) {
        let sanitizedPaths = Array(
            NSOrderedSet(array: paths.compactMap { normalizedNavigationURL(for: $0)?.path() })
        ).compactMap { $0 as? String }

        guard !sanitizedPaths.isEmpty else { return }

        backgroundRefreshQueue = sanitizedPaths
        guard !isBackgroundRefreshRunning else { return }

        isBackgroundRefreshRunning = true
        logger.log(.web, "Hintergrund-Sync gestartet", metadata: ["paths": sanitizedPaths.joined(separator: ",")])
        loadNextBackgroundRoute()
    }

    func selectQuizOption(questionID: String, optionID: String) {
        let script = """
        (() => {
          const question = document.querySelector(`[data-syntax-question-id="\(questionID)"]`);
          if (!question) return false;
          const option = question.querySelector(`[data-syntax-option-id="\(optionID)"]`);
          if (!option) return false;
          option.click();
          return true;
        })()
        """

        Task { @MainActor in
            do {
                let result = try await webView.evaluateJavaScript(script)
                logger.log(.web, "Quiz-Klick an Website gesendet", metadata: ["result": "\(String(describing: result))"])
                try? await Task.sleep(nanoseconds: 350_000_000)
                scrapeCurrentPage()
            } catch {
                setError(error.localizedDescription)
            }
        }
    }

    func triggerLessonNavigation(forward: Bool) {
        let buttonLabel = forward ? "Weiter" : "Zurück"
        let script = """
        (() => {
          const buttons = Array.from(document.querySelectorAll('button'));
          const target = buttons.find((button) => (button.innerText || '').replace(/\\s+/g, ' ').trim() === '\(buttonLabel)');
          if (!target) return false;
          target.click();
          return true;
        })()
        """

        Task { @MainActor in
            do {
                let result = try await webView.evaluateJavaScript(script)
                logger.log(.web, "Lesson-Navigation an Website gesendet", metadata: ["direction": forward ? "forward" : "backward", "result": "\(String(describing: result))"])
                try? await Task.sleep(nanoseconds: 450_000_000)
                scrapeCurrentPage()
            } catch {
                setError(error.localizedDescription)
            }
        }
    }

    func performBridgeAction(actionID: String) {
        let script = """
        (() => {
          const target = document.querySelector(`[data-syntax-action-id="\(actionID)"]`);
          if (!target) return false;
          const clickable = target.closest('button, a[href], [role="button"]') || target;
          clickable.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
          clickable.click();
          return true;
        })()
        """

        Task { @MainActor in
            do {
                let result = try await webView.evaluateJavaScript(script)
                logger.log(.web, "Bridge-Aktion an Website gesendet", metadata: ["actionID": actionID, "result": "\(String(describing: result))"])
                try? await Task.sleep(nanoseconds: 500_000_000)
                scrapeCurrentPage()
            } catch {
                setError(error.localizedDescription)
            }
        }
    }

    private func installObservers() {
        observers.append(
            webView.observe(\.title, options: [.new]) { [weak self] _, change in
                guard let self else { return }
                Task { @MainActor in
                    self.state.pageTitle = (change.newValue ?? nil) ?? "Syntax Sync"
                    self.logger.log(.state, "Seitentitel aktualisiert", metadata: ["title": self.state.pageTitle])
                    self.publishState()
                }
            }
        )
        observers.append(
            webView.observe(\.url, options: [.new]) { [weak self] _, change in
                guard let self, let path = change.newValue??.path(percentEncoded: false) else { return }
                Task { @MainActor in
                    self.state.currentPath = path.isEmpty ? "/dashboard" : path
                    self.logger.log(.state, "URL aktualisiert", metadata: ["path": self.state.currentPath])
                    self.publishState()
                }
            }
        )
        observers.append(
            webView.observe(\.isLoading, options: [.new]) { [weak self] _, change in
                guard let self else { return }
                Task { @MainActor in
                    self.state.isLoading = change.newValue ?? false
                    self.logger.log(.state, "Loading-Status aktualisiert", metadata: ["isLoading": "\(self.state.isLoading)"])
                    self.publishState()
                }
            }
        )
    }

    private func publishState() {
        logger.log(.state, "State publiziert", metadata: ["path": state.currentPath, "route": state.sidebarRoute.rawValue])
        onStateChange?(state)
    }

    private func normalizedNavigationURL(for path: String) -> URL? {
        guard let url = URL(string: path, relativeTo: baseURL) else { return nil }
        guard let host = url.host, host == allowedHost else { return nil }
        guard url.scheme == "https" else { return nil }
        return url
    }

    private func shouldIgnoreNavigationError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return true
        }
        return false
    }

    private func setError(_ message: String?) {
        state.errorMessage = message
        logger.log(.error, "WebController Fehler", metadata: ["message": message ?? "nil"])
        publishState()
    }

    private func scrapeCurrentPage() {
        Task { @MainActor in
            do {
                let result = try await evaluateScraper(in: webView)
                state.currentPath = result.currentPath
                state.pageTitle = result.pageTitle
                state.isLoggedIn = result.isLoggedIn
                state.dashboard = result.dashboard
                state.modules = result.modules
                state.lesson = result.lesson
                state.profile = result.profile
                state.errorMessage = nil
                logger.log(
                    .web,
                    "Seite gescraped",
                    metadata: [
                        "path": result.currentPath,
                        "quizQuestions": "\(result.lesson.quiz.questions.count)",
                        "lessonItems": "\(result.lesson.items.count)"
                    ]
                )
                publishState()
            } catch {
                setError(error.localizedDescription)
            }
        }
    }

    private func scrapeBackgroundPage() {
        Task { @MainActor in
            do {
                let result = try await evaluateScraper(in: backgroundWebView)
                logger.log(
                    .web,
                    "Hintergrundseite gescraped",
                    metadata: [
                        "path": result.currentPath,
                        "quizQuestions": "\(result.lesson.quiz.questions.count)",
                        "lessonItems": "\(result.lesson.items.count)"
                    ]
                )
                onBackgroundStateSync?(result)
            } catch {
                logger.log(.error, "Hintergrund-Scrape fehlgeschlagen", metadata: ["message": error.localizedDescription])
            }

            loadNextBackgroundRoute()
        }
    }

    private func loadNextBackgroundRoute() {
        guard let nextPath = backgroundRefreshQueue.first else {
            isBackgroundRefreshRunning = false
            logger.log(.web, "Hintergrund-Sync abgeschlossen")
            return
        }

        backgroundRefreshQueue.removeFirst()

        guard let url = normalizedNavigationURL(for: nextPath) else {
            loadNextBackgroundRoute()
            return
        }

        backgroundWebView.load(URLRequest(url: url))
    }

    private func evaluateScraper(in webView: WKWebView) async throws -> SyntaxWebState {
        let raw = try await webView.evaluateJavaScript(scraperScript)
        guard let jsonString = raw as? String else {
            throw NSError(domain: "SyntaxWebController", code: 1, userInfo: [NSLocalizedDescriptionKey: "Website-Antwort konnte nicht gelesen werden."])
        }

        let data = Data(jsonString.utf8)
        let payload = try JSONDecoder().decode(ScraperPayload.self, from: data)

        var nextState = state
        nextState.currentPath = payload.currentPath
        nextState.pageTitle = payload.pageTitle
        nextState.isLoggedIn = payload.isLoggedIn
        nextState.dashboard = payload.dashboard.toSnapshot()
        nextState.modules = payload.modules.toSnapshot()
        nextState.lesson = payload.lesson.toSnapshot()
        nextState.profile = payload.profile.toSnapshot()
        return nextState
    }
}

extension SyntaxWebController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === backgroundWebView {
            scrapeBackgroundPage()
            return
        }
        scrapeCurrentPage()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else {
            return .allow
        }

        if navigationAction.targetFrame?.isMainFrame == true {
            if let host = url.host, host != allowedHost {
                if webView === backgroundWebView {
                    logger.log(.navigation, "Externe Hintergrund-Navigation blockiert", metadata: ["url": url.absoluteString])
                    return .cancel
                }
                logger.log(.navigation, "Externe Navigation blockiert", metadata: ["url": url.absoluteString])
                NSWorkspace.shared.open(url)
                return .cancel
            }
        }

        return .allow
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if shouldIgnoreNavigationError(error) { return }
        if webView === backgroundWebView {
            logger.log(.error, "Hintergrund-Navigation fehlgeschlagen", metadata: ["message": error.localizedDescription])
            loadNextBackgroundRoute()
            return
        }
        setError(error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if shouldIgnoreNavigationError(error) { return }
        if webView === backgroundWebView {
            logger.log(.error, "Hintergrund-Provisional-Navigation fehlgeschlagen", metadata: ["message": error.localizedDescription])
            loadNextBackgroundRoute()
            return
        }
        setError(error.localizedDescription)
    }
}

extension SyntaxWebController: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = navigationAction.request.url else {
            return nil
        }

        if let host = url.host, host == allowedHost, url.path(percentEncoded: false).hasPrefix("/dashboard") {
            webView.load(URLRequest(url: url))
            return nil
        }

        logger.log(.navigation, "Neues Web-Fenster extern geoeffnet", metadata: ["url": url.absoluteString])
        NSWorkspace.shared.open(url)
        return nil
    }
}

private struct ScraperPayload: Decodable {
    var currentPath: String
    var pageTitle: String
    var isLoggedIn: Bool
    var dashboard: DashboardPayload
    var modules: ModulesPayload
    var lesson: LessonPayload
    var profile: ProfilePayload
}

private struct DashboardPayload: Decodable {
    var greeting: String
    var userName: String
    var liveClassTitle: String
    var liveClassDescription: String
    var liveClassAction: String
    var liveClassPath: String
    var liveClassExternalURL: String
    var liveClassActionID: String
    var currentModuleTitle: String
    var currentLessonTitle: String
    var currentLessonDescription: String
    var currentLessonPath: String
    var currentLessonActionID: String
    var modules: [ModuleCardPayload]

    func toSnapshot() -> DashboardSnapshot {
        DashboardSnapshot(
            greeting: greeting,
            userName: userName,
            liveClassTitle: liveClassTitle,
            liveClassDescription: liveClassDescription,
            liveClassAction: liveClassAction,
            liveClassPath: liveClassPath,
            liveClassExternalURL: liveClassExternalURL,
            liveClassActionID: liveClassActionID,
            currentModuleTitle: currentModuleTitle,
            currentLessonTitle: currentLessonTitle,
            currentLessonDescription: currentLessonDescription,
            currentLessonPath: currentLessonPath,
            currentLessonActionID: currentLessonActionID,
            modules: modules.enumerated().map { index, item in
                ModuleCard(
                    id: item.id.ifEmpty("dashboard-module-\(index)"),
                    title: item.title,
                    progressLabel: item.progressLabel,
                    progressValue: item.progressValue,
                    routePath: item.routePath,
                    actionID: item.actionID
                )
            }
        )
    }
}

private struct ModulesPayload: Decodable {
    var modules: [ModuleProgressPayload]

    func toSnapshot() -> ModulesSnapshot {
        ModulesSnapshot(
            modules: modules.enumerated().map { index, item in
                ModuleProgress(
                    id: item.id.ifEmpty("module-\(index)"),
                    title: item.title,
                    subtitle: item.subtitle,
                    progressValue: item.progressValue,
                    routePath: item.routePath,
                    routeActionID: item.routeActionID,
                    continuePath: item.continuePath,
                    continueActionID: item.continueActionID
                )
            }
        )
    }
}

private struct LessonPayload: Decodable {
    var routePath: String
    var breadcrumbs: [String]
    var title: String
    var subtitle: String
    var progressLabel: String
    var items: [LessonItemPayload]
    var quiz: QuizPayload

    func toSnapshot() -> LessonSnapshot {
        LessonSnapshot(
            routePath: routePath,
            breadcrumbs: breadcrumbs,
            title: title,
            subtitle: subtitle,
            progressLabel: progressLabel,
            items: items.enumerated().map { index, item in
                LessonItem(
                    id: item.id.ifEmpty("lesson-item-\(index)"),
                    title: item.title,
                    subtitle: item.subtitle,
                    statusLabel: item.statusLabel,
                    routePath: item.routePath,
                    actionID: item.actionID
                )
            },
            quiz: quiz.toSnapshot()
        )
    }
}

private struct ProfilePayload: Decodable {
    var firstName: String
    var lastName: String
    var birthDate: String
    var gender: String
    var email: String
    var phone: String

    func toSnapshot() -> ProfileSnapshot {
        ProfileSnapshot(
            firstName: firstName,
            lastName: lastName,
            birthDate: birthDate,
            gender: gender,
            email: email,
            phone: phone
        )
    }
}

private struct ModuleCardPayload: Decodable {
    var id: String
    var title: String
    var progressLabel: String
    var progressValue: Double
    var routePath: String
    var actionID: String
}

private struct ModuleProgressPayload: Decodable {
    var id: String
    var title: String
    var subtitle: String
    var progressValue: Double
    var routePath: String
    var routeActionID: String
    var continuePath: String
    var continueActionID: String
}

private struct LessonItemPayload: Decodable {
    var id: String
    var title: String
    var subtitle: String
    var statusLabel: String
    var routePath: String
    var actionID: String
}

private struct QuizPayload: Decodable {
    var title: String
    var modeLabel: String
    var routePath: String
    var progressLabel: String
    var questions: [QuizQuestionPayload]
    var canGoBack: Bool
    var canGoForward: Bool

    func toSnapshot() -> QuizSnapshot {
        QuizSnapshot(
            title: title,
            modeLabel: modeLabel,
            routePath: routePath,
            progressLabel: progressLabel,
            questions: questions.enumerated().map { index, item in
                QuizQuestion(
                    id: item.id.ifEmpty("quiz-question-\(index)"),
                    prompt: item.prompt,
                    hint: item.hint,
                    positionLabel: item.positionLabel,
                    options: item.options.enumerated().map { optionIndex, option in
                        QuizOption(
                            id: option.id.ifEmpty("quiz-option-\(index)-\(optionIndex)"),
                            title: option.title,
                            isSelected: option.isSelected
                        )
                    }
                )
            },
            canGoBack: canGoBack,
            canGoForward: canGoForward
        )
    }
}

private struct QuizQuestionPayload: Decodable {
    var id: String
    var prompt: String
    var hint: String
    var positionLabel: String
    var options: [QuizOptionPayload]
}

private struct QuizOptionPayload: Decodable {
    var id: String
    var title: String
    var isSelected: Bool
}

private extension String {
    func ifEmpty(_ replacement: String) -> String {
        isEmpty ? replacement : self
    }
}

private let scraperScript = """
(() => {
  const text = (value) => (value || '').replace(/\\s+/g, ' ').trim();
  const rawNodeText = (node) => (node?.innerText || node?.textContent || '').replace(/\\u00a0/g, ' ');
  const lines = (node) => rawNodeText(node).split(/\\n+/).map(text).filter(Boolean);
  const normalized = (value) => text(value).toLowerCase();
  const hrefPath = (node) => {
    const target = node?.closest('a[href]') || node?.querySelector?.('a[href]');
    if (!target) return '';
    try {
      const url = new URL(target.getAttribute('href'), location.origin);
      if (url.origin !== location.origin) return '';
      if (!url.pathname.startsWith('/dashboard')) return '';
      return url.pathname;
    } catch {
      return '';
    }
  };
  const hrefURL = (node) => {
    const target = node?.closest('a[href]') || node?.querySelector?.('a[href]');
    if (!target) return '';
    try {
      return new URL(target.getAttribute('href'), location.origin).toString();
    } catch {
      return '';
    }
  };
  const isClickable = (node) => !!node && typeof node.matches === 'function' && node.matches('a[href], button, [role="button"]');
  const findClickable = (node, matcher) => {
    if (!node) return null;
    const candidates = [
      ...(isClickable(node) ? [node] : []),
      ...Array.from(node.querySelectorAll?.('a[href], button, [role="button"]') || [])
    ];
    return candidates.find((candidate) => {
      const value = text(candidate.textContent);
      if (!value) return false;
      return matcher ? matcher(value, candidate) : true;
    }) || candidates[0] || null;
  };
  const registerAction = (node, id) => {
    const target = isClickable(node) ? node : findClickable(node);
    if (!target) return '';
    target.setAttribute('data-syntax-action-id', id);
    return id;
  };
  const closestCard = (node, predicate) => {
    let current = node;
    let fallback = null;
    while (current && current !== document.body) {
      const content = text(rawNodeText(current));
      if (content && !fallback && current.matches?.('div[class], section, article, main')) {
        fallback = current;
      }
      const looksLikeContainer = current !== node || content.length > 80 || !!current.querySelector?.('a[href], button, [role="button"]');
      if (content && looksLikeContainer && (!predicate || predicate(content, current))) return current;
      current = current.parentElement;
    }
    return fallback || node?.closest?.('div[class]') || node?.parentElement || null;
  };
  const findCardByText = (label) => {
    const el = Array.from(document.querySelectorAll('body *')).find((node) => text(node.textContent) === label);
    return closestCard(el, (content) => content.includes(label));
  };
  const parsePercent = (value) => {
    const match = text(value).match(/(\\d+(?:[\\.,]\\d+)?)\\s*%/);
    return match ? Number(match[1].replace(',', '.')) / 100 : 0;
  };
  const unique = (values) => Array.from(new Set(values.filter(Boolean)));
  const isVisible = (node) => !!node && !(node.offsetParent === null && getComputedStyle(node).position !== 'fixed');
  const questionMarkerPattern = /^frage\\s+\\d+\\s*\\/\\s*\\d+$/i;
  const optionIgnorePattern = /^(zurück|zurueck|weiter|pru?fungsmodus|eine antwort trifft zu|antwort speichern|weiter zur naechsten frage)$/i;
  const findQuestionContainer = (node) => {
    let current = node;
    while (current && current !== document.body) {
      const candidateText = text(current.textContent);
      const buttonCount = current.querySelectorAll('button').length;
      if (buttonCount >= 2 && candidateText.length < 2000) return current;
      current = current.parentElement;
    }
    return node?.parentElement || document.body;
  };
  const extractQuestionPrompt = (container, positionLabel) => {
    const candidates = Array.from(container.querySelectorAll('h1, h2, h3, h4, p, span, strong, div'))
      .map((node) => text(node.textContent))
      .filter((value) => value && value !== positionLabel && !questionMarkerPattern.test(value))
      .filter((value) => !optionIgnorePattern.test(value))
      .filter((value) => value.length > 12 && value.length < 280);

    return candidates.find((value) => value.includes('?'))
      || candidates.find((value) => /[a-zA-ZÄÖÜäöü]/.test(value))
      || '';
  };
  const extractHint = (container) => {
    return Array.from(container.querySelectorAll('p, span, div, small'))
      .map((node) => text(node.textContent))
      .find((value) => /antwort trifft zu/i.test(value) || /mehrere antworten/i.test(value)) || '';
  };
  const extractOptions = (container, index, positionLabel, prompt, hint) => {
    const seenTitles = new Set();
    return Array.from(container.querySelectorAll('button, [role="button"], label'))
      .filter(isVisible)
      .map((candidate, optionIndex) => {
        const optionTitle = text(candidate.textContent);
        if (!optionTitle) return null;
        if (optionTitle === positionLabel || optionTitle === prompt || optionTitle === hint) return null;
        if (questionMarkerPattern.test(optionTitle) || optionIgnorePattern.test(optionTitle)) return null;
        if (optionTitle.length > 180) return null;
        if (seenTitles.has(optionTitle)) return null;
        seenTitles.add(optionTitle);

        const classText = typeof candidate.className === 'string' ? candidate.className : '';
        const ariaChecked = candidate.getAttribute('aria-checked');
        const ariaPressed = candidate.getAttribute('aria-pressed');
        const selected = ariaChecked === 'true'
          || ariaPressed === 'true'
          || candidate.getAttribute('data-state') === 'checked'
          || /selected|checked|active/.test(classText)
          || candidate.innerHTML.includes('rgb(117, 94, 255)')
          || candidate.innerHTML.includes('text-secondary');

        candidate.setAttribute('data-syntax-option-id', `q${index}-o${optionIndex}`);
        return {
          id: `q${index}-o${optionIndex}`,
          title: optionTitle,
          isSelected: selected
        };
      })
      .filter(Boolean);
  };

  const bodyLines = lines(document.body);
  const bodyText = text(document.body.innerText);
  const currentPath = location.pathname;
  const pageTitle = document.title || 'Syntax Sync';
  const isLoggedIn = currentPath.startsWith('/dashboard');

  const dashboard = {
    greeting: '',
    userName: '',
    liveClassTitle: '',
    liveClassDescription: '',
    liveClassAction: '',
    liveClassPath: '',
    liveClassExternalURL: '',
    liveClassActionID: '',
    currentModuleTitle: '',
    currentLessonTitle: '',
    currentLessonDescription: '',
    currentLessonPath: '',
    currentLessonActionID: '',
    modules: []
  };

  const greetingLine = bodyLines.find((line) => /^Hallo\\b/.test(line)) || '';
  const greetingMatch = greetingLine.match(/^Hallo\\s+(.+?)(?:\\s*🎉|$)/);
  if (greetingMatch) {
    dashboard.greeting = greetingLine;
    dashboard.userName = greetingMatch[1].replace(/[🎉]/g, '').trim();
  }

  const liveCard = findCardByText('Live-Unterricht');
  if (liveCard) {
    const liveTexts = lines(liveCard);
    const liveActionTarget = findClickable(liveCard, (value) => /unterricht beitreten|zoom|live/i.test(value));
    const liveURL = hrefURL(liveActionTarget || liveCard);
    dashboard.liveClassTitle = liveTexts.find((item) => item === 'Live-Unterricht') || '';
    dashboard.liveClassDescription = liveTexts.find((item) => item.includes('virtuellen Klassenzimmer')) || '';
    dashboard.liveClassAction = liveTexts.find((item) => item.includes('Unterricht beitreten')) || text(liveActionTarget?.textContent);
    dashboard.liveClassPath = hrefPath(liveActionTarget || liveCard);
    dashboard.liveClassExternalURL = liveURL && !liveURL.startsWith(location.origin) ? liveURL : '';
    dashboard.liveClassActionID = registerAction(liveActionTarget || liveCard, 'dashboard-live');
  }

  const currentActionTarget = Array.from(document.querySelectorAll('button, a, [role="button"]'))
    .find((node) => /fortsetzen/i.test(text(node.textContent)));
  const currentCard = closestCard(currentActionTarget, (content) => content.includes('Fortsetzen') && content.length > 80);
  if (currentCard) {
    const cardText = text(rawNodeText(currentCard));
    const cardLines = lines(currentCard);
    const moduleMatch = cardText.match(/(Web Grundlagen|Web Produktdesign)/);
    const lessonMatch = cardText.match(/(JavaScript\\s+\\d+|HTML|CSS\\s+\\d+|Das Internet|Tools)/);
    dashboard.currentModuleTitle = moduleMatch ? moduleMatch[1] : '';
    dashboard.currentLessonTitle = lessonMatch ? lessonMatch[1] : '';
    dashboard.currentLessonDescription = cardLines
      .filter((line) => !/^Hallo\\b/.test(line))
      .filter((line) => !/(Live-Unterricht|Unterricht beitreten|Fortsetzen|Deine Module|Alle anzeigen)/i.test(line))
      .filter((line) => line !== dashboard.currentModuleTitle && line !== dashboard.currentLessonTitle)
      .join(' ');
    dashboard.currentLessonPath = hrefPath(currentActionTarget || currentCard);
    dashboard.currentLessonActionID = registerAction(currentActionTarget || currentCard, 'dashboard-current-lesson');
  }

  if (currentPath === '/dashboard') {
    const modulePairs = [];
    bodyLines.forEach((line, index) => {
      const progressLabel = (line.match(/^\\d+%$/) || [''])[0];
      if (!progressLabel) return;
      const title = bodyLines[index - 1] || '';
      if (!title || /^(Alle anzeigen|Deine Module|Fortsetzen)$/i.test(title)) return;
      modulePairs.push({ title, progressLabel });
    });

    const seenModules = new Set();
    dashboard.modules = modulePairs.map((pair, index) => {
      const progressNode = Array.from(document.querySelectorAll('body *')).find((node) => text(node.textContent) === pair.progressLabel);
      const card = closestCard(progressNode, (content) => content.includes(pair.title) && content.includes(pair.progressLabel));
      return {
        id: `dashboard-${index}`,
        title: pair.title,
        progressLabel: pair.progressLabel,
        progressValue: parsePercent(pair.progressLabel),
        routePath: hrefPath(card),
        actionID: registerAction(card, `dashboard-module-${index}`)
      };
    }).filter((item) => {
      const key = `${item.title}:${item.progressLabel}`;
      if (seenModules.has(key)) return false;
      seenModules.add(key);
      return item.title;
    });
  }

  const modules = { modules: [] };
  if (currentPath.startsWith('/dashboard/modules')) {
    const continueButtons = Array.from(document.querySelectorAll('button')).filter((button) => text(button.textContent).includes('Fortsetzen'));
    modules.modules = continueButtons.map((button, index) => {
      const card = closestCard(button, (content) => content.includes('Fortsetzen') && (/\\d+ von \\d+ UE/.test(content) || content.length > 80));
      const cardText = text(rawNodeText(card));
      const cardLines = lines(card);
      const subtitleMatch = cardText.match(/\\d+ von \\d+ UE/);
      const title = cardLines.find((line) => {
        if (/^(Modulübersicht|Modulubersicht|Fortsetzen)$/i.test(line)) return false;
        if (/\\d+ von \\d+ UE/.test(line)) return false;
        return line.length > 2 && line.length < 120;
      }) || text(cardText.split(/\\d+ von \\d+ UE/)[0].replace(/Modulübersicht|Fortsetzen/g, ''));
      const overviewTarget = findClickable(card, (value) => /modulübersicht|modulubersicht/i.test(value));
      return {
        id: `module-card-${index}`,
        title,
        subtitle: subtitleMatch ? subtitleMatch[0] : '',
        progressValue: subtitleMatch ? (() => {
          const m = subtitleMatch[0].match(/(\\d+) von (\\d+) UE/);
          return m ? Number(m[1]) / Number(m[2]) : 0;
        })() : 0,
        routePath: hrefPath(overviewTarget || card),
        routeActionID: registerAction(overviewTarget || card, `module-overview-${index}`),
        continuePath: hrefPath(button) || hrefPath(card),
        continueActionID: registerAction(button, `module-continue-${index}`)
      };
    });
  }

  const lesson = {
    routePath: '',
    breadcrumbs: [],
    title: '',
    subtitle: '',
    progressLabel: '',
    items: [],
    quiz: {
      title: '',
      modeLabel: '',
      routePath: '',
      progressLabel: '',
      questions: [],
      canGoBack: false,
      canGoForward: false
    }
  };

  if (currentPath.includes('/lection/') || currentPath.includes('/lesson/')) {
    const breadcrumbLinks = Array.from(document.querySelectorAll('a')).map((node) => text(node.textContent)).filter(Boolean);
    lesson.routePath = currentPath;
    lesson.breadcrumbs = breadcrumbLinks.slice(0, 4);

    const headingCandidates = Array.from(document.querySelectorAll('h1, h2, h3, strong')).map((node) => text(node.textContent)).filter(Boolean);
    lesson.title = headingCandidates.find((item) => /\\d+\\.\\d+/.test(item) || /JavaScript|HTML|CSS|Internet|Tools/.test(item)) || '';
    lesson.subtitle = bodyText.includes('Prüfungsmodus') ? 'Quiz' : bodyText.includes('Aufgabe') ? 'Aufgabe' : 'Inhalt';
    const progressMatch = bodyText.match(/(\\d+\\s*\\/\\s*\\d+|\\d+ von \\d+)/);
    lesson.progressLabel = progressMatch ? progressMatch[1] : '';

    const itemBlocks = Array.from(document.querySelectorAll('body *'))
      .filter((node) => /^\\d+\\.\\d+\\s+/.test(text(node.textContent)))
      .slice(0, 12);

    lesson.items = itemBlocks.map((node, index) => {
      const block = node.closest('div[class]') || node.parentElement;
      const content = text(block?.textContent);
      const titleMatch = content.match(/\\d+\\.\\d+\\s+[^\\n]+/);
      const statusMatch = content.match(/(Erledigt|In Bearbeitung|Quiz|Aufgabe|Inhalt)/);
      return {
        id: `lesson-item-${index}`,
        title: titleMatch ? titleMatch[0] : content.slice(0, 80),
        subtitle: content,
        statusLabel: statusMatch ? statusMatch[1] : '',
        routePath: hrefPath(block),
        actionID: registerAction(block, `lesson-item-${index}`)
      };
    });

    if (currentPath.endsWith('/quiz')) {
      lesson.quiz.routePath = currentPath;
      lesson.quiz.title = lesson.title;
      lesson.quiz.modeLabel = Array.from(document.querySelectorAll('button, span, div'))
        .map((node) => text(node.textContent))
        .find((value) => value.includes('Prüfungsmodus')) || '';
      lesson.quiz.progressLabel = lesson.progressLabel;

      const questionNodes = unique(
        Array.from(document.querySelectorAll('body *'))
          .map((node) => questionMarkerPattern.test(text(node.textContent)) ? node : null)
      );

      lesson.quiz.questions = questionNodes.map((node, index) => {
        const positionLabel = text(node.textContent);
        const container = findQuestionContainer(node);
        const prompt = extractQuestionPrompt(container, positionLabel);
        const hint = extractHint(container);
        const options = extractOptions(container, index, positionLabel, prompt, hint);

        container?.setAttribute?.('data-syntax-question-id', `q${index}`);

        return {
          id: `q${index}`,
          prompt,
          hint,
          positionLabel,
          options
        };
      }).filter((item) => item.options.length > 0);

      if (!lesson.quiz.questions.length) {
        const fallbackContainer = Array.from(document.querySelectorAll('main, form, section, article, body'))
          .find((node) => node.querySelectorAll('button, [role="button"], label').length >= 2);

        if (fallbackContainer) {
          const prompt = extractQuestionPrompt(fallbackContainer, '');
          const hint = extractHint(fallbackContainer);
          const options = extractOptions(fallbackContainer, 0, '', prompt, hint);

          if (options.length > 0) {
            fallbackContainer.setAttribute('data-syntax-question-id', 'q0');
            lesson.quiz.questions = [{
              id: 'q0',
              prompt: prompt || lesson.title || 'Quizfrage',
              hint,
              positionLabel: lesson.progressLabel || '',
              options
            }];
          }
        }
      }

      const buttonTexts = Array.from(document.querySelectorAll('button')).map((button) => text(button.textContent));
      lesson.quiz.canGoBack = buttonTexts.includes('Zurück');
      lesson.quiz.canGoForward = buttonTexts.includes('Weiter');
    }
  }

  const profile = {
    firstName: '',
    lastName: '',
    birthDate: '',
    gender: '',
    email: '',
    phone: ''
  };

  if (currentPath.startsWith('/dashboard/settings')) {
    const valueForLabel = (label) => {
      const labelNode = Array.from(document.querySelectorAll('label, p, span, div')).find((node) => text(node.textContent) === label);
      const field = labelNode?.parentElement?.querySelector('input, select') || labelNode?.closest('div')?.querySelector('input, select');
      return field ? text(field.value || field.textContent) : '';
    };
    profile.firstName = valueForLabel('Vorname');
    profile.lastName = valueForLabel('Nachname');
    profile.birthDate = valueForLabel('Geburtsdatum');
    profile.gender = valueForLabel('Geschlecht');
    profile.email = valueForLabel('Email');
    profile.phone = valueForLabel('Telefonnummer');
  }

  return JSON.stringify({ currentPath, pageTitle, isLoggedIn, dashboard, modules, lesson, profile });
})()
"""
