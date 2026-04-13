# プロジェクトガイドライン（共通）

## 前提

- **回答は必ず日本語で行うこと。**
- コードの変更をする際、変更量が200行を超える可能性が高い場合は、事前に「この指示では変更量が200行を超える可能性がありますが、実行しますか？」とユーザーに確認をとること。
- 何か大きい変更を加える場合、まず何をするのか計画を立てた上で、ユーザーに「このような計画で進めようと思います。」と提案すること。

## Custom Agent 運用

- custom agent は役割で使い分ける。要件整理は `product-manager`、技術設計は `architect`、実装は `developer`、UI/UX は `ui-designer`、レビューは `reviewer`、検証は `tester`、複数委譲の統合は `orchestrator` を優先する。
- custom agent に handoff する際は、この `.github/copilot-instructions.md` を共通前提として渡す。
- macOS 変更は `.github/instructions/macos.instructions.md`、iOS 変更は `.github/instructions/ios.instructions.md` を追加前提として渡す。
- Swift コードの規約判断では `.github/skills/swift-coding-standards/SKILL.md` を参照させる。
- UI 変更では Apple HIG、Liquid Glass、アクセシビリティ、Dynamic Type、Safe Area の遵守を handoff に明記する。
- `NightScope/` と `NightScopeTests/` は macOS 文脈、`NightScopeiOS/` は iPhone 向け iOS 文脈として扱う。
- 実装・レビュー・テストで完了条件を置く場合は、原則として README 記載の `xcodebuild` コマンドを基準にする。
- 重要な設計変更や複数ターゲット変更では、`developer` だけで閉じず `reviewer` と `tester` を品質ゲートに含める。

## Apple HIG 準拠ルール

- **SF Symbols を優先使用する。** テキストラベルよりもアイコンを活用し、インターフェースをクリーンに保つ。タブバー・ツールバーでは filled バリアントを使用する。
- **システムカラー・アクセントカラーを使用する。** ハードコードされた色の代わりに `Color.accentColor` や `ShapeStyle` のセマンティックカラーを使用する。
- **ライト / ダークモードの両対応を必須とする。** カスタムカラーは Light・Dark・増加コントラスト（Increased Contrast）の各バリアントを定義する。
- **コントロールを密集・重複させない。** Liquid Glass 要素をレイヤーとして重ねない。
- **標準スペーシングメトリクスを使用する。** システムのデフォルトスペーシングを上書きしない。
- **VoiceOver / Voice Control 対応を行う。** すべてのカスタム UI に適切な `accessibilityLabel` / `accessibilityHint` を設定する。
- **Dynamic Type に対応する。** フォントには必ずシステムフォント（`.body`・`.headline` 等）または `Font.custom(_:size:relativeTo:)` を使用し、固定サイズのフォントを避ける。
- **Safe Area を尊重する。** ノッチ・Dynamic Island・ホームインジケーターの領域にインタラクティブな要素を配置しない。

## UI レイアウト・ビジュアルデザイン原則（共通）

美しい UI 配置を実現するため、以下の原則を遵守すること。

---

### 1. タイポグラフィ

- **Dynamic Type スケールを必ず使用する。** フォントには `.largeTitle`・`.title`・`.headline`・`.body`・`.callout`・`.subheadline`・`.footnote`・`.caption` 等のシステムスタイルを使用する。
- カスタムフォントを使用する場合は `Font.custom(_:size:relativeTo:)` で Dynamic Type に追従させる。
- **視覚的階層** を意識し、重要な情報ほど大きく・太くする。同一画面内でフォントウェイトは 2〜3 種類に絞る。
- テキストの行間・字間はシステムデフォルトを尊重し、`tracking` / `lineSpacing` の独自設定は最小限にとどめる。

  ```swift
  // ✅ Good
  Text("タイトル")
      .font(.title2)
      .fontWeight(.semibold)
  Text("説明文")
      .font(.body)
      .foregroundStyle(.secondary)
  ```

---

### 2. スペーシング・グリッド原則

