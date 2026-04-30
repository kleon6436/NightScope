# Project Guidelines

## Assumptions

- When making code changes that are likely to exceed 200 lines, first ask the user: "This instruction may result in changes exceeding 200 lines. Do you want to proceed?"
- Before making any large changes, plan what to do first, then propose to the user: "Here is the plan I'd like to follow."
- Think before you write
- Prefer simplicity
- Only touch what is necessary
- Work toward goals
- After changes, always perform code review and testing

## Project Overview

- **Project Name**: NightScope
- **Overview**: A macOS and iPhone app that aggregates observation site, weather, light pollution, and celestial information to help users determine the best time for stargazing.
- **Target Platform**: macOS 15.0 (Sequoia) / iOS 18.0+ (iPhone)
- **Repository Structure**: Single repo. macOS target (`NightScope/`) and iOS target (`NightScopeiOS/`) are managed in the same Xcode project. Source is organized under `Controllers / Models / Data / ViewModels / Views`.

## Tech Stack

| Category | Technology / Tool | Version | Notes |
|---------|-------------|-----------|------|
| Language | Swift | 6 | |
| IDE | Xcode | 26 | |
| Package Manager | Swift Package Manager | | |
| UI Framework | SwiftUI | macOS 15+ / iOS 18+ SDK | Minimize mixing with AppKit / UIKit |
| Architecture | MVC | | Controllers / Models / ViewModels / Views |
| Testing | XCTest / Swift Testing | | Both frameworks may be used |
| Linter / Formatter | SwiftLint | latest | Configuration not currently present in the repository |
| Icon Creation | Icon Composer | Built into Xcode 26 | Layered icon structure |
| CI/CD | — | | Not configured |

## External Data Sources

| Data Source | Purpose | License | How to Obtain |
|---|---|---|---|
| Apple WeatherKit | Weather forecast | Apple Developer Program Terms | System framework |
| Falchi et al. 2016 World Atlas | Light pollution map | CC BY 4.0 | Bundled binary (`bortle_map.bin`) |
| NASA SRTM | Terrain / elevation | Public Domain | Bundled binary (`srtm_elevation.bin`) |
| Yale Bright Star Catalogue (BSC5) | Star catalogue | Public Domain | Bundled JSON (`stars_fill.json`) |
| Apple MapKit | Reverse geocoding | Apple Developer Program Terms | System framework |

When modifying or adding external data sources, always verify license terms (especially the attribution requirement of CC BY 4.0).

## Project Structure

```
NightScope/                        # macOS main target
├── Controllers/                   # External API fetching & calculation logic
├── Models/                        # Domain models
├── Data/                          # Bundled JSON / binary data
├── ViewModels/                    # Presentation logic
├── Views/                         # SwiftUI views
├── Assets.xcassets/
├── NightScope.entitlements
└── NightScopeApp.swift
NightScopeiOS/                     # iOS target
NightScopeTests/                   # Unit tests
Tools/                             # Bundle data generation scripts (Python)
```

## Build Commands

