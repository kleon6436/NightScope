# Project Guidelines

## Assumptions

- When making code changes that are likely to exceed 200 lines, first ask the user: "This instruction may result in changes exceeding 200 lines. Do you want to proceed?"
- Before making any large changes, plan what to do first, then propose to the user: "Here is the plan I'd like to follow."
- Think before you write
- Prefer simplicity
- Only touch what is necessary
- Work toward goals
- After changes, always perform code review and testing

## Agent Autonomy Principle

Agents are expected to act **autonomously**, not under micromanagement. Agent instructions describe the agent's **role, judgment criteria, and quality bar** — not a step-by-step script. Each agent is trusted to:

- Decide which phases / steps are actually needed for the task at hand and skip the rest
- Choose its own tools, depth of exploration, and output structure
- Escalate or hand off only when the situation genuinely calls for it — not as a ritual
- Treat templates and checklists in this repo as **defaults to deviate from when judgment dictates**, not mandatory gates

Do not pad output with mandatory phase headers, restated checklists, or ceremonial confirmations when they add no value. Do the work, deliver the result.

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
- For non-trivial changes, planning (`prometheus`) and review (`momus` / `momus-deep`) are the default — the orchestrator may skip them when the task clearly does not warrant the overhead.
- `metis` / `metis-deep` gap analysis is recommended for risky or cross-cutting plans, not required for every plan.

### Agent List (12 agents)

**Discipline Layer**

| Agent | Model | Primary Responsibilities |
|-------|--------|------|
| `sisyphus` | Claude Sonnet 4.6 | Main orchestrator. Intent analysis, delegation, verification, integration, BOULDER.md management |
| `sisyphus-junior` | GPT-5 mini | Lightweight orchestrator. Dedicated to typos, single-line changes, and small tasks |
| `prometheus` | GPT-5.4 mini | Strategic planner. Requirements gathering, acceptance criteria, plan creation. Does not write code |
| `hephaestus` | GPT-5.3-Codex | Autonomous deep worker. Self-contained explore→plan→execute→verify cycle. Explicit activation only |

**Specialized Layer**

| Agent | Model | Primary Responsibilities |
|-------|--------|------|
| `oracle` | GPT-5.4 | Top-level consultant. Complex debugging, architecture decisions. Explicit activation only when the path forward is unclear |
| `librarian` | GPT-5 mini | Evidence-based researcher. Official docs, GitHub examples. URL/permalink required |
| `explore` | GPT-5 mini | Fast codebase scanner. Parallel activation allowed. Read-only |
| `metis` | GPT-5.4 mini | Plan consultant. Catches ambiguity, gaps, and incorrect assumptions in the planning phase |
| `metis-deep` | GPT-5.4 | Deep plan consultant. For plans spanning multiple services, data model changes, security constraints, migration/rollback strategy, or 3+ open questions |
| `momus` | GPT-5.4 mini | Relentless verifier. Comprehensive code review, test quality, security (OWASP Top 10) |
| `momus-deep` | GPT-5.4 | Security-focused verifier. For changes touching auth, data deletion, external input, concurrency, or secrets |
| `atlas` | GPT-5.4 mini | Implementer. Executes verified plans. Also handles CI/CD and deployment |

### Category Quick Reference

| Category | Example Tasks | Recommended Agent | Recommended Model |
|---------|---------|-----------|----------|
| quick | typo, single-line fix, config value change | `sisyphus-junior` | GPT-5 mini |
| plan | requirements, planning, acceptance criteria | `prometheus` | GPT-5.4 mini |
| deep | autonomous large-scale implementation | `hephaestus` | GPT-5.3-Codex |
| ultrabrain | architecture decisions, complex debugging | `oracle` | GPT-5.4 |
| writing | documentation, research, cited answers | `librarian` | GPT-5 mini |
| search | codebase grep, dependency analysis | `explore` | GPT-5 mini |
| plan-review | plan gap analysis (standard) | `metis` | GPT-5.4 mini |
| plan-review-deep | plan gap analysis (multi-service / data model / security / rollout) | `metis-deep` | GPT-5.4 |
| review | code quality, testing, security | `momus` | GPT-5.4 mini |
| review-deep | security-sensitive changes (auth / data deletion / external input / concurrency / secrets) | `momus-deep` | GPT-5.4 |
| implement | implementation, fixes, CI/CD | `atlas` | GPT-5.4 mini |
| visual-engineering | UI/UX, accessibility | `atlas` (using Gemini 3.1 Pro) | Gemini 3.1 Pro |

### Model Cost Policy

- **High cost (evaluate each time)**: Claude Sonnet 4.6 / GPT-5.4 / GPT-5.3-Codex — limit to complex reasoning, critical design decisions, and large-scale implementation
- **Medium cost (use actively)**: GPT-5.4 mini / Gemini 3.1 Pro — planning assistance, implementation, visual tasks
- **Low cost (use freely)**: GPT-5 mini — small tasks, search, research

> `atlas` uses GPT-5.4 mini for lighter cases; consider switching to Claude Sonnet 4.6 for large-scale refactoring or implementations that must closely follow existing conventions.

### BOULDER.md Protocol

When session continuity matters — multi-session work, complex handoffs, or explicit user request — `sisyphus` may manage `BOULDER.md` in the project root. For one-shot tasks, skip it.

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

- **When BOULDER is in use — session start**: read `BOULDER.md` to understand incomplete tasks before starting work
- **When BOULDER is in use — state changes materially**: update Completed / In Progress / On Hold / Handoff Notes
- **When BOULDER is not in use**: do not create or mention it ceremonially

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
| **Engineering Discipline** | `senior-engineer-standard` |
| **Internationalization** | `i18n-localization` |
