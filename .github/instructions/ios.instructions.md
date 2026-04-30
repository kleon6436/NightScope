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

## Project Overview

- **Project Name**: NightScope
- **Overview**: A macOS and iPhone app that aggregates observation site, weather, light pollution, and celestial information to help users determine the best time for stargazing.
- **Target Platform**: iOS 18.0+
- **Supported Devices**: iPhone only
- **Minimum Deployment Target**: iOS 18.0
- **Repository Structure**: Single repo. The macOS target (`NightScope/`) and iOS target (`NightScopeiOS/`) are managed in the same Xcode project. Source is organized under `Controllers / Models / Data / ViewModels / Views`.

## Tech Stack

### Recommended

| Category | Technology / Tool | Version | Notes |
|---------|-------------|-----------|------|
| Language | Swift | 6 | |
| IDE | Xcode | 26 | |
| Package Manager | Swift Package Manager | | |
| UI Framework | SwiftUI | iOS 18+ SDK | Minimize mixing with UIKit |
| UI Framework (Supplementary) | UIKit | | Only when SwiftUI is insufficient |
| Architecture | MVC | | Controllers / Models / ViewModels / Views |
| Testing | XCTest / Swift Testing | | Both frameworks can be used together |
| Linter / Formatter | SwiftLint | Latest | Configuration not currently present in the repository |
| Icon Creation | Icon Composer | Built into Xcode 26 | Create layered icons |
| CI/CD | — | | Not configured |

## Recommended Copilot Agent Configuration

- When working with multiple agents, use `agents/orchestrator.agent.md` as the central coordinator.
- Use `agents/product-manager.agent.md` for requirements clarification, `agents/architect.agent.md` for technical design, and `agents/developer.agent.md` for implementation.
- For UI changes including Liquid Glass support, use `agents/ui-designer.agent.md` in conjunction to finalize screen states, visual hierarchy, and accessibility first.
- Run final quality gates through `agents/reviewer.agent.md` and `agents/tester.agent.md`.

## UI Guidelines

For UI design and implementation on iOS / iPadOS (HIG, Liquid Glass, navigation, size classes, Dynamic Type, icons, etc.), refer to the following skills:

- `skills/apple-ui-guidelines/SKILL.md` — Apple Platform UI Guidelines (iOS / iPadOS / macOS common)
- `skills/ui-accessibility/SKILL.md` — Common accessibility principles
- `skills/ui-review-checklist/SKILL.md` — Checklist for UI review


## Coding Standards

For Swift coding standards, refer to `skills/swift-coding-standards/SKILL.md`.