```bash
# macOS build
xcodebuild -quiet -project NightScope.xcodeproj -scheme NightScope \
  -destination 'platform=macOS' build

# macOS test
xcodebuild -quiet -project NightScope.xcodeproj -scheme NightScope \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO test

# iOS (Simulator) build
xcodebuild -quiet -project NightScope.xcodeproj -target NightScopeiOS \
  -sdk iphonesimulator -configuration Debug \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

## Recommended Copilot Agent Configuration

- When using the orchestration pattern, use the templates under `agents/`.
- Use `agents/sisyphus.agent.md` as the central entry point and delegate to specialist agents based on task type.
- Handle small tasks and typo fixes with `sisyphus-junior` to save high-cost model usage.
- Always plan with `prometheus` and run `metis` gap analysis before implementing.
- Always have important changes reviewed by `momus`.

### Agent List (10 agents)

**Discipline Layer**

| Agent | Model | Primary Responsibilities |
|-------|--------|------|
| `sisyphus` | Claude Sonnet 4.6 | Main orchestrator. Intent analysis, delegation, verification, integration, BOULDER.md management |
| `sisyphus-junior` | GPT-5 mini | Lightweight orchestrator. Dedicated to typos, single-line changes, and small tasks |
| `prometheus` | Claude Sonnet 4.6 | Strategic planner. Requirements gathering, acceptance criteria, plan creation. Does not write code |
| `hephaestus` | GPT-5.3-Codex | Autonomous deep worker. Self-contained explore→plan→execute→verify cycle. Explicit activation only |

**Specialized Layer**

| Agent | Model | Primary Responsibilities |
|-------|--------|------|
| `oracle` | GPT-5.4 | Top-level consultant. Complex debugging, architecture decisions. Explicit activation only when the path forward is unclear |
| `librarian` | GPT-5 mini | Evidence-based researcher. Official docs, GitHub examples. URL/permalink required |
| `explore` | Grok Code Fast 1 | Fast codebase scanner. Parallel activation allowed. Read-only |
| `metis` | GPT-5.4 mini | Plan consultant. Catches ambiguity, gaps, and incorrect assumptions in the planning phase |
| `momus` | GPT-5.4 | Relentless verifier. Comprehensive code review, test quality, security (OWASP Top 10) |
| `atlas` | GPT-5.4 mini | Implementer. Executes verified plans. Also handles CI/CD and deployment |

### Category Quick Reference

| Category | Example Tasks | Recommended Agent | Recommended Model |
|---------|---------|-----------|----------|
| quick | typo, single-line fix, config value change | `sisyphus-junior` | GPT-5 mini |
| plan | requirements, planning, acceptance criteria | `prometheus` | Claude Sonnet 4.6 |
| deep | autonomous large-scale implementation | `hephaestus` | GPT-5.3-Codex |
| ultrabrain | architecture decisions, complex debugging | `oracle` | GPT-5.4 |
| writing | documentation, research, cited answers | `librarian` | GPT-5 mini |
| search | codebase grep, dependency analysis | `explore` | Grok Code Fast 1 |
| review | code quality, testing, security | `momus` | GPT-5.4 |
| implement | implementation, fixes, CI/CD | `atlas` | GPT-5.4 mini |
| visual-engineering | UI/UX, accessibility | `atlas` (using Gemini 3.1 Pro) | Gemini 3.1 Pro |

### Model Cost Policy

- **High cost (evaluate each time)**: Claude Sonnet 4.6 / GPT-5.4 / GPT-5.3-Codex — limit to complex reasoning, critical design decisions, and large-scale implementation
- **Medium cost (use actively)**: GPT-5.4 mini / Gemini 3.1 Pro — planning assistance, implementation, visual tasks
- **Low cost (use freely)**: GPT-5 mini / Grok Code Fast 1 — small tasks, search, research

> `atlas` uses GPT-5.4 mini for lighter cases; consider switching to Claude Sonnet 4.6 for large-scale refactoring or implementations that must closely follow existing conventions.

### BOULDER.md Protocol

For session continuity, `sisyphus` manages `BOULDER.md` in the project root.

```markdown
# Boulder - Session State
Last Updated: {datetime}
Task: {task summary}

## Completed ✅
- [x] ...

## In Progress 🔄
- [ ] ...

## On Hold / Blockers
- ...

## Handoff Notes
{Important information and decision rationale for the next session}
```

- **Session start**: `sisyphus` reads `BOULDER.md` to understand incomplete tasks before starting work
- **After each major step**: Update Completed / In Progress / On Hold
- **Session end**: Record remaining tasks and handoff notes before closing

## Platform-Specific Guidelines

For detailed development guidelines per platform, refer to the following instruction files.

| Platform | Instruction File |
|--------------|-------------|
| iOS / iPadOS | `instructions/ios.instructions.md` |
| macOS | `instructions/macos.instructions.md` |

## Skills List

| Category | Skills |
|---------|-------|
| **Coding Standards** | `swift-coding-standards` |
| **UI / UX** | `apple-ui-guidelines` / `ui-accessibility` / `ui-review-checklist` / `design-system` |
| **Quality & Security** | `security-practices` / `cicd-deployment` / `performance-optimization` / `apple-app-store-submission` |
| **Internationalization** | `i18n-localization` |
