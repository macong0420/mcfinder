# Repository Guidelines

## Project Structure & Module Organization
`MCFinder/` contains all app source code, split by responsibility:
- `App/` app lifecycle and shared state (`MCFinderApp`, `AppDelegate`, `AppState`).
- `Database/`, `Index/`, `Monitoring/`, `Search/` core indexing and query pipeline.
- `QuickSearch/`, `Hotkeys/`, `Preview/`, `Views/` UI and interaction features.
- `Bookmarks/`, `Utilities/` sandbox access and shared helpers.
- `Resources/` app assets, entitlements, and `Info.plist`.

Project configuration is in `MCFinder.xcodeproj/`. Build outputs may appear in `build/` and should not be manually edited.

## Build, Test, and Development Commands
- `open MCFinder.xcodeproj`  
  Open the project in Xcode for interactive development.
- `xcodebuild -project MCFinder.xcodeproj -scheme MCFinder -configuration Debug build`  
  CLI build for local verification.
- `xcodebuild -project MCFinder.xcodeproj -scheme MCFinder -configuration Release build`  
  Release build check before shipping.
- `xcodebuild -project MCFinder.xcodeproj -scheme MCFinder clean`  
  Clean derived artifacts when diagnosing build issues.

## Coding Style & Naming Conventions
- Language: Swift 5.9+ (Xcode 15+), SwiftUI + AppKit interop.
- Indentation: 4 spaces; keep one primary type per file.
- Types: `UpperCamelCase` (`SearchEngine`), methods/properties: `lowerCamelCase` (`startScan`).
- Prefer small, focused extensions in `Utilities/Extensions.swift` and feature-specific logic in the matching module folder.
- Keep comments high-signal: explain invariants, threading, sandbox behavior, or non-obvious API constraints.

## Testing Guidelines
There is currently no separate XCTest target in this repository. Before opening a PR:
- Run a Debug and Release build via Xcode or `xcodebuild`.
- Manually validate key flows: add indexed folder, incremental updates, quick search hotkey, and Quick Look toggle.
- If you add complex logic, include an implementation note in the PR and consider adding a test target in the same change or a follow-up.

## Commit & Pull Request Guidelines
Recent history uses short, direct commit subjects (often Chinese), e.g. `修复无法搜索的 bug`, `快捷键`. Follow this style:
- One-line subject, specific and scoped to a single change.
- Prefer actionable wording (what changed, not why only).

PRs should include:
- Change summary and affected modules (for example `Search/`, `Database/`).
- Manual verification steps and outcomes.
- Screenshots or recordings for UI-visible changes.
- Linked issue/task when applicable.
