---
description: "Development guidelines for Apple macOS apps"
applyTo: []
---

# Project Guidelines (macOS Tahoe App Development)

## Recommended Copilot Agent Configuration

- Use `sisyphus` as the main orchestrator. All tasks start here.
- Use `prometheus` for requirements gathering and plan creation before writing any code.
- Run `metis` gap analysis and `momus` review on all plans and implementations.
- For UI work involving HIG / Liquid Glass considerations, pass as a visual-engineering task to `atlas` (using Gemini 3.1 Pro).
- For security-related changes (auth, Keychain, data handling), route reviews through `momus-deep`.

## UI Guidelines

For UI design and implementation on macOS (HIG, Liquid Glass, windows, navigation, keyboard shortcuts, icons, etc.), refer to the following skills:

- `skills/apple-ui-guidelines/SKILL.md` — Apple Platform UI Guidelines (iOS / iPadOS / macOS common)
- `skills/ui-accessibility/SKILL.md` — Common accessibility principles
- `skills/ui-review-checklist/SKILL.md` — Checklist for UI review


## Coding Standards

For Swift coding standards, refer to `skills/swift-coding-standards/SKILL.md`.
