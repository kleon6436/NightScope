---
name: ui-review-checklist
description: 'Cross-platform UI review checklist. Use when: reviewing UI pull requests; conducting UI QA; doing self-check before handoff across any platform.'
argument-hint: 'Target platform or focus category (optional)'
---

# UI Review Checklist

## Overview

This skill provides a checklist for reviewing and self-checking UI across platforms.
Work through this list from top to bottom before pull requests, handoffs, and QA.

See the following for platform-specific details:
- Apple: `skills/apple-ui-guidelines/SKILL.md`
- Windows: `skills/windows-ui-guidelines/SKILL.md`
- Web: `skills/web-ui-guidelines/SKILL.md`
- Android: `skills/android-ui-guidelines/SKILL.md`
- Accessibility: `skills/ui-accessibility/SKILL.md`

---

## 1. Visual Design

- [ ] Only design system / tokens (colors, spacing, typography) used — no hardcoded values
- [ ] Spacing follows the **8pt / 8dp / 4px** grid
- [ ] Font weights limited to 2–3 per screen
- [ ] Visual hierarchy is clear (title → body → supplementary information)
- [ ] Corner radii, shadows, and borders follow system standards or are consistent
- [ ] Icons use official sets (SF Symbols / Material Symbols / Segoe Fluent Icons, etc.)
- [ ] Platform-native components preferred — no custom reimplementations

---

## 2. Layout and Responsive

- [ ] Verified at both minimum and maximum widths
  - iOS: SE (375pt) ~ Pro Max (440pt)
  - iPad: 8.3" ~ 13", Split View / Stage Manager
  - Android: Compact / Medium / Expanded
  - Web: 320px / 768px / 1024px / 1440px
  - Windows: 500px ~ full screen, Snap Layouts
  - macOS: minimum window size ~ maximized
- [ ] No layout breakage in both portrait and landscape (mobile / tablet)
- [ ] No content crossing the fold crease on foldable devices
- [ ] Avoiding fixed widths like `width: 200px` / `frame(width: 200)`
- [ ] Respects Safe Area / Window Insets
- [ ] Scroll behavior is correct for long content (inertia / bounce)
- [ ] Edge-to-Edge (Android 15+) / content transparency behind Liquid Glass handled appropriately

---

## 3. Interaction

- [ ] Touch targets meet minimum recommended size (iOS 44pt / Android 48dp / Web 24–44px)
- [ ] All 5 states defined: tap, hover, focus, pressed, and disabled
- [ ] Destructive actions (delete, submit) have a confirmation and undo mechanism
- [ ] Gestures (swipe, pinch, drag) have alternative means of interaction
- [ ] Back navigation (Back / Escape / swipe) transitions as expected
- [ ] Predictive Back (Android 14+) supported
- [ ] Tapping outside a modal cancels it; Escape closes it

---

## 4. Text and i18n

- [ ] All user-facing strings are localized (no hardcoded strings)
- [ ] Text does not get cut off in longer languages like German / Finnish (expect 1.3× expansion)
- [ ] Text does not look sparse in shorter languages like Chinese
- [ ] Appropriate fonts for Japanese, Chinese, and Korean (CJK fallback)
- [ ] RTL (Arabic, Hebrew) layout is mirrored or handled with logical properties
- [ ] Dates, numbers, and currencies formatted per locale
- [ ] Readable line length: 45–75 characters (Japanese: 30–40 characters)
- [ ] Line height at least 1.5× for body text
- [ ] Full string accessible on text truncation (ellipsis) via tooltip / expand

---

## 5. State Design

Cover all of the following states for every screen:

- [ ] **Empty state** — Guidance and action when content count is 0 (`ContentUnavailableView`, etc.)
- [ ] **Loading** — Skeleton / placeholder / progress indicator
- [ ] **Error** — What went wrong + retry mechanism
- [ ] **Offline** — Behavior when connection is restored
- [ ] **Partial failure** — When only some data could be fetched
- [ ] **Paywall / Insufficient permissions** — Authentication / permission error display
- [ ] **Success feedback** — Snackbar / Toast / inline success

---

## 6. Accessibility

See `skills/ui-accessibility/SKILL.md` for details. Minimum requirements:

- [ ] All interactive elements have accessible names
- [ ] All features operable with keyboard only
- [ ] Focus indicator is visible (3:1 contrast)
- [ ] Focus order is logical
- [ ] Text contrast ratio 4.5:1 (normal) / 3:1 (large)
- [ ] Information not conveyed by color alone
- [ ] Layout does not break at 200% font size
- [ ] Read correctly by screen readers
- [ ] Reduce Motion supported
- [ ] Images have appropriate alt text; decorative images hidden from screen readers
- [ ] Videos have subtitles

---

## 7. Dark / Light Mode

- [ ] All screens visible in both themes
- [ ] No hardcoded colors (use semantic colors / theme resources)
- [ ] Images, illustrations, and icons work correctly in both themes
- [ ] Full-color logos have adjusted background / contrast in dark mode
- [ ] Shadows and borders visible in dark mode
- [ ] `color-scheme` / `<meta name="theme-color">` (Web) configured
- [ ] Increased Contrast / High Contrast supported

---

## 8. Animation and Motion

