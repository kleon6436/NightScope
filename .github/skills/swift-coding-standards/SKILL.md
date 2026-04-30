---
name: swift-coding-standards
description: 'Reference and apply Swift coding standards. Use when applying Swift style guide, reviewing Swift code conventions, naming rules, code format, access control, error handling patterns, and comment conventions.'
argument-hint: 'The coding standard item to check or apply (optional)'
---

# Swift Coding Standards

## Overview

This skill defines coding standards for Swift code.
Follow these standards during code reviews and new implementations.

---

## 1. Naming Conventions

### Types, Protocols, and Enumerations

- Use **UpperCamelCase**.
- Use clear and descriptive names.

```swift
// ✅ Good
struct UserProfile { }
class NetworkManager { }
protocol DataFetchable { }
enum ConnectionState { }

// ❌ Bad
struct userprofile { }
class NM { }
```

### Variables, Constants, Functions, and Methods

- Use **lowerCamelCase**.
- Boolean values should use prefixes such as `is`, `has`, `can`, `should`.

```swift
// ✅ Good
let userName: String
var isLoggedIn: Bool
func fetchUserData() { }

// ❌ Bad
let UserName: String
var LoggedIn: Bool
func FetchUserData() { }
```

### Constants and Enumeration Cases

- `static let` constants and `enum` cases use **lowerCamelCase**.

```swift
// ✅ Good
enum Direction {
    case north, south, east, west
}
static let maxRetryCount = 3
```

---

## 2. Code Format

<!-- Change values as needed for your project -->

| Item | Setting |
|------|-----|
| Indent | {4} spaces (no tabs) |
| Max line length | {120} characters |
| Opening brace `{` position | End of line (K&R style) |
| Trailing whitespace | Prohibited |
| Newline at end of file | Required |

```swift
// ✅ Good
func greet(name: String) -> String {
    return "Hello, \(name)!"
}

// ❌ Bad
func greet(name: String) -> String
{
    return "Hello, \(name)!"
}
```

---

## 3. Access Control

- Always apply `private` or `fileprivate` to anything that does not need to be exposed externally.
- Use `public` / `open` only when external exposure is truly necessary.
- Do not explicitly state the default (`internal`).

```swift
// ✅ Good
private var cache: [String: Data] = [:]
private func parseResponse(_ data: Data) { }

// ❌ Bad（unnecessarily left as internal）
var cache: [String: Data] = [:]
```

---

## 4. Type Inference and Type Annotations

- Omit type annotations when the type can be clearly inferred.
- Explicitly annotate when needed for public APIs or improved readability.

```swift
// ✅ Good
let count = 10
let message = "Hello"
let items: [Item] = []   // Explicit annotation for empty arrays

// ❌ Bad
let count: Int = 10
let message: String = "Hello"
```

---

## 5. Optionals

- Force-unwrapping with `!` is prohibited in principle. Exceptions: IBOutlet / IBAction.
- Prefer optional binding with `guard let` / `if let`.
- Make use of default values via `??`.

```swift
// ✅ Good
guard let user = currentUser else { return }
let name = user.name ?? "Unknown"

// ❌ Bad
let user = currentUser!
```

---

## 6. Error Handling

- Use `throws` / `try` / `catch`.
- Define errors as `enum` conforming to the `Error` protocol.
- Use `try?` only when the value is not needed; `try!` is prohibited in principle.

```swift
// ✅ Good
enum APIError: Error {
    case networkFailure
    case invalidResponse(statusCode: Int)
    case decodingFailed
}

func fetchData() throws -> Data {
    // ...
}

do {
    let data = try fetchData()
} catch APIError.networkFailure {
    // Network error handling
} catch {
    // Other error handling
}
```

---

## 7. Collections and Closures

- Use trailing closure syntax.
- Make active use of higher-order functions such as `map`, `filter`, `compactMap`.

```swift
// ✅ Good
let doubled = numbers.map { $0 * 2 }
let evens = numbers.filter { $0.isMultiple(of: 2) }

// ❌ Bad
let doubled = numbers.map({ (n: Int) -> Int in return n * 2 })
```

---

## 8. Comment Conventions

- Only add comments where the code logic is not self-evident.
- Attach **DocC-style** documentation comments to public APIs.
- Write TODO / FIXME in the format `// TODO: description` and include a ticket number.

```swift
/// Fetches user information.
/// - Parameter id: The identifier of the target user
/// - Returns: The `UserProfile` of the target user
/// - Throws: `APIError.notFound` if the user does not exist
func fetchUser(id: String) async throws -> UserProfile {
    // ...
}

// TODO: #123 Implement cache optimization
```

---

## 9. Asynchronous Processing

- Prefer `async/await` (migrate from Combine / callbacks incrementally).
- Apply `@MainActor` to classes and methods that perform UI updates.
- Manage `Task` lifecycles and cancel unnecessary tasks.

```swift
// ✅ Good
@MainActor
func updateUI(with user: UserProfile) {
    nameLabel.text = user.name
}

func loadData() async throws {
    let user = try await fetchUser(id: userId)
    await updateUI(with: user)
}
```

---

## 10. Project-Specific Rules

<!-- Add project-specific content as needed -->

- {Add project-specific rules here}
