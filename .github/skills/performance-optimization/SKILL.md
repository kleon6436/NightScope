---
name: performance-optimization
description: 'Reference and apply performance optimization guidelines. Use when: optimizing app performance, reducing bundle size, improving Core Web Vitals, memory profiling, render optimization, caching strategies.'
argument-hint: 'Performance optimization topic to check or apply (optional)'
---

# Performance Optimization Guidelines

## Overview

This skill defines the performance optimization standards for applications.
The core principle is "measure before optimizing" — avoid guesswork-based optimization.

---

## 1. Common Principles

- **Measure first, optimize later** — Profile with evidence before optimizing
- **Prioritize metrics that directly affect user experience** — FID, LCP, CLS, startup time, scroll smoothness
- **Avoid premature optimization** — Confirm necessity before sacrificing readability
- **Set a performance budget** — Define target values and continuously monitor in CI

---

## 2. Web Performance

### Core Web Vitals Targets

| Metric | Good | Needs Improvement | Poor |
|--------|------|-------------------|------|
| LCP (Largest Contentful Paint) | ≤ 2.5s | 2.5–4.0s | > 4.0s |
| INP (Interaction to Next Paint) | ≤ 200ms | 200–500ms | > 500ms |
| CLS (Cumulative Layout Shift) | ≤ 0.1 | 0.1–0.25 | > 0.25 |

### Image Optimization

```tsx
// ✅ Good: automatic optimization with next/image (Next.js)
import Image from 'next/image';
<Image src="/hero.jpg" alt="Hero" width={1200} height={600} priority />

// ✅ Good: appropriate format and lazy loading
<img src="image.webp" loading="lazy" decoding="async" width="400" height="300" />

// ❌ Bad: no size specified (causes CLS)
<img src="image.jpg" />
```

### Bundle Size Reduction

```ts
// ✅ Good: Code Splitting via dynamic import
const HeavyComponent = dynamic(() => import('./HeavyComponent'), {
  loading: () => <Skeleton />,
});

// ✅ Good: named import for tree-shaking support
import { debounce } from 'lodash-es';

// ❌ Bad: default import loads the entire bundle
import _ from 'lodash';
```

### Cache Strategy

| Resource | Cache-Control |
|----------|---------------|
| HTML | `no-cache` (always fetch fresh) |
| JS / CSS (hashed) | `max-age=31536000, immutable` |
| Images | `max-age=86400` (1 day) |
| API responses | `max-age=60, stale-while-revalidate=300` |

### Rendering Optimization (React)

```tsx
// ✅ Good: memoize expensive computations with useMemo
const sortedList = useMemo(() => expensiveSort(data), [data]);

// ✅ Good: prevent function re-creation with useCallback
const handleClick = useCallback(() => {
  onSelect(item.id);
}, [item.id, onSelect]);

// ✅ Good: prevent component re-renders with React.memo
const ListItem = memo(({ item, onSelect }: Props) => {
  return <div onClick={() => onSelect(item.id)}>{item.name}</div>;
});

// ❌ Bad: expensive computation written directly during render
const sorted = data.sort((a, b) => /* expensive comparison */);
```

---

## 3. iOS / macOS Performance

### Profiling with Instruments

- **Time Profiler** — identify CPU usage hotspots
- **Allocations** — track memory allocations and deallocations
- **Leaks** — detect memory leaks
- **Core Data** — check fetch frequency and slow queries

### SwiftUI Optimization

```swift
// ✅ Good: prevent unnecessary redraws with Equatable
struct ListRowView: View, Equatable {
    let item: Item
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.item.id == rhs.item.id && lhs.item.updatedAt == rhs.item.updatedAt
    }
}

// ✅ Good: evaluate lazily only when needed
LazyVStack {
    ForEach(items) { item in
        ItemRow(item: item)
    }
}

// ✅ Good: @StateObject is created only once
@StateObject private var viewModel = ItemListViewModel()

// ❌ Bad: passing @ObservedObject from outside (may be recreated each time)
```

### Async & Background Processing

```swift
// ✅ Good: do not block the main thread
Task {
    let data = await fetchData()  // processed in the background
    await MainActor.run {
        self.items = data         // UI updates on the main thread
    }
}

// ❌ Bad: synchronous network call on the main thread
let data = URLSession.shared.synchronousRequest(url)  // Not OK
```

---

## 4. Android Performance

### Compose Optimization

```kotlin
// ✅ Good: cache expensive computations with remember
val sortedItems = remember(items) {
    items.sortedBy { it.name }
}

// ✅ Good: prevent unnecessary recompositions with derivedStateOf
val isButtonEnabled by remember {
    derivedStateOf { selectedItems.isNotEmpty() }
}

// ✅ Good: specify keys in LazyColumn for animation optimization
LazyColumn {
    items(items, key = { it.id }) { item ->
        ItemRow(item = item)
    }
}

// ❌ Bad: LazyColumn without keys (all items recomposed)
```

### ANR Prevention

```kotlin
// ✅ Good: run I/O operations on Dispatchers.IO
viewModelScope.launch(Dispatchers.IO) {
    val result = repository.fetchData()
    withContext(Dispatchers.Main) {
        _uiState.value = UiState.Success(result)
    }
}

// ❌ Bad: heavy processing on the main thread
fun loadData() {
    _uiState.value = repository.fetchDataBlocking()  // causes ANR
}
```

### Profiling Tools

- **Android Studio Profiler** — CPU, memory, network, and energy
- **Compose Inspector** — check Recomposition count
- **Systrace / Perfetto** — identify frame time bottlenecks

---

## 5. Memory Management

### Common Patterns

```swift
// Swift: use [weak self] to prevent retain cycles
someViewModel.onComplete = { [weak self] result in
    self?.handleResult(result)
}
```

```kotlin
// Kotlin: use lifecycleScope to automatically cancel on lifecycle end
viewLifecycleOwner.lifecycleScope.launch {
    viewModel.uiState.collect { state ->
        updateUI(state)
    }
}
```

```ts
// React: unsubscribe in useEffect cleanup
useEffect(() => {
  const subscription = dataService.subscribe(setData);
  return () => subscription.unsubscribe();
}, []);
```

---

## 6. Performance Budget

Set the following target values at project start and monitor with CI.

| Metric | Target (example) |
|--------|------------------|
| JS bundle size (initial load) | 200 KB or less (gzip) |
| TTI (Time to Interactive) | 3.0 s or less |
| LCP | 2.5 s or less |
| App launch time (iOS cold) | 400 ms or less |
| Scroll frame rate | 60 fps (120 fps on 120 fps-capable devices) |
| Memory usage (typical use) | {project-specific target} |

---

## 7. Checklist

- [ ] Optimization is applied to bottlenecks measured with a profiler
- [ ] Core Web Vitals targets are set and monitored in CI
- [ ] Images have appropriate format, dimensions, and lazy loading
- [ ] Code Splitting is applied to reduce bundle size
- [ ] Expensive computations are properly cached (memoized)
- [ ] No heavy synchronous processing on the main thread
- [ ] Potential memory leaks (retain cycles, unremoved listeners) have been checked
- [ ] Virtualization and lazy loading are applied to list rendering
