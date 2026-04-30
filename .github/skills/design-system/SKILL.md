---
name: design-system
description: 'Reference and apply design system and design token management guidelines. Use when establishing design tokens, color system, typography scale, spacing system, component specifications, cross-platform brand consistency.'
argument-hint: 'The design system item to review or apply (optional)'
---

# Design System & Token Management Guidelines

## Overview

This skill defines conventions for design systems and design token management.
It provides practical guidelines for maintaining brand consistency across platforms while adapting to each platform's design language.

---

## 1. What are Design Tokens?

Design tokens are a **platform-agnostic mechanism for managing design decisions** such as colors, typography, and spacing.
They are defined as a Single Source of Truth in Figma or JSON, then converted to each platform's format.

### Token Hierarchy

```
Foundation
  └── Semantic
        └── Component
```

| Tier | Example | Usage |
|------|----|----|
| **Foundation** | `color.blue.500 = #2563EB` | Raw color palette. Do not use directly |
| **Semantic** | `color.primary = color.blue.500` | Referenced by meaning. Components use this tier |
| **Component** | `button.primary.background = color.primary` | Component-specific settings |

---

## 2. Color System

### Light / Dark Mode Support

```json
// tokens.json (Style Dictionary format)
{
  "color": {
    "background": {
      "primary": {
        "$value": { "light": "#FFFFFF", "dark": "#1C1C1E" },
        "$type": "color"
      },
      "secondary": {
        "$value": { "light": "#F2F2F7", "dark": "#2C2C2E" },
        "$type": "color"
      }
    },
    "text": {
      "primary": {
        "$value": { "light": "#000000", "dark": "#FFFFFF" },
        "$type": "color"
      },
      "secondary": {
        "$value": { "light": "#6B7280", "dark": "#9CA3AF" },
        "$type": "color"
      }
    },
    "interactive": {
      "primary": {
        "$value": { "light": "#2563EB", "dark": "#3B82F6" },
        "$type": "color"
      }
    }
  }
}
```

### Accessibility Requirements (WCAG 2.2 AA)

| Contrast Ratio | Usage |
|--------------|------|
| 4.5 : 1 or higher | Normal text (under 18px) |
| 3 : 1 or higher | Large text (18px or above / Bold 14px or above) · UI components |

For details, refer to `skills/ui-accessibility/SKILL.md`.

---

## 3. Typography Scale

### Scale Definition

| Token | Size | Weight | Usage |
|---------|-------|--------|------|
| `text.display` | 34px / 36px | Bold | Hero headings |
| `text.title1` | 28px / 34px | Regular / Bold | Page titles |
| `text.title2` | 22px / 28px | Regular / Bold | Section titles |
| `text.title3` | 20px / 24px | Regular / Semibold | Subsections |
| `text.headline` | 17px / 20px | Semibold | Card headings |
| `text.body` | 17px / 16px | Regular | Body text |
| `text.callout` | 16px / 15px | Regular | Supplementary info |
| `text.subheadline` | 15px / 14px | Regular | Labels |
| `text.footnote` | 13px / 12px | Regular | Annotations |
| `text.caption` | 12px / 11px | Regular | Captions |

### Platform Adaptation

| Platform | Recommended Font | Scaling |
|--------------|-----------|------------|
| iOS / macOS | SF Pro / SF Pro Rounded | Dynamic Type support |
| Android | Roboto / Google Sans | Defined in sp units |
| Web | system-ui / Inter / Noto Sans | Defined in rem units |
| Windows | Segoe UI Variable | WinUI 3 TextBlock |

---

## 4. Spacing System

### Base Grid: 4px

```
space-1  =  4px  — Extra small (icon inner padding)
space-2  =  8px  — Small (between related elements)
space-3  = 12px  — Small-medium (compact padding)
space-4  = 16px  — Medium (standard padding)
space-5  = 20px  — Medium-large
space-6  = 24px  — Large (section inner padding)
space-8  = 32px  — Extra large (between sections)
space-10 = 40px  — 2XL
space-12 = 48px  — Page-level padding
space-16 = 64px  — Maximum padding
```

### Principles

- Use **smaller spacing** between adjacent related elements; use **larger spacing** between unrelated elements
- Base content-to-edge padding on `space-4` (16px)
- Account for platform system spacing (Safe Area, Status Bar, etc.)

---

## 5. Component Specifications

### Buttons

| Variant | Usage | Appearance |
|---------|------|-------|
| `Primary` | Main action (one per screen as a rule) | Filled · brand color |
| `Secondary` | Secondary actions | Outlined or Tonal |
| `Tertiary` | Supplementary actions | Text only |
| `Destructive` | Delete / cancel, etc. | Red tones |
| `Ghost` | Lowest priority | No background · text only |

```
Minimum tap target: 44×44px (iOS HIG / WCAG compliant)
```

### State Design (required for all interactive elements)

| State | Definition |
|------|------|
| **Default** | Normal display |
| **Hover** | Mouse cursor over (Desktop) |
| **Pressed** | Being tapped / clicked |
| **Focused** | Keyboard focus (required for accessibility) |
| **Disabled** | Not interactive |
| **Loading** | Processing |

---

## 6. Token Conversion (Style Dictionary)

```js
// style-dictionary.config.js
module.exports = {
  source: ['tokens/**/*.json'],
  platforms: {
    // CSS Custom Properties (Web)
    css: {
      transformGroup: 'css',
      buildPath: 'src/styles/',
      files: [{ destination: 'tokens.css', format: 'css/variables' }],
    },
    // Swift (iOS / macOS)
    ios_swift: {
      transformGroup: 'ios-swift',
      buildPath: 'Sources/DesignSystem/',
      files: [{ destination: 'DesignTokens.swift', format: 'ios-swift/enum.swift' }],
    },
    // Android (Compose)
    android: {
      transformGroup: 'android',
      buildPath: 'app/src/main/res/values/',
      files: [{ destination: 'tokens.xml', format: 'android/resources' }],
    },
  },
};
```

---

## 7. Figma Integration

- Manage tokens in Figma **Variables** / **Styles** and sync with development
- Automate JSON export with **Tokens Studio** (Figma plugin)
- Using the same token names between designers and developers prevents implementation drift

---

## 8. Checklist

- [ ] Tokens are defined in 3 tiers: Foundation / Semantic / Component
- [ ] Colors have both light and dark mode values defined
- [ ] Text contrast meets WCAG 2.2 AA
- [ ] Spacing follows the 4px grid
- [ ] All interactive components have 6 states defined
- [ ] Tokens are auto-converted to each platform's format (CSS / Swift / XML)
- [ ] Figma token definitions and code are in sync
