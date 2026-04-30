---
description: "Development guidelines for Apple macOS apps"
applyTo: []
---

# Project Guidelines (macOS Tahoe App Development)

## Project Overview

- **Project Name**: NightScope
- **Overview**: A macOS and iPhone app that aggregates observation site, weather, light pollution, and celestial information to help users determine the best time for stargazing.
- **Target Platform**: macOS 15.0 (Sequoia) or later
- **Minimum Deployment Target**: macOS 15.0
- **Repository Structure**: Single repo. The macOS target (`NightScope/`) and iOS target (`NightScopeiOS/`) are managed in the same Xcode project. Source is organized under `Controllers / Models / Data / ViewModels / Views`.

## Tech Stack

| Category | Technology / Tool | Version | Notes |
|---------|-------------|-----------|------|
| Language | Swift | 6 | |
| IDE | Xcode | 26 | |
| Package Manager | Swift Package Manager | | |
| UI Framework | SwiftUI | macOS 15+ SDK | Minimize mixing with AppKit |
| Architecture | MVC | | Controllers / Models / ViewModels / Views |
| Testing | XCTest / Swift Testing | | Both frameworks can be used together |
| Linter / Formatter | SwiftLint | Latest | Configuration not currently present in the repository |
| Icon Creation | Icon Composer | Built into Xcode 26 | Create layered icons |
| CI/CD | — | | Not configured |

## Recommended Copilot Agent Configuration

- When working with multiple agents, use `agents/orchestrator.agent.md` as the starting point.
- Use `agents/product-manager.agent.md` for requirements clarification, `agents/architect.agent.md` for technical design, and `agents/developer.agent.md` for implementation.
- For UI work involving HIG / Liquid Glass considerations, use `agents/ui-designer.agent.md` in conjunction to finalize information architecture and accessibility early.
- After implementation, use `agents/reviewer.agent.md` and `agents/tester.agent.md` as quality gates.

## UI Guidelines

For UI design and implementation on macOS (HIG, Liquid Glass, windows, navigation, keyboard shortcuts, icons, etc.), refer to the following skills:

- `skills/apple-ui-guidelines/SKILL.md` — Apple Platform UI Guidelines (iOS / iPadOS / macOS common)
- `skills/ui-accessibility/SKILL.md` — Common accessibility principles
- `skills/ui-review-checklist/SKILL.md` — Checklist for UI review


## Coding Standards

For Swift coding standards, refer to `skills/swift-coding-standards/SKILL.md`.