- [ ] Duration in the 150–400ms range
- [ ] Easing follows platform recommendations (Spring / FastOutSlowIn, etc.)
- [ ] Simplified or disabled when `prefers-reduced-motion` / Reduce Motion is enabled
- [ ] No flashing more than 3 times per second
- [ ] Auto-play / infinite loops have a stop mechanism
- [ ] Maintains 60fps (no jank)
- [ ] Centered on `transform` / `opacity`, not triggering layout changes

---

## 9. Performance

### General
- [ ] Something is visible within 1 second on initial load
- [ ] Scrolling at 60fps (no dropped frames)
- [ ] Long lists use deferred rendering (LazyColumn / RecyclerView / virtual scrolling)
- [ ] Images optimized for resolution (multiple sizes · WebP / AVIF / HEIC)

### Web
- [ ] **LCP ≤ 2.5s** / **CLS ≤ 0.1** / **INP ≤ 200ms**
- [ ] Images have `width` / `height` attributes and `loading="lazy"`
- [ ] Critical CSS inlined; non-critical deferred
- [ ] JS bundle audited (no unnecessary dependencies)

### Native
- [ ] Startup time measured (Baseline Profile, etc.)
- [ ] No memory leaks (profiled)
- [ ] Image caching appropriate (Coil / Kingfisher / SDWebImage)

---

## 10. Platform Conventions

### iOS / iPadOS
- [ ] Standard components used: `NavigationStack` / `NavigationSplitView` / `TabView`, etc.
- [ ] No custom backgrounds that block Liquid Glass
- [ ] Dynamic Type supported
- [ ] Size classes (Compact / Regular) supported
- [ ] Haptics (`.sensoryFeedback`) used appropriately

### macOS
- [ ] Standard keyboard shortcuts (⌘N / ⌘S / ⌘W)
- [ ] Menu bar items appropriate
- [ ] Responds to window resize
- [ ] Inspector panel used

### Android
- [ ] Material 3 + Dynamic Color supported
- [ ] Adaptive navigation with WindowSizeClass
- [ ] Edge-to-Edge + WindowInsets
- [ ] Predictive Back
- [ ] Adaptive icons + Monochrome

### Windows
- [ ] Fluent Design + Mica / Acrylic applied appropriately
- [ ] Title bar integration
- [ ] NavigationView + Segoe Fluent Icons
- [ ] High Contrast theme supported
- [ ] Keyboard accelerators (Ctrl+S / Alt navigation)

### Web
- [ ] Semantic HTML (`<button>` / `<nav>` / `<main>`, etc.)
- [ ] SEO meta tags / OGP configured
- [ ] HTTPS assumed; external links have `rel="noopener"`
- [ ] Viewport meta tag correct

---

## 11. Code Quality

- [ ] Component has a single responsibility (one concern)
- [ ] No magic numbers or magic strings
- [ ] Extraction to shared components is appropriate (no over-abstraction either)
- [ ] Recomposition / re-render optimized (`remember` / `useMemo` / `@Immutable`)
- [ ] No heavy computations inline
- [ ] Component can be previewed in isolation with Preview / Storybook
- [ ] Follows the language-specific coding standards skill (`swift-coding-standards` / `python-coding-standards`, etc.)

---

## 12. Security and Privacy (UI Perspective)

- [ ] Password fields handled correctly (input masking · `autocomplete="current-password"` / `"new-password"`)
- [ ] Sensitive information not written to clipboard, or written with an expiry
- [ ] Login state display is trustworthy (anti-spoofing)
- [ ] External links state their purpose + `rel="noopener"` (Web)
- [ ] Escape processing applied when displaying user-generated content
- [ ] Sensitive information protected in screenshots / task switcher (`FLAG_SECURE` / `isIdleTimerDisabled`, etc.)

---

## 13. Text (UX Writing)

- [ ] Button labels use **verb + object** ("Delete", "Save Changes")
- [ ] Error messages are specific and tell the user how to fix the issue (not just "Error" but "The email address format is invalid")
- [ ] Confirmation dialogs state the outcome explicitly ("Are you sure you want to delete?" → "This will permanently delete 'Report 2026'. This cannot be undone.")
- [ ] Polite / plain form is consistent throughout
- [ ] Technical terms and abbreviations kept to a minimum, with definitions provided
- [ ] Numbers, times, and dates are formatted consistently (full-width/half-width, 24-hour/12-hour, calendar era)
- [ ] Empty state microcopy offers encouragement or a next action

---

## 14. Edge Cases

- [ ] Very long names / strings (including emoji)
- [ ] Empty string / whitespace-only input
- [ ] Number 0 / negative numbers / maximum value
- [ ] Image load failure
- [ ] Network delay (equivalent to 3G)
- [ ] Date display on timezone switch
- [ ] Offline → online recovery
- [ ] Background → foreground recovery (state restoration)
- [ ] Input state preserved on device rotation
- [ ] Low memory (process kill → restoration)

---

## 15. Handoff / Documentation

- [ ] Component properties and slots are clearly defined
- [ ] Verified against design spec (Figma, etc.) — no discrepancies
- [ ] Prototype / demo video available (for complex interactions)
- [ ] UI changes recorded in release notes / changelog
- [ ] Accessibility verification records kept (VoiceOver / TalkBack logs)

---

## Usage

1. Self-check every item in this list from top to bottom before opening a PR.
2. Mark items not applicable with "N/A: reason".
3. Reviewers verify diffs, screenshots, and videos based on this list.
4. For platform-specific details, refer to the respective UI skill.
