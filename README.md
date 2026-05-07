# MCFinder

A fast, native macOS file search app — local index, instant results, no cloud, no telemetry.

MCFinder builds its own SQLite + FTS5 index of the folders you choose, watches them for changes via FSEvents, and lets you search by name, path, extension, type, size, or date in milliseconds. A Spotlight-style global panel makes it reachable from anywhere on the system.

> Built with SwiftUI + AppKit. Runs sandboxed. macOS 14.0+.

---

## Features

- **Local SQLite + FTS5 index** — millisecond search across hundreds of thousands of files, no Spotlight dependency.
- **Live updates** — FSEvents watcher keeps the index in sync as files are created, moved, or deleted.
- **Four search modes** — `contains`, `exact`, `prefix`, and `pathContains` (full-path matching).
- **Rich filters** — extension, file type (documents / images / audio / video / archives / apps / folders), size range, modified-after date.
- **Sorting** — by name, date, size, or kind (asc/desc).
- **Quick Search panel** — Spotlight-style floating panel with a configurable global hotkey.
- **Quick Look preview** — press space (or use the menu) to preview the selected result.
- **Recent files** — the last 50 files you opened from MCFinder are remembered and surfaced.
- **Customizable global hotkeys** — record any key + modifier for the main window and Quick Search panel; conflicts are detected and surfaced in the UI.
- **Launch at Login** — opt-in via `SMAppService`.
- **Localized** — English & Simplified Chinese.
- **App Sandbox + Security-Scoped Bookmarks** — folder access survives app restarts without re-prompting.

---

## Getting started

### Requirements

- macOS **14.0** or later
- Xcode **15** or later (Swift 5.9+)

### Build & run

```bash
git clone <this repo>
cd mcfinder
open MCFinder.xcodeproj
```

Then in Xcode:

1. Select the `MCFinder` scheme.
2. ⌘R to build and run.

The app is sandboxed; on first launch it has no folders indexed. Use **File → Add Folder to Index…** (⇧⌘N) or the Settings window to grant access to a folder. Desktop / Documents / Downloads are pre-entitled and don't require a security-scoped bookmark.

### First-run flow

1. Launch MCFinder.
2. Add at least one folder via `File → Add Folder to Index…`.
3. Wait for the initial scan to complete (status bar shows live progress).
4. Type in the search field, or press the global hotkey to summon Quick Search.

---

## Default keyboard shortcuts

| Action | Shortcut |
|---|---|
| Show / hide main window (global) | ⌥⌘F |
| Show / hide Quick Search panel (global) | ⇧⌥⌘F |
| Add folder to index | ⇧⌘N |
| Open Settings | ⌘, |
| Toggle Quick Look preview | View menu |

> The default hotkeys avoid `⌘⇧Space`, which macOS reserves for "Select previous input source" — a previous default that silently failed to register. Both global hotkeys are user-configurable in Settings.

---

## Architecture

MCFinder is a single binary, organized as follows:

```
MCFinder/
├── App/              MCFinderApp · AppDelegate · AppState (single source of truth)
├── Database/         DatabaseManager (SQLite/FTS5) · DatabaseModels · SchemaVersion
├── Index/            FileEnumerator · IndexManager (full + incremental scans)
├── Monitoring/       FSEventsMonitor · FSEventsDelegate (live change tracking)
├── Search/           SearchEngine · SearchModels (modes, filters, sorts)
├── QuickSearch/      QuickSearchPanel · QuickSearchView · QuickSearchState
├── Hotkeys/          KeyboardShortcutManager (RegisterEventHotKey) · RecorderNSView
├── Bookmarks/        BookmarkManager (Security-Scoped Bookmarks)
├── Preview/          QuickLookCoordinator (QLPreviewPanel integration)
├── Views/            ContentView · SettingsView · HotkeySettingsView · ResultRowView · AboutView
├── Utilities/        Logger · Extensions · FileTypeDetector
└── Resources/        Info.plist
```

### Data layer

- A single SQLite connection wrapped in a serial dispatch queue (`com.mcfinder.db`). All `sqlite3_*` calls go through it; the connection is opened with `SQLITE_OPEN_FULLMUTEX` as defense-in-depth.
- Pragmas: `journal_mode=WAL`, `synchronous=NORMAL`, `cache_size=-20000` (≈20 MB), `mmap_size=256 MB`, `temp_store=MEMORY`, `foreign_keys=ON`, `busy_timeout=5000`.
- Schema:
  - `files(id, name, path UNIQUE, parent_path, extension, size, modified_at, created_at, is_directory)`
  - `files_fts` — FTS5 virtual table over `name` + `path`, kept in sync via INSERT/UPDATE/DELETE triggers on `files`.
  - Plain B-tree index on `parent_path` for directory enumeration.
- Database file: `~/Library/Containers/com.mcfinder.app/Data/Library/Application Support/MCFinder/mcfinder.db`.

### Search

- The query is built dynamically depending on `SearchMode`. `pathContains` joins `files_fts` for full-text path matching; the other modes operate directly on `files`.
- Hidden paths (`%/.%`) are filtered out at the SQL level.
- Results carry a `rank` score so the UI can present the best matches first.
- Searches run on a `userInitiated` detached `Task` with a 300 ms debounce on user input.

### Indexing

- `IndexManager.scanDirectories(...)` walks each root with `FileEnumerator` and bulk-inserts rows in transactions.
- `FSEventsMonitor` reports changes back to `IndexManager.processFSEventChanges(...)` for incremental updates.
- Re-scans are non-blocking; the UI surfaces a live `scannedCount`.

### Sandbox & permissions

- **Entitlements**: app-sandbox, user-selected read-write, app-scope bookmarks, network client (used only to open external help URLs), and read-write entitlements for Desktop / Documents / Downloads.
- **Security-Scoped Bookmarks**: `BookmarkManager` persists user-selected folders so access is restored on relaunch. Auto-entitled paths (`~/Desktop`, `~/Documents`, `~/Downloads`) are tracked separately and don't consume bookmark slots.
- **Login Item**: handled by `LaunchAtLoginManager` via `SMAppService.mainApp` — no helper bundle, no extra entitlements. Approval may be required in System Settings → General → Login Items.

---

## Privacy

- 100% local. The index, recent files list, and preferences live entirely on your Mac.
- No analytics, no network calls beyond opening external help URLs you click.
- `ITSAppUsesNonExemptEncryption` is `false`.

---

## Project status

Early-stage but functional. Recent commits:

- `297d5f8` 优化
- `18198e5` 快捷键
- `fc6a7b8` icon
- `f9f188a` 修复无法搜索的 bug
- `75da8bf` Initial commit: MCFinder macOS file search app

Known rough edges and ideas live in the source comments — search for `// TODO` / `// Logger.app.error`.

---

## License

Copyright © 2026 MCFinder. All rights reserved.

(No open-source license has been chosen yet — please open an issue if you intend to redistribute.)
