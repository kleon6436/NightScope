---
name: i18n-localization
description: 'Reference and apply internationalization (i18n) and localization (l10n) guidelines. Use when: implementing internationalization, managing translation files, locale formatting, RTL layout support, pluralization.'
argument-hint: 'i18n / l10n item to review or apply (optional)'
---

# Internationalization (i18n) / Localization (l10n) Guidelines

## Overview

This skill defines conventions for implementing internationalization and localization in applications.
Follow this guideline when developing products targeting multiple languages and regions.

---

## 1. Core Principles

- **Do not hardcode text in code** — Manage all display text in resource files
- **Use `en` (English) as the default locale** and derive translations for each language from it
- **Cultural neutrality** — Verify that icons, colors, and gestures are not culturally problematic
- **Account for text expansion** — Design layouts assuming 1.3–1.5× the length of English text

---

## 2. Supported Locale Management

### Locale Code Conventions

- Follow IETF BCP 47 (e.g. `en`, `ja`, `zh-Hans`, `zh-Hant`, `ar`, `he`)
- Separate regional variants (e.g. `en-US`, `en-GB`) only when necessary

### Language File Structure

```
messages/
  en.json         — Default (required)
  ja.json         — Japanese
  zh-Hans.json    — Chinese (Simplified)
  zh-Hant.json    — Chinese (Traditional)
  ar.json         — Arabic (RTL)
  ko.json         — Korean
  fr.json         — French
  de.json         — German
  es.json         — Spanish
  pt-BR.json      — Portuguese (Brazil)
```

---

## 3. Translation Key Design

### Key Naming Conventions

- Use the `scope.component.meaning` format (dot-separated nesting)
- **Do not start with a verb** — Put the semantic subject first (use `form.submitButton`, not `button.submit`)
- **Name by meaning, not appearance** — Use `errorMessage`, not `redText`

```json
// ✅ Good
{
  "common": {
    "button": {
      "submit": "Submit",
      "cancel": "Cancel",
      "save": "Save"
    },
    "error": {
      "required": "This field is required.",
      "networkError": "Network error. Please try again."
    }
  },
  "auth": {
    "login": {
      "title": "Sign In",
      "emailLabel": "Email Address",
      "passwordLabel": "Password",
      "submitButton": "Sign In",
      "forgotPassword": "Forgot your password?"
    }
  }
}

// ❌ Bad
{
  "loginTitle": "Sign In",        // No scope
  "redText": "Error",             // Named by appearance
  "button1": "Submit"             // Meaningless name
}
```

### Variable Interpolation

- Use the `{variableName}` format for placeholders (may vary depending on the library)

```json
{
  "greeting": "Hello, {name}!",
  "itemCount": "You have {count} items in your cart."
}
```

---

## 4. Plural Handling

- Always use plural-aware logic; do not hardcode conditions like `if count === 1`
- Define `zero` / `one` / `two` / `few` / `many` / `other` categories per language

### Web (next-intl example)

```json
{
  "items": {
    "one": "{count} item",
    "other": "{count} items"
  }
}
```

### iOS / macOS (Localizable.stringsdict)

```xml
<key>%d items</key>
<dict>
  <key>NSStringLocalizedFormatKey</key>
  <string>%#@items@</string>
  <key>items</key>
  <dict>
    <key>NSStringFormatSpecTypeKey</key>
    <string>NSStringPluralRuleType</string>
    <key>one</key>
    <string>%d item</string>
    <key>other</key>
    <string>%d items</string>
  </dict>
</dict>
```

### Android (strings.xml)

```xml
<plurals name="items_count">
  <item quantity="one">%d item</item>
  <item quantity="other">%d items</item>
</plurals>
```

---

## 5. Date / Time / Number / Currency Formatting

- **Do not hardcode** — Use the `Intl` API / locale-aware libraries
- Exchange dates with the server in ISO 8601 and convert to local format on display

