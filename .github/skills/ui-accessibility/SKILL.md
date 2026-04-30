---
name: ui-accessibility
description: 'Cross-platform UI accessibility principles. Use to review and apply WCAG 2.2 AA, contrast ratios, focus order, screen readers (VoiceOver / TalkBack / Narrator / NVDA / JAWS), keyboard operation, Reduce Motion, and respecting user settings. Use when: reviewing UI accessibility across any platform; applying WCAG; designing inclusive experiences.'
argument-hint: 'Item to review (contrast / focus / screen reader, etc. — optional)'
---

# UI Accessibility Guidelines (Cross-Platform Common)

## Overview

This skill defines common principles for ensuring UI accessibility regardless of platform.
For platform-specific implementation details, refer to the respective UI skills (`apple-ui-guidelines` / `windows-ui-guidelines` / `web-ui-guidelines` / `android-ui-guidelines`).

References:
- [WCAG 2.2](https://www.w3.org/TR/WCAG22/)
- [Inclusive Design Principles](https://inclusivedesignprinciples.org/)

---

## 1. The 4 Principles (POUR)

The foundational principles of WCAG. All UI decisions should be evaluated against these four.

| Principle | Meaning |
|---|---|
| **Perceivable** | Information is presented in a form that users can perceive (visual, auditory, or tactile) |
| **Operable** | The UI can be operated by any input method (keyboard, mouse, touch, voice) |
| **Understandable** | Information and methods of operation are understandable to users |
| **Robust** | Content can be reliably interpreted by a wide range of assistive technologies |

---

## 2. Contrast

WCAG AA criteria:

| Target | Normal | Large Text (18pt / 14pt bold) | Non-text (icons, borders) |
|---|---|---|---|
| Contrast ratio | **4.5:1** | **3:1** | **3:1** |

For AAA, aim for **7:1 / 4.5:1**.

### Implementation Notes

- Placeholder text must also meet the same contrast requirements as body text. Excessively faint placeholders are not acceptable.
- Disabled states may be **relaxed as an exception**, but do not hide important information with a disabled state.
- Focus indicators must have a contrast of **3:1 or more** against the background.
- Tools: [WebAIM Contrast Checker](https://webaim.org/resources/contrastchecker/) / Figma Contrast plugin / Xcode Accessibility Inspector / Chrome DevTools.

### Don’t Rely on Color Alone

Convey information with cues beyond color (icons, text, patterns):

- Error: red **+ icon + text**
- Link: color **+ underline**
- Required field: color **+ “*” + `aria-required`**
- Selected state: background color **+ checkmark**

---

## 3. Touch Target Size

| Platform | Minimum Recommended |
|---|---|
| Web (WCAG 2.5.5 AA) | **24×24 CSS px** (minimum) / **44×44 recommended** |
| iOS / iPadOS | **44×44 pt** |
| Android | **48×48 dp** |
| Windows | **40×40 px** (48×48 recommended for touch) |

- Ensure at least **8px** of space between adjacent targets.
- Even if the visual size is small, enlarging the hit area (`hitSlop` / padding) is acceptable.

---

## 4. Keyboard Operation

### Requirements

- **All interactive elements must be reachable and operable by keyboard alone** (WCAG 2.1.1).
- **Do not create keyboard traps** (WCAG 2.1.2). Focus must be able to leave every element.
- **Logical operation order** (WCAG 2.4.3). Align with DOM / visual order.

### Standard Shortcuts

| Action | Key |
|---|---|
| Move to next element | `Tab` |
| Move to previous element | `Shift + Tab` |
| Activate button | `Space` / `Enter` |
| Follow link | `Enter` |
| Toggle checkbox | `Space` |
| Expand dropdown | `Space` / `Enter` / Arrow keys |
| Close modal | `Esc` |
| Navigate list | Arrow keys |

### Focus Indicators

- **Do not remove focus rings** (prohibit `:focus { outline: none }`).
- On the Web, use `:focus-visible` to hide the ring only on mouse click.
- Respect the platform's native focus ring; when replacing it, ensure visibility (3:1 or more).

---

## 5. Screen Reader Support

### Major Screen Readers

| Platform | Screen Reader |
|---|---|
| iOS / iPadOS | **VoiceOver** |
| macOS | **VoiceOver** |
| Android | **TalkBack** |
| Windows | **Narrator** / **NVDA** / **JAWS** |
| Web | All supported (browser + SR) |

### Common Requirements

- Provide an **accessible name** for every interactive element:
  - Web: `<button>Delete</button>` / `aria-label="Delete"`
  - iOS: `.accessibilityLabel("Delete")`
  - Android: `contentDescription = "Delete"`
  - Windows: `AutomationProperties.Name="Delete"`
- Icon-only buttons must always have a label.
- Decorative images/icons must be **hidden** from assistive technologies:
  - Web: `aria-hidden="true"` / `alt=""`
  - iOS: `.accessibilityHidden(true)`
  - Android: `contentDescription = null`
- Announce state changes via **live regions** (read aloud):
  - Web: `aria-live="polite"` / `role="status"`
  - iOS: `AccessibilityNotification.Announcement`
  - Android: `Modifier.semantics { liveRegion = LiveRegionMode.Polite }`

### Correct Semantics Representation

- **Role**: Explicitly declare the true role — button / link / checkbox / radio, etc.
- **State**: Provide selected, expanded, disabled, pressed, etc. via `aria-expanded` / `aria-selected` / `aria-pressed`, etc.
- **Property**: Related elements (`aria-describedby` / `aria-labelledby`), required state (`aria-required`).

---

## 6. Text & Readability

- **Line length**: **45–75 characters** per line (approx. 30–40 for Japanese).
- **Line spacing**: **1.5× or more** for body text (WCAG 1.4.12).
- **Paragraph spacing**: **2×** the line spacing or more.
- **Text resize**: Content and functionality must not be lost when text is enlarged up to 200% (WCAG 1.4.4).
- **Reflow**: Displayable without horizontal scrolling at **320 CSS px** width (WCAG 1.4.10).
- **Avoid images of text** (except logos). Represent content with real text.
- Text spacing must not break layout when line length, letter spacing, line height, and paragraph spacing are adjusted by the user (WCAG 1.4.12).

---

## 7. Reduce Motion

When a user has enabled "Reduce Motion", minimize animations:

| Platform | API |
|---|---|
| Web | `@media (prefers-reduced-motion: reduce)` |
| iOS | `@Environment(\.accessibilityReduceMotion)` |
| Android | `Settings.Global.ANIMATOR_DURATION_SCALE` / `AccessibilityManager` |
| Windows | `UISettings.AnimationsEnabled` |

Guidelines:
- Stop or simplify parallax effects, infinite loops, autoplay, and flashing.
- Replace necessary feedback with gentle transitions such as fades.
- **Autoplay content** (video, carousels) must always provide a way to pause.
- **Prohibit flashing more than 3 times per second** (photosensitive seizure prevention, WCAG 2.3.1).

---

## 8. Reduce Transparency / High Contrast

- **Reduce Transparency**: Provide fallbacks for semi-transparent backgrounds (Liquid Glass / Acrylic / frosted glass).
  - iOS/macOS: `@Environment(\.accessibilityReduceTransparency)`
  - Windows: System Backdrop adjusts automatically
  - Web: `@media (prefers-reduced-transparency: reduce)`
- **High Contrast / Increased Contrast**:
  - iOS/macOS: `@Environment(\.colorSchemeContrast)` / Increased Contrast variants in Assets
  - Windows: Use `SystemColor*Brush` in **High Contrast themes**
  - Web: `@media (prefers-contrast: more)` / `forced-colors: active`

---

## 9. Form Accessibility

- Associate a **visible label** with every input (`<label for>` / `.accessibilityLabel` / `ContentDescription`).
- **Error messages**:
  - Be explicit about the error (e.g., “Email address does not contain @” rather than “Input error”)
  - Indicate the error location (`aria-describedby` / `accessibilityHint`)
  - Provide a suggestion for correction
- Indicate **required fields** both visually and to assistive technologies (`aria-required="true"` / `required`).
- Configure **autocomplete / autofill** appropriately (WCAG 1.3.5).
- Also announce success messages via live regions.

---

## 10. Images & Media

### Alternative Text

- **Informative images**: Provide a concise `alt` / `accessibilityLabel` describing the content.
- **Decorative images**: `alt=""` / `accessibilityHidden`.
- **Functional images** (linked images, button images): Text describing the function.
- **Complex images** (diagrams, charts): Short alt + long description (`aria-describedby` / nearby text).

### Video & Audio

- **Captions**: Required for videos with audio content (WCAG 1.2.2).
- **Audio Description**: Verbal description of visual information (WCAG 1.2.5).
- **Transcript**: Text version of audio content.
- Autoplay must be muted, with a clear way to stop.

---

## 11. Language & Localization

- Declare the document language (`<html lang="en">` / `UIAccessibility.announceLanguage`).
- Use `lang` attributes for inline content in a different language (informs the SR about pronunciation).
- Format dates, numbers, and currencies according to the locale (`Intl` / `NumberFormatter`).

---

## 12. Timeouts

- If a timeout is present, offer the user at least one of the following: **extend, disable, or restart** (WCAG 2.2.1).
- Sessions within **20 hours** should be maintainable.
- Auto-refresh and redirects must be stoppable by the user.

---

## 13. Testing & Validation

### Automated Testing

| Tool | Target |
|---|---|
| **axe DevTools** | Web |
| **Lighthouse** | Web |
| **WAVE** | Web |
| **Accessibility Inspector** (Xcode) | iOS / macOS |
| **Accessibility Scanner** | Android |
| **Accessibility Insights** | Windows / Web |

### Manual Testing (Required)

1. **Operate all features with keyboard only** (no mouse or trackpad)
2. **Navigate every screen with a screen reader** (VoiceOver / TalkBack / NVDA)
3. **Font size at 200%** — check for layout breakage
4. **Reduce Motion ON** — verify animation behavior
5. **High Contrast / Dark Mode** — verify visual legibility
6. **Zoom 400%** (for Web) — verify usable without horizontal scrolling

### User Testing

Conduct testing with real users who have disabilities whenever possible. Automated tests detect only approximately **30%** of issues.

---

## 14. Cognitive Accessibility

- Use **simple language** (define technical terms when necessary).
- **Consistent navigation** (WCAG 3.2.3). Same features in the same place.
- **Consistent identification** (WCAG 3.2.4). Same features use the same labels and icons.
- **Confirmation steps for critical actions** (delete, payment). Make them undoable (WCAG 3.3.4).
- Use **progress indicators** to communicate long-running operations.
- **Error prevention** — hints before input, real-time validation, confirmation before submission.

---

## 15. WCAG 2.2 New Requirements (Important)

Criteria added since 2023:

- **2.4.11 Focus Not Obscured (Minimum)** (AA) — A focused element must not be fully hidden by other UI (e.g., a fixed header).
- **2.5.7 Dragging Movements** (AA) — Any action achievable by dragging must also be achievable with a single pointer (click/tap).
- **2.5.8 Target Size (Minimum)** (AA) — Input targets must be **at least 24×24 CSS px** (with exceptions).
- **3.2.6 Consistent Help** (A) — Help features must be in a consistent location.
- **3.3.7 Redundant Entry** (A) — Do not require re-entry of information already entered within the same process.
- **3.3.8 Accessible Authentication (Minimum)** (AA) — Provide an authentication method that does not rely on cognitive function tests (puzzles, image selection).

---

## 16. Review Checklist

Verify all of the following during UI review:

- [ ] All interactive elements have accessible names
- [ ] All features are operable by keyboard alone
- [ ] Focus indicators are visible (3:1 or more)
- [ ] Focus order is logical
- [ ] Modals / popovers close with `Esc`
- [ ] Text contrast meets AA or above (4.5:1 / 3:1)
- [ ] Information is not conveyed by color alone
- [ ] Touch targets meet recommended size or larger
- [ ] Layout does not break at 200% font scaling
- [ ] Visible in Dark Mode / High Contrast
- [ ] Reduce Motion ON suppresses excessive animations
- [ ] Images have appropriate alt text / decorative images are hidden from SR
- [ ] Videos have captions
- [ ] Form labels are associated with inputs
- [ ] Error messages are specific and indicate how to fix them
- [ ] Dynamic changes are announced to SR via live regions
- [ ] Drag operations have an alternative means

---

## Related Skills

- Apple UI: `skills/apple-ui-guidelines/SKILL.md`
- Windows UI: `skills/windows-ui-guidelines/SKILL.md`
- Web UI: `skills/web-ui-guidelines/SKILL.md`
- Android UI: `skills/android-ui-guidelines/SKILL.md`
- UI Review: `skills/ui-review-checklist/SKILL.md`
