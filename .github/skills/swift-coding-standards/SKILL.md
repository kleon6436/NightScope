---
name: swift-coding-standards
description: 'Swiftのコーディング規約を参照・適用する。Swift コーディング規約、命名規則、スタイルガイド、フォーマット、アクセス制御、エラーハンドリング、コメント規約を確認・適用したいときに使用。Use when: applying Swift style guide, reviewing Swift code conventions, naming rules, access control, error handling patterns.'
argument-hint: '確認・適用したいコーディング規約の項目（省略可）'
---

# Swift コーディング規約

## 概要

このスキルは Swift コードのコーディング規約を定義します。
コードレビュー・新規実装の際はこの規約に従ってください。

---

## 1. 命名規則

### 型・プロトコル・列挙型

- **UpperCamelCase** を使用する。
- 意味が明確で説明的な名前をつける。

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

### 変数・定数・関数・メソッド

- **lowerCamelCase** を使用する。
- ブール値は `is`, `has`, `can`, `should` などのプレフィックスを使う。

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

### 定数・列挙値

- `static let` 定数および `enum` のケースは **lowerCamelCase** を使用する。

```swift
// ✅ Good
enum Direction {
    case north, south, east, west
}
static let maxRetryCount = 3
```

---

## 2. コードフォーマット

| 項目 | 設定値 |
|------|--------|
| インデント | スペース 4 個（タブ不可） |
| 1行の最大文字数 | 120 文字 |
| 中括弧 `{` の位置 | 行末（K&R スタイル） |
| 末尾スペース | 禁止 |
| ファイル末尾の改行 | 必須 |

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

## 3. アクセス制御

- 外部に公開する必要がないものには必ず `private` または `fileprivate` を付ける。
- `public` / `open` は本当に外部公開が必要な場合のみ使用する。
- デフォルト（`internal`）は明示しない。

```swift
// ✅ Good
private var cache: [String: Data] = [:]
private func parseResponse(_ data: Data) { }

// ❌ Bad（不必要に internal のまま）
var cache: [String: Data] = [:]
```

---

## 4. 型推論・型アノテーション

- 型が明確に推論できる場合は型アノテーションを省略する。
- 公開 API や可読性向上のために必要な場合は明示する。

```swift
// ✅ Good
let count = 10
let message = "Hello"
let items: [Item] = []   // 空配列は明示

// ❌ Bad
let count: Int = 10
let message: String = "Hello"
```

---

## 5. オプショナル

- `!` による強制アンラップは原則禁止。IBOutlet / IBAction を除く。
- `guard let` / `if let` によるオプショナルバインディングを優先する。
- `??` によるデフォルト値を活用する。

```swift
// ✅ Good
guard let user = currentUser else { return }
let name = user.name ?? "Unknown"

// ❌ Bad
let user = currentUser!
```

---

## 6. エラーハンドリング

- `throws` / `try` / `catch` を使用する。
- エラーは `enum` で定義し、`Error` プロトコルに準拠させる。
- `try?` は値が不要な場合のみ使用し、`try!` は原則禁止。

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
    // ネットワークエラー処理
} catch {
    // その他のエラー処理
}
```

---

## 7. コレクション・クロージャ

- 末尾クロージャ構文を使用する。
- `map`, `filter`, `compactMap` 等の高階関数を積極的に使用する。

```swift
// ✅ Good
let doubled = numbers.map { $0 * 2 }
let evens = numbers.filter { $0.isMultiple(of: 2) }

// ❌ Bad
let doubled = numbers.map({ (n: Int) -> Int in return n * 2 })
```

---

## 8. コメント規約

- コードのロジックが自明でない箇所にのみコメントを付ける。
- 公開 API には **DocC 形式**のドキュメントコメントを付ける。
- TODO / FIXME は `// TODO: 説明` の形式で記述し、チケット番号を添える。

```swift
/// ユーザー情報を取得します。
/// - Parameter id: 対象ユーザーの識別子
/// - Returns: 対象ユーザーの `UserProfile`
/// - Throws: ユーザーが存在しない場合 `APIError.notFound`
func fetchUser(id: String) async throws -> UserProfile {
    // ...
}

// TODO: #123 キャッシュ最適化を実装する
```

---

## 9. 非同期処理

- `async/await` を優先する（Combine / callback は段階的に移行）。
- `@MainActor` を UI 更新を行うクラス・メソッドに付与する。
- `Task` のライフサイクルを管理し、不要なタスクはキャンセルする。

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