- **8pt グリッド** をスペーシングの基準とする。余白・パディングには `8, 16, 24, 32` の倍数を使用する。
- マジックナンバーの直書きを禁止する。スペーシング定数を定義して使用する。

  ```swift
  // ✅ Good
  enum Spacing {
      static let xs: CGFloat = 8
      static let sm: CGFloat = 16
      static let md: CGFloat = 24
      static let lg: CGFloat = 32
  }

  VStack(spacing: Spacing.sm) { ... }
      .padding(.horizontal, Spacing.sm)
  ```

- 近い要素は近く、異なるグループは広い余白で区切る。余白でコンテンツの論理的なグループを視覚的に伝えること。

---

### 3. アニメーション・トランジション

- **`.animation(.spring(duration: 0.3), value:)`** を基本アニメーションとして使用する。線形アニメーション（`.linear`）は特別な理由がない限り使用しない。
- 画面遷移・要素の出現には **`matchedGeometryEffect`** を活用し、要素が「変容する」ヒーロートランジションを実現する。

  ```swift
  // ✅ Good — カードから詳細画面へのヒーロートランジション
  .matchedGeometryEffect(id: item.id, in: namespace)
  ```

- Liquid Glass のモーフィングには **`glassEffectID(_:in:) + withAnimation`** を組み合わせる。
- `Reduce Motion` 設定に対応し、アニメーションを簡略化できる分岐を入れる。

  ```swift
  @Environment(\.accessibilityReduceMotion) var reduceMotion

  .animation(reduceMotion ? .none : .spring(duration: 0.3), value: isExpanded)
  ```

---

### 4. カラー設計

- **セマンティックカラーを階層的に使い分ける。**
  - 最重要テキスト・アイコン: `.primary`
  - 補助テキスト・アイコン: `.secondary`
  - より補助的な情報: `.tertiary`
  - 無効状態: `.quaternary`
- アクセントカラーは `Color.accentColor` を使用し、ハードコードした RGB 値を避ける。
- **Liquid Glass の背後のコンテンツと視認性を確保する。** Liquid Glass 上にテキストを重ねる場合は `.shadow(radius:)` や `.foregroundStyle(.primary)` で読みやすさを保証する。
- カスタムカラーは必ず Assets.xcassets に Light / Dark / Increased Contrast の 3 バリアントを定義する。

---

### 5. 空状態・エラー状態のデザイン

- コンテンツが 0 件・オフライン・エラーの状態には **`ContentUnavailableView`** を使用する。独自の「空っぽ画面」を作らない。

  ```swift
  // ✅ Good
  if items.isEmpty {
      ContentUnavailableView(
          "アイテムがありません",
          systemImage: "tray",
          description: Text("新しいアイテムを追加してください。")
      )
  }

  // 検索結果が 0 件の場合
  ContentUnavailableView.search(text: searchText)
  ```

---

### 6. ローディング / スケルトン UI

- データ取得中の中間状態には **`.redacted(reason: .placeholder)`** でスケルトン表示を実現する。`ProgressView()` の全画面表示は避ける。

  ```swift
  // ✅ Good — データ取得中はプレースホルダーを表示
  ItemRowView(item: placeholderItem)
      .redacted(reason: isLoading ? .placeholder : [])
  ```

- `List` 全体のローディングには `List` + `.redacted` を組み合わせ、レイアウトシフトを防ぐ。

---

### 7. アダプティブレイアウト（共通基礎）

- コンテナに収まらない場合の代替レイアウトには **`ViewThatFits`** を使用する。

  ```swift
  // ✅ Good — 横幅が足りない場合は縦並びに自動切り替え
  ViewThatFits {
      HStack { LabelView(); ValueView() }
      VStack { LabelView(); ValueView() }
  }
  ```

- 固定幅 `frame(width: 200)` を避け、`.frame(maxWidth: .infinity)` や `.fixedSize()` を優先する。
- `GeometryReader` の過剰使用を避ける。`Layout` プロトコルや `ViewThatFits` で代替できる場合はそちらを使用する。

## コーディング規約

Swift のコーディング規約については `.github/skills/swift-coding-standards/SKILL.md` を参照すること。
