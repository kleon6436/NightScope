---
name: apple-ui-guidelines
description: 'UI guidelines for Apple platforms (iOS / iPadOS / macOS). Use when reviewing or applying Human Interface Guidelines (HIG), Liquid Glass, SwiftUI layout, Dynamic Type, SF Symbols, VoiceOver, size classes, navigation structure, toolbars, sheets, and icons. Use when: designing or implementing UI for iOS, iPadOS, or macOS apps with SwiftUI; applying Apple HIG; adopting Liquid Glass; reviewing Apple platform UI code.'
argument-hint: 'Target platform (iOS / iPadOS / macOS) and the item to review (optional)'
---

# Apple UI Guidelines (iOS / iPadOS / macOS)

## Overview

This skill defines the UI design and implementation conventions for Apple platforms (iOS 26 / iPadOS 26 / macOS 26 Tahoe and later).
It summarizes the rules for complying with the Human Interface Guidelines (HIG) and correctly handling Liquid Glass materials.

References:
- [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- [Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass)

---

## Platform Tags

Instructions in each section may carry the following tags. Select applicable ones based on the target platform.

- **[iOS]** For iPhone (iOS)
- **[iPadOS]** For iPad
- **[macOS]** For Mac
- **[Common]** Applies to all platforms
- No tag = Common

---

## 1. HIG Compliance Rules (Common)

- **Prioritize SF Symbols.** Use icons over text labels to keep interfaces clean. Use the filled variant in tab bars and toolbars.
- **Use system colors and accent colors.** Use semantic colors such as `Color.accentColor` or `ShapeStyle` instead of hardcoded colors.
- **Support both Light and Dark mode.** Custom colors must define variants for Light, Dark, and Increased Contrast.
- **Do not crowd or overlap controls.** Do not layer Liquid Glass elements on top of each other.
- **Use standard spacing metrics.** Do not override system default spacing.
- **Support VoiceOver / Voice Control.** Set appropriate `accessibilityLabel` / `accessibilityHint` on all custom UI.
- **Support Dynamic Type.** Always use system fonts (`.body`, `.headline`, etc.) or `Font.custom(_:size:relativeTo:)` for fonts; avoid fixed sizes.
- **[iOS / iPadOS] Respect the Safe Area.** Do not place interactive elements in the notch, Dynamic Island, or home indicator areas.

---

## 2. Liquid Glass Core Policy (Common)

- **Maximize use of standard components.** `NavigationStack` / `NavigationSplitView` / `TabView` / toolbars / sheets / popovers automatically apply Liquid Glass.
- **Do not apply custom backgrounds to navigation elements.** Do not set custom `background` / `visualEffect` on tab bars, navigation bars, toolbars, sidebars, or sheets.
  - **[macOS Exception]** For immersive content apps (Photos, Maps, etc.), `.toolbarBackground(.hidden, for: .windowToolbar)` is acceptable (HIG: "Consider temporarily hiding toolbars for a distraction-free experience").
- **Do not overuse `glassEffect`.** Limit `glassEffect(_:in:)` to the most important functional elements such as custom controls.
- **Test with accessibility settings.** Verify that custom effects work properly with both "Reduce Transparency" and "Reduce Motion" enabled.

---

## 3. Navigation Structure

### [iOS] iPhone

- Use **`NavigationStack`** as the foundation.

```swift
NavigationStack(path: $path) {
    ContentView()
        .navigationDestination(for: Item.self) { item in
            DetailView(item: item)
        }
}
```

### [iPadOS / macOS]

- Use **`NavigationSplitView`** to achieve a sidebar layout.

```swift
NavigationSplitView {
    SidebarView()
} detail: {
    DetailView()
}
```

- Use **`inspector(isPresented:content:)`** for inspector panels.
- Apply **`backgroundExtensionEffect()`** to content adjacent to the sidebar or inspector to achieve an edge-to-edge appearance.

```swift
Image("hero")
    .resizable()
    .scaledToFill()
    .backgroundExtensionEffect()
```

---

## 4. Tab Bar

### [iOS / iPadOS]

| Item | iOS | iPadOS |
|------|-----|--------|
| Position | Bottom of screen (floating) | Top of screen |
| Sidebar conversion | Not supported | Convertible with `.sidebarAdaptable` |
| Customization | — | Items can be added/removed with `TabViewCustomization` |

```swift
TabView {
    Tab("Home", systemImage: "house.fill") { HomeView() }
    Tab("Library", systemImage: "books.vertical.fill") { LibraryView() }
    Tab(role: .search) { SearchView() }
}
.tabViewStyle(.sidebarAdaptable) // [iPadOS]
```

- **[iOS]** Minimize the tab bar on scroll: `.tabBarMinimizeBehavior(.onScrollDown)`
- **[iPadOS]** Use `TabViewCustomization` to allow users to add or remove tab items.
- Do not disable or hide the tab bar. Keep tabs visible even when content is empty, with an explanation.
- Tab labels should be concise — one word when possible.
- Prefer filled SF Symbols variants for tab icons.

### [macOS]

- Adopt **`.tabViewStyle(.sidebarAdaptable)`** for tab views to automatically convert to a sidebar.

---

## 5. Toolbar

- Group toolbar items by function and separate them with `ToolbarSpacer`.

```swift
.toolbar {
    ToolbarItemGroup(placement: .bottomBar) { // [iOS]
        Button("Edit", systemImage: "pencil") { }
        Button("Delete", systemImage: "trash") { }
    }
    ToolbarSpacer(.fixed)
    ToolbarItemGroup(placement: .bottomBar) {
        Button("Share", systemImage: "square.and.arrow.up") { }
    }
}
```

- Always set `accessibilityLabel` on icon-only items.
- Use **`ToolbarContent/hidden(_:)`** instead of `.hidden()` to hide items.
- Set **`scrollEdgeEffectStyle`** to ensure readability when scrolling.

---

## 6. Controls

- Use **`.buttonStyle(.glass)`** / **`.buttonStyle(.glassProminent)`** for glass-effect buttons.

```swift
Button("Add") { }.buttonStyle(.glass)
Button("Confirm") { }.buttonStyle(.glassProminent)
```

- For corner radii on custom controls, use **`ConcentricRectangle`** or **`rect(corners:isUniform:)`** to align concentrically with surrounding elements.
- Combine multiple custom Liquid Glass effects with **`GlassEffectContainer`** + **`glassEffectID(_:in:)`**.

```swift
GlassEffectContainer {
    ForEach(items) { item in
        ItemView(item: item)
            .glassEffect(.regular, in: .capsule)
            .glassEffectID(item.id, in: namespace)
    }
}
```

---

## 7. Sheets & Modals

- **[iOS / iPadOS]** iOS 26 sheets have increased corner radii, and half-sheets are inset from the screen edges. Ensure sufficient padding so that content does not overlap near the rounded corners.
- Use **`presentationDetents`** for appropriate size control.

```swift
.sheet(isPresented: $showSheet) {
    SheetContentView()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
}
```

- Remove custom background views (`visualEffectView`, etc.) from sheets and popovers, and defer to the system's Liquid Glass background.
- Use **`confirmationDialog`** for action sheets, and specify the source data with the `presenting` parameter.

```swift
.confirmationDialog(
    "Select an action",
    isPresented: $showDialog,
    titleVisibility: .visible,
    presenting: selectedItem
) { item in
    Button("Delete", role: .destructive) { delete(item) }
    Button("Share") { share(item) }
}
```

---

## 8. Lists & Forms

- Use **`.formStyle(.grouped)`** for forms.

```swift
Form {
    Section("Settings") {
        Toggle("Notifications", isOn: $notificationsEnabled)
        Slider(value: $volume, in: 0...1)
    }
}
.formStyle(.grouped)
```

- `Section` headers should use **Title Case** (do not use ALL CAPS).
- **[iOS / iPadOS]** The leading action of context menus and the leading swipe action should match.

```swift
.swipeActions(edge: .trailing, allowsFullSwipe: true) {
    Button("Delete", role: .destructive) { delete(item) }
}
.contextMenu {
    Button("Delete", role: .destructive) { delete(item) }
    Button("Share") { share(item) }
}
```

---

## 9. Search

- Define the search tab with **`Tab(role: .search)`**. The system automatically places it at the trailing end.
- **[iOS]** Place the search field inside the bottom toolbar.
- **[iPadOS]** Automatically placed at the top trailing edge.

---

## 10. Typography

- Use Dynamic Type scale (`.largeTitle` / `.title` / `.headline` / `.body` / `.callout` / `.subheadline` / `.footnote` / `.caption`).
- Use `Font.custom(_:size:relativeTo:)` for custom fonts to follow Dynamic Type scaling.
- Limit font weights to 2–3 variants on a single screen.
- Minimize custom `tracking` / `lineSpacing` settings.

```swift
Text("Title")
    .font(.title2)
    .fontWeight(.semibold)
Text("Description")
    .font(.body)
    .foregroundStyle(.secondary)
```

---

## 11. Spacing & Grid

- Use an **8pt grid** as the base. Use multiples of `8, 16, 24, 32`.
- Prohibit magic numbers. Define spacing constants.

```swift
enum Spacing {
    static let xs: CGFloat = 8
    static let sm: CGFloat = 16
    static let md: CGFloat = 24
    static let lg: CGFloat = 32
}
```

- Keep related elements close together; separate distinct groups with wider spacing.

---

## 12. Content-First Layout

- Allow content to show through behind navigation elements on Liquid Glass. Aim for full-bleed placement.
- **[iOS / iPadOS]** Use **`ignoresSafeArea(.container, edges: .top)`** for hero images.
- **[macOS / iPadOS]** Apply **`backgroundExtensionEffect()`** to content adjacent to the sidebar.
- Set `contentMargins` / `safeAreaPadding` / `scrollEdgeEffectStyle` appropriately.

---

## 13. Animation & Transitions

- Use **`.animation(.spring(duration: 0.3), value:)`** for basic animations. Do not use `.linear` without a specific reason.
- Use **`matchedGeometryEffect`** for element morphing.
- Use **`glassEffectID(_:in:)` + `withAnimation`** for Liquid Glass morphing.
- Support Reduce Motion:

```swift
@Environment(\.accessibilityReduceMotion) var reduceMotion

.animation(reduceMotion ? .none : .spring(duration: 0.3), value: isExpanded)
```

---

## 14. Color Design

- Use semantic colors hierarchically:
  - Most important: `.primary`
  - Supporting: `.secondary`
  - More supplemental: `.tertiary`
  - Disabled: `.quaternary`
- Use `Color.accentColor` for accent color. Avoid hardcoded RGB values.
- For text on Liquid Glass, ensure readability with `.shadow(radius:)` or `.foregroundStyle(.primary)`.
- Define custom colors in Assets.xcassets with 3 variants: Light / Dark / Increased Contrast.

---

## 15. Size Class Support [iOS / iPadOS]

- Use `@Environment(\.horizontalSizeClass)` to determine layout width class:
  - **Compact width**: iPhone (both orientations), narrow iPad windows in portrait
  - **Regular width**: iPad landscape / wide windows, **iPhone Pro Max / Plus in landscape**

```swift
@Environment(\.horizontalSizeClass) var horizontalSizeClass

var body: some View {
    if horizontalSizeClass == .compact {
        VStack { ... }
    } else {
        HStack { ... }
    }
}
```

- `@Environment(\.verticalSizeClass)`:
  - Portrait: `regular`
  - Landscape (all iPhones): `compact`

---

## 16. Haptics [iOS]

- Use **`.sensoryFeedback(_:trigger:)`**. Use `UIImpactFeedbackGenerator` only when SwiftUI is not supported.

```swift
Button("Delete") { delete() }
    .sensoryFeedback(.warning, trigger: isDeleted)
Toggle("Notifications", isOn: $enabled)
    .sensoryFeedback(.selection, trigger: enabled)
```

- Supported feedback types:
  - Success: `.success`
  - Warning: `.warning`
  - Error: `.error`
  - Selection: `.selection`
  - Light tap: `.impact(weight: .light)`

---

## 17. Empty State & Error State

- Use **`ContentUnavailableView`**. Do not build custom empty screens.

```swift
if items.isEmpty {
    ContentUnavailableView(
        "No Items",
        systemImage: "tray",
        description: Text("Add a new item to get started.")
    )
}

ContentUnavailableView.search(text: searchText)
```

---

## 18. Loading / Skeleton UI

- Use **`.redacted(reason: .placeholder)`** for skeleton display. Avoid full-screen `ProgressView()`.

```swift
ItemRowView(item: placeholderItem)
    .redacted(reason: isLoading ? .placeholder : [])
```

---

## 19. Adaptive Layout

- Use **`ViewThatFits`** to provide alternative layouts.

```swift
ViewThatFits {
    HStack { LabelView(); ValueView() }
    VStack { LabelView(); ValueView() }
}
```

- Avoid fixed-width `frame(width:)`; prefer `.frame(maxWidth: .infinity)` / `.fixedSize()`.
- **[iOS]** Use **`containerRelativeFrame`** to absorb device width differences (375–440 pt).
- Avoid overusing `GeometryReader`.

---

## 20. Keyboard & Focus Management

- Use **`@FocusState`** to manage focus explicitly.

```swift
@FocusState private var isFieldFocused: Bool

TextField("Name", text: $name)
    .focused($isFieldFocused)
```

- **[iPadOS / macOS]** Assign **`KeyboardShortcut`** to primary actions.

```swift
Button("New") { createItem() }
    .keyboardShortcut("n", modifiers: .command)
Button("Save") { save() }
    .keyboardShortcut("s", modifiers: .command)
```

- **[macOS]** macOS is keyboard-first. Follow standard conventions (⌘N, ⌘S, ⌘W, etc.). Design Tab focus order logically.

---

## 21. Windows [macOS]

- Support resizing to any size and set an appropriate minimum size.
- `NavigationSplitView` automatically provides fluid transitions when resizing.
- Set `safeAreaInsets` / layout guides correctly to prevent overlap with window controls and the title bar.
- Do not fix the column widths of `NavigationSplitView`.

---

## 22. App Icon

Create layered icons using **Icon Composer** (built into Xcode 26).

- Layer structure: Foreground / Midground / Background (the system automatically applies reflections, refractions, shadows, and blur)
- The system automatically adds a background for irregular shapes
- Center elements within the icon and account for the rounded corner clipping

### Required Variants

| Platform | Variants |
|---|---|
| [iOS / iPadOS] | Default (Light) / Dark / Clear / Tinted |
| [macOS] | Default (Light) / Dark / Clear (Light) / Clear (Dark) / Tinted (Light) / Tinted (Dark) |

---

## 23. Screen Size Testing [iOS]

The HIG states: "Test the largest and smallest layouts first." Always verify on these devices:

| Test Target | Width | Height | Verification Points |
|---|---|---|---|
| iPhone SE (4.7-inch) | 375 | 667 | Smallest class. No content clipping |
| iPhone 17 Pro Max | 440 | 956 | Largest class. Regular width in landscape |

Verification checklist:
- Text and controls fit within the Safe Area
- No layout breakage at the largest Dynamic Type size (Accessibility XL)
- `verticalSizeClass`-based switching works correctly in landscape

---

## Related Skills

- Accessibility in general: `skills/ui-accessibility/SKILL.md`
- UI review: `skills/ui-review-checklist/SKILL.md`
- Swift coding standards: `skills/swift-coding-standards/SKILL.md`
