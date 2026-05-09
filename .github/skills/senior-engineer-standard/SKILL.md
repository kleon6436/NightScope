---
name: senior-engineer-standard
description: 'The code quality charter every coding and review agent must apply. Use when: implementing, refactoring, or reviewing code. Defines the bar that makes agent-written code indistinguishable from a senior engineer''s.'
argument-hint: 'Principle to focus on (optional): patterns | errors | tests | slop | comments'
---

# Senior-Engineer Code Quality Charter

Code written by an agent must be indistinguishable from code written by a senior engineer. This skill is the single source of truth for that bar. Implementer agents apply it; reviewer agents verify it.

---

## The 5 Principles

1. **Follow existing patterns and architecture.** Match the conventions, layering, naming, and idioms already established in the codebase. Reuse existing helpers, abstractions, and error types before introducing new ones.
2. **Implement proper error handling and edge cases.** Validate at boundaries. Surface failures meaningfully. Cover empty / null / boundary / concurrent / failure-mode inputs.
3. **Write tests that verify real behavior, not just coverage.** Assert observable outcomes. Cover the contract — happy path, abnormal path, boundaries — not just lines executed.
4. **No AI slop. Clean, concise, maintainable code.** Every line earns its place. No filler, no speculative abstraction, no scaffolding for needs that don't exist.
5. **Comment only when comments add value; never state the obvious.** Explain *why*, not *what*. If the code already says it, the comment is noise.

---

## Per-Principle Rules

### 1. Follow Existing Patterns

**Do**
- Read neighboring files before writing; mirror their structure and naming.
- Reuse existing utilities, error types, logging, DI/config wiring.
- Place new code where similar concerns already live.

**Don't**
- Introduce a new pattern when an existing one fits.
- Rename, restyle, or "modernize" code outside the requested scope.
- Add a new dependency when the codebase already solves the problem.

### 2. Error Handling and Edge Cases

**Do**
- Validate inputs at system boundaries (API, IO, IPC, user input).
- Propagate errors with enough context to diagnose them.
- Enumerate edge cases explicitly: empty, null/undefined, zero, negative, max size, concurrent access, partial failure, timeout, cancellation.

**Don't**
- Catch-and-swallow exceptions to silence them.
- Re-throw with no added context, or wrap a typed error in a generic one.
- Add validation for impossible states or scenarios that can't occur.

### 3. Tests That Verify Behavior

**Do**
- Assert on the observable outcome users / callers depend on.
- Cover happy, abnormal, and boundary paths from the requirement.
- Make tests deterministic; use fakes/fixtures over wide mocks.

**Don't**
- Assert that a mock was called as the primary verification.
- Write a test that passes regardless of whether the bug is fixed.
- Pad coverage with redundant or trivially-true assertions.

### 4. No AI Slop

**Do**
- Delete code paths that aren't reached.
- Keep functions small, named for what they actually do, and located where they belong.
- Prefer clarity over cleverness; prefer reusing existing abstractions over inventing new ones.

**Don't (AI-Slop Anti-Pattern Catalog)**
- Defensive `try/except` (or `try/catch`) that swallows or rethrows-as-generic — hides real failures.
- Comments that restate the next line in English.
- Speculative abstractions, "future-proof" parameters, or unused options.
- Helper functions used exactly once that don't aid readability.
- Re-implementing functionality that already exists in the codebase or stdlib.
- Test assertions that mirror the implementation step-by-step (`expect(mock).toHaveBeenCalled` as the only assertion).
- Docstrings that paraphrase the function signature.
- Dead branches (`if False:`, unreachable `else`, configuration that has no consumer).
- "While we're at it" refactors, formatting churn, and import reorders unrelated to the task.
- Boilerplate scaffolding (interfaces with one impl, factories with one product) introduced without a real second case.

### 5. Comments That Add Value

**Do**
- Explain non-obvious *why*: trade-off chosen, invariant relied on, external constraint, link to spec/issue.
- Mark intentional surprises (`// intentional: legacy contract requires …`).

**Don't**
- Restate the code (`// increment counter` above `counter++`).
- Add docstrings that just echo the parameter names.
- Leave TODO/FIXME without owner or context.

---

## Implementer Self-Check (apply before declaring done)

- [ ] My change matches the existing patterns I read in neighboring files.
- [ ] Boundary inputs and failure modes are handled, not assumed away.
- [ ] Tests assert observable behavior tied to the acceptance criteria.
- [ ] Every line I added is necessary; no speculative scaffolding remains.
- [ ] Every comment I added explains *why*; obvious comments are removed.
- [ ] I made no out-of-scope edits.

## Reviewer Check (apply during code review)

- [ ] Pattern fidelity: does this match how the rest of the codebase does it? Are existing helpers reused?
- [ ] Error & edge cases: boundary inputs, failure modes, concurrency — handled or consciously deferred?
- [ ] Test quality: do tests fail when behavior breaks? Or only when implementation shape changes?
- [ ] AI slop: any anti-patterns from the catalog above present?
- [ ] Comments: every comment earns its place; nothing restates the code.

Reviewers should fold findings into the existing priority labels (`[must]` / `[imo]` / `[nits]` / `[good]`); slop and comment noise typically map to `[must]` or `[imo]` depending on impact.
