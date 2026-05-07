---
description: "Development guidelines for Apple iOS and iPadOS apps"
applyTo: []
---

# Project Guidelines (iOS / iPadOS App Development)

## Assumptions

- Instructions tagged with **[iPhone only]**, **[iPad only]**, or **[Universal only]** in each section should be handled according to the "Supported Devices" setting as follows:
  - **"iPhone only"**: Ignore instructions tagged [iPad only] and [Universal only]
  - **"iPad only"**: Ignore instructions tagged [iPhone only] and [Universal only]
  - **"Universal"**: Apply all instructions regardless of tags

## Recommended Copilot Agent Configuration

- Use `sisyphus` as the main orchestrator. All tasks start here.
- Use `prometheus` for requirements gathering and plan creation before writing any code.
- Run `metis` gap analysis and `momus` review on all plans and implementations.
- For UI changes including Liquid Glass support, pass as a visual-engineering task to `atlas` (using Gemini 3.1 Pro).
- For security-related changes (auth, Keychain, data handling), route reviews through `momus-deep`.

## UI Guidelines

For UI design and implementation on iOS / iPadOS (HIG, Liquid Glass, navigation, size classes, Dynamic Type, icons, etc.), refer to the following skills:

- `skills/apple-ui-guidelines/SKILL.md` — Apple Platform UI Guidelines (iOS / iPadOS / macOS common)
- `skills/ui-accessibility/SKILL.md` — Common accessibility principles
- `skills/ui-review-checklist/SKILL.md` — Checklist for UI review


## Coding Standards

For Swift coding standards, refer to `skills/swift-coding-standards/SKILL.md`.
