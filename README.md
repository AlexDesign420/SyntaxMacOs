# Syntax Sync

A native macOS application that wraps the [Syntax Institut](https://app.syntax-institut.de) learning platform in a desktop-friendly interface.

Built with **SwiftUI** and **WKWebView**, the app provides a native macOS experience — sidebar navigation, dashboard, modules, lessons and profile — while keeping the actual logged-in web session alive in the background.

---

## Features

- **Native macOS UI** — SwiftUI sidebar, dashboard, module and lesson views
- **Persistent Web Session** — WKWebView maintains the real login session
- **Data Scraping & Sync** — JavaScript extracts lesson, quiz and profile data from the web page
- **Offline Cache** — Scraped data is stored locally as JSON and restored on app launch
- **Live Lessons & Zoom** — Direct access to live classes and Zoom links
- **Progress Tracking** — Continue where you left off across sessions

---

## Architecture

```
SwiftUI App
    ├── Native Sidebar (Dashboard, Modules, Learn, Profile)
    └── WKWebView (persistent logged-in web session)
            └── JavaScript Bridge
                  ├── Read: lesson data, quiz data, profile info
                  └── Write: user actions back to the website
```

**Data Flow:**
1. App starts → cached JSON data loads instantly
2. WKWebView syncs with the live website in the background
3. JavaScript scrapes updated data and writes it to `syntax-state.json`
4. SwiftUI views reflect the latest data

---

## Tech Stack

| Component | Technology |
|-----------|------------|
| UI Framework | SwiftUI |
| Navigation | NavigationSplitView |
| Web Engine | WKWebView |
| Data Bridge | JavaScript ↔ Swift |
| Local Storage | JSON file (`syntax-state.json`) |
| Platform | macOS 14+ |

---

## Project Status

Reviewed baseline as of 2026-05-13. Verified:

- [x] Project structure and Xcode configuration
- [x] Sandbox and network entitlements
- [x] Core data flows and storage paths
- [x] Native UI + web hybrid architecture

Future development should build on this architecture while respecting the documented data flows and storage paths.

---

## Privacy & Security

- This repository does not intentionally include private personal data.
- The app operates against the public Syntax Institut web platform.
- Personal Xcode user data has been removed from version control.

---

## License

No license selected yet.
