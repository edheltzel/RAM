# RAM (app sources)

## Purpose

SwiftUI macOS menu-bar app: live memory chip, popup process list, sampling, and preferences.

## Ownership

- `RAMApp.swift`, `PopupView.swift`, `Store.swift`, `Models.swift`
- `MemoryMonitor.swift`, `ProcessSampler.swift`, `Grouping.swift`
- `ActivityMonitorOpener.swift`, `LaunchAtLogin.swift`

## Local Contracts

- Menu extra + popup only; keep the surface tiny.
- Domain vocabulary follows `docs/agents/domain.md` / `CONTEXT.md` when present.
- Do not invent synonyms for glossary terms.

## Work Guidance

Prefer small, focused Swift files. Match existing naming and Store-driven UI updates.

## Verification


## Child DOX Index

None.