### Web (Intl API)

```ts
// Date
new Intl.DateTimeFormat('ja-JP', { dateStyle: 'long' }).format(date);
// → April 18, 2026 (locale-formatted)

// Number
new Intl.NumberFormat('de-DE').format(1234567.89);
// → 1.234.567,89

// Currency
new Intl.NumberFormat('ja-JP', { style: 'currency', currency: 'JPY' }).format(1500);
// → ¥1,500
```

### iOS / macOS (Swift)

```swift
let formatter = DateFormatter()
formatter.locale = Locale.current
formatter.dateStyle = .long
formatter.string(from: Date())

// Currency
let nf = NumberFormatter()
nf.numberStyle = .currency
nf.locale = Locale.current
nf.string(from: 1500)
```

---

## 6. RTL (Right-to-Left) Support

Principles for supporting RTL languages (Arabic `ar`, Hebrew `he`, Persian `fa`, etc.).

### Web

```css
/* Use logical properties */
margin-inline-start: 1rem;    /* ✅ Independent of left/right */
padding-inline-end: 0.5rem;

/* ❌ Avoid */
margin-left: 1rem;
padding-right: 0.5rem;
```

```html
<!-- Set dir attribute on the html tag -->
<html lang="ar" dir="rtl">
```

### iOS / macOS (Swift)

```swift
// UIKit: Use semanticContentAttribute
view.semanticContentAttribute = .forceRightToLeft

// SwiftUI: Automatically handled via environment
// HStack is automatically reversed in RTL
```

### Android (Kotlin)

```xml
<!-- Use start/end instead of left/right -->
<TextView
    android:paddingStart="16dp"
    android:paddingEnd="16dp"
    android:layout_marginStart="8dp" />
```

---

## 7. Platform-Specific Implementation

### iOS / macOS

- Use `String(localized:)` or `LocalizedStringKey` for text
- Files: `Localizable.strings` (general text) + `Localizable.stringsdict` (plurals)
- Prefer Xcode **String Catalog (.xcstrings)** as the first choice

```swift
// ✅ String Catalog (recommended)
Text("auth.login.title")  // SwiftUI

// ✅ From code
String(localized: "greeting", defaultValue: "Hello, \(name)!")
```

### Android

- Use `strings.xml` for text and `plurals` for plurals
- Fill placeholders with `getString(R.string.key, arg1, arg2)`
- Do not retrieve strings without a `Context`

```kotlin
// ✅ Good
getString(R.string.greeting, userName)
resources.getQuantityString(R.plurals.items_count, count, count)
```

### Web (next-intl example)

```tsx
import { useTranslations } from 'next-intl';

function LoginPage() {
  const t = useTranslations('auth.login');
  return <h1>{t('title')}</h1>;
}
```

### Windows (C#)

- Manage text in `Resources.resw`
- Retrieve at runtime using `ResourceLoader`

```csharp
var resourceLoader = ResourceLoader.GetForCurrentView();
string text = resourceLoader.GetString("Auth/Login/Title");
```

---

## 8. Translation Workflow

### Translation File Management

1. **Developers** add keys in the default language (`en`)
2. **CI** automatically detects untranslated keys and raises alerts
3. **Translators / translation tools** (Crowdin / Phrase / Lokalise, etc.) translate into each language
4. **PRs** review and merge translation files

### Handling Untranslated Keys

- Fall back to the default language (`en`)
- Log when a fallback occurs (beware of false positives in production)

---

## 9. Checklist

- [ ] All display text is managed in resource files
- [ ] No text is hardcoded in source code
- [ ] Plural handling is properly implemented
- [ ] Dates, times, numbers, and currencies use locale-aware formatting
- [ ] Verified that RTL languages do not cause layout breakage
- [ ] Verified that text expansion does not break the layout
- [ ] Placeholders are named using variable names
- [ ] CI untranslated-key detection is working
