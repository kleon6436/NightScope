# プロジェクトガイドライン（macOS Tahoe アプリ開発用）

## 前提

- **回答は必ず日本語で行うこと。**
- コードの変更をする際、変更量が200行を超える可能性が高い場合は、事前に「この指示では変更量が200行を超える可能性がありますが、実行しますか？」とユーザーに確認をとること。
- 何か大きい変更を加える場合、まず何をするのか計画を立てた上で、ユーザーに「このような計画で進めようと思います。」と提案すること。

## プロジェクト概要

- **プロジェクト名**: NightScope
- **概要**: 星空観察支援 macOS アプリ。Open-Meteo API による天気予報・lightpollutionmap.info API による光害情報・天文計算エンジンを組み合わせて星空指数（0〜100）を算出し、月相・観測可能ウィンドウ・2週間予報グリッドを表示する。
- **対象プラットフォーム**: macOS 26（macOS Tahoe）以上
- **最低 Deployment Target**: macOS 26.0
- **リポジトリ構成**: シングルレポ。`NightScope/`（Views・Controllers・Models）・`NightScopeTests/`（単体テスト）の2ターゲット構成。

## 技術スタック

| カテゴリ | 技術 / ツール | バージョン | 備考 |
|---------|-------------|-----------|------|
| 言語 | Swift | 6 | |
| IDE | Xcode | 26 | |
| パッケージマネージャ | Swift Package Manager | | |
| UI フレームワーク | SwiftUI | macOS 26 SDK | AppKit との混在は最小限に |
| アーキテクチャ | MVVM | | `AppController` が ViewModel として機能 |
| テスト | XCTest / Swift Testing | | 両フレームワーク併用可 |
| アイコン作成 | Icon Composer | Xcode 26 内蔵 | レイヤー構造のアイコンを作成 |

## Liquid Glass デザインガイドライン

macOS Tahoe では **Liquid Glass** と呼ばれる新しいマテリアルが全プラットフォームに導入された。
ガラスの光学特性と流動性を組み合わせたこのマテリアルは、ナビゲーション要素やコントロールの機能的なレイヤーを形成する。
以下のルールを遵守して実装すること。

参考: [Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass) / [HIG](https://developer.apple.com/design/human-interface-guidelines/)

---

### 1. 基本方針

- **標準コンポーネントを最大活用する。**  
  `NavigationSplitView`、`NavigationStack`、ツールバー、シート、ポップオーバーなどの標準コンポーネントは Liquid Glass を自動適用するため、積極的に使用すること。

- **ナビゲーション要素へのカスタム背景適用を禁止する。**  
  サイドバー・ツールバー・タブバー・シートなどに独自の `background` / `visualEffect` を設定しない。システムの Liquid Glass を妨げるため。

- **`glassEffect` の過剰使用を禁止する。**  
  `glassEffect(_:in:)` はカスタムコントロールなど最も重要な機能要素に限定する。複数箇所への適用はコンテンツからの注意分散につながる。

- **アクセシビリティ設定でテストする。**  
  「透明度を下げる（Reduce Transparency）」「視差効果を減らす（Reduce Motion）」を有効にした状態でカスタムエフェクトが適切に変化することを確認する。
  標準コンポーネントを使っている場合は自動的に対応される。

---

### 2. ナビゲーション構造

- サイドバーレイアウトには **`NavigationSplitView`** を使用する。

  ```swift
  // ✅ Good
  NavigationSplitView {
      SidebarView()
  } detail: {
      DetailView()
  }
  ```

- インスペクターパネルは **`inspector(isPresented:content:)`** API を使用する。

  ```swift
  .inspector(isPresented: $showInspector) {
      InspectorView()
  }
  ```

- サイドバー・インスペクターの隣のコンテンツには **`backgroundExtensionEffect()`** を適用し、エッジトゥエッジ体験を実現する。

  ```swift
  // ✅ Good — サイドバー下にコンテンツが延びる視覚的効果
  Image("hero")
      .resizable()
      .scaledToFill()
      .backgroundExtensionEffect()
  ```

- タブビューには **`sidebarAdaptable`** スタイルを採用し、文脈に応じてサイドバーへ自動変換させる。

  ```swift
  TabView {
      Tab("Home", systemImage: "house") { HomeView() }
      Tab(role: .search) { SearchView() }
  }
  .tabViewStyle(.sidebarAdaptable)
  ```

---

### 3. ツールバー

- ツールバーアイテムは **機能ごとにグループ化** し、`ToolbarSpacer` で区切る。

  ```swift
  // ✅ Good — 編集系と情報系を分離
  .toolbar {
      ToolbarItemGroup(placement: .primaryAction) {
          Button("Undo", systemImage: "arrow.uturn.backward") { }
          Button("Redo", systemImage: "arrow.uturn.forward") { }
      }
      ToolbarSpacer(.fixed)
      ToolbarItemGroup(placement: .primaryAction) {
          Button("Share", systemImage: "square.and.arrow.up") { }
      }
  }
  ```

- アイコンのみのツールバーアイテムには **必ず `accessibilityLabel` を設定** する。
- ツールバーアイテムの非表示には ビューの `.hidden()` ではなく **`ToolbarContent/hidden(_:)`** を使用する。
- コンテンツがスクロールする場合は **`scrollEdgeEffectStyle`** を設定してツールバーの可読性を確保する。

---

### 4. コントロール

- グラス効果のボタンは独自実装せず **`.buttonStyle(.glass)`** / **`.buttonStyle(.glassProminent)`** を活用する。

  ```swift
  // ✅ Good
  Button("追加") { }
      .buttonStyle(.glass)

  Button("確認") { }
      .buttonStyle(.glassProminent)
  ```

- カスタムコントロールの角丸は **`ConcentricRectangle`** または **`rect(corners:isUniform:)`** を使用し、ウィンドウ・周囲要素と同心円的に揃える。

- 複数のカスタム Liquid Glass エフェクトは **`GlassEffectContainer`** でまとめ、各ビューに **`glassEffectID(_:in:)`** を付与する（パフォーマンス最適化 + モーフィングアニメーション）。

  ```swift
  // ✅ Good — バッジ群のようなグラスエフェクト集合
  GlassEffectContainer {
      ForEach(badges) { badge in
          BadgeView(badge: badge)
              .glassEffect(.regular, in: .circle)
              .glassEffectID(badge.id, in: namespace)
      }
  }
  ```

---

### 5. シート・モーダル

- シート・ポップオーバーのカスタム背景ビュー（`visualEffectView` 等）は **削除** し、システムの Liquid Glass 背景に委ねる。
- アクションシートは **`confirmationDialog`** を使用し、`presenting:` パラメーターで表示トリガーとなるデータを指定する。

  ```swift
  .confirmationDialog(
      "操作を選択",
      isPresented: $showDialog,
      titleVisibility: .visible,
      presenting: selectedItem
  ) { item in
      Button("削除", role: .destructive) { delete(item) }
  }
  ```

- シート内のコンテンツ・コントロールが角丸シートのコーナー付近に重ならないよう余白を確保する。

---

### 6. リスト・フォーム

- フォームには **`.formStyle(.grouped)`** を使用してプラットフォームのレイアウトメトリクスに自動準拠する。

  ```swift
  Form {
      Section("設定") {
          Toggle("通知", isOn: $notificationsEnabled)
      }
  }
  .formStyle(.grouped)
  ```

- `Section` ヘッダーは **タイトルスタイルの大文字化**（Title Case）で記述する。ALL CAPS は使用しない。

---

### 7. 検索

- 検索タブは **`Tab(role: .search)`** で定義し、システムが自動的にトレーリング端に配置するようにする。

  ```swift
  Tab(role: .search) {
      SearchView()
  }
  ```

---

### 8. ウィンドウ

- ウィンドウは任意サイズへのリサイズをサポートし、適切な最小サイズを設定する。
- `NavigationSplitView` を使用することでリサイズ時のフルードトランジションを自動取得できる。
- `safeAreaInsets` / レイアウトガイドを正しく設定し、ウィンドウコントロールとタイトルバーの重なりを防ぐ。

---

### 9. アプリアイコン

- **Icon Composer**（Xcode 26 内蔵）でレイヤー構造のアイコンを作成する。
  - レイヤー構成: 前景 / 中景 / 背景（システムが反射・屈折・シャドウ・ブラーを自動適用）
  - 不規則な形状のアイコンにはシステムが自動でバックグラウンドを付与する
- 以下の6バリアントを提供する（提供しないバリアントはシステムが自動生成する）:
  - Default（Light）
  - Dark
  - Clear（Light）
  - Clear（Dark）
  - Tinted（Light）
  - Tinted（Dark）
- 要素はアイコン中央に配置し、角丸クリッピングを考慮する。

## Apple HIG 準拠ルール

- **SF Symbols を優先使用する。** テキストラベルよりもアイコンを活用し、インターフェースをクリーンに保つ。
- **システムカラー・アクセントカラーを使用する。** ハードコードされた色の代わりに `Color.accentColor` や `ShapeStyle` のセマンティックカラーを使用する。
- **ライト / ダークモードの両対応を必須とする。** カスタムカラーは Light・Dark・増加コントラスト（Increased Contrast）の各バリアントを定義する。
- **コントロールを密集・重複させない。** Liquid Glass 要素をレイヤーとして重ねない。
- **標準スペーシングメトリクスを使用する。** システムのデフォルトスペーシングを上書きしない。
- **VoiceOver / Voice Control 対応を行う。** すべてのカスタム UI に適切な `accessibilityLabel` / `accessibilityHint` を設定する。

## UI レイアウト・ビジュアルデザイン原則

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

### 3. コンテンツファーストレイアウト

- Liquid Glass の思想は「コンテンツをナビゲーション要素の背後から透かして見せる」こと。コンテンツをフルブリードで配置し、ナビゲーション要素が浮かぶ構造を意識する。
- サイドバー・インスペクター隣のコンテンツには **`backgroundExtensionEffect()`** を適用し、エッジトゥエッジ体験を実現する。

  ```swift
  // ✅ Good — サイドバー下にコンテンツが延びる視覚的効果
  Image("hero")
      .resizable()
      .scaledToFill()
      .backgroundExtensionEffect()
  ```

- コンテンツが Liquid Glass 要素（ツールバー・サイドバー）の背後に自然にスクロールするよう、`scrollEdgeEffectStyle` と `safeAreaInsets` を適切に設定する。

---

### 4. アニメーション・トランジション

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

### 5. カラー設計

- **セマンティックカラーを階層的に使い分ける。**
  - 最重要テキスト・アイコン: `.primary`
  - 補助テキスト・アイコン: `.secondary`
  - より補助的な情報: `.tertiary`
  - 無効状態: `.quaternary`
- アクセントカラーは `Color.accentColor` を使用し、ハードコードした RGB 値を避ける。
- **Liquid Glass の背後のコンテンツと視認性を確保する。** Liquid Glass 上にテキストを重ねる場合は `.shadow(radius:)` や `.foregroundStyle(.primary)` で読みやすさを保証する。
- カスタムカラーは必ず Assets.xcassets に Light / Dark / Increased Contrast の 3 バリアントを定義する。

---

### 6. 空状態・エラー状態のデザイン

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

### 7. ローディング / スケルトン UI

- データ取得中の中間状態には **`.redacted(reason: .placeholder)`** でスケルトン表示を実現する。`ProgressView()` の全画面表示は避ける。

  ```swift
  // ✅ Good — データ取得中はプレースホルダーを表示
  ItemRowView(item: placeholderItem)
      .redacted(reason: isLoading ? .placeholder : [])
  ```

- `List` 全体のローディングには `List` + `.redacted` を組み合わせ、レイアウトシフトを防ぐ。

---

### 8. アダプティブレイアウト

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
- ウィンドウのリサイズに追従するよう、`NavigationSplitView` の列幅は固定しない。

---

### 9. キーボードショートカット・フォーカス管理

- macOS はキーボードファーストのプラットフォームである。主要アクションには必ず **`KeyboardShortcut`** を割り当てる。

  ```swift
  Button("新規作成") { createItem() }
      .keyboardShortcut("n", modifiers: .command)

  Button("保存") { save() }
      .keyboardShortcut("s", modifiers: .command)

  Button("削除") { delete() }
      .keyboardShortcut(.delete, modifiers: .command)
  ```

- **`@FocusState`** でフォーカスを明示的に管理し、Tab キーによるフォーカス移動が論理的な順序になるよう設計する。

  ```swift
  @FocusState private var focusedField: Field?

  TextField("名前", text: $name)
      .focused($focusedField, equals: .name)
  TextField("説明", text: $description)
      .focused($focusedField, equals: .description)
  ```

- メニューバーアイテムのキーボードショートカットは標準的な macOS の慣習（⌘N, ⌘S, ⌘W 等）に従う。

## コーディング規約

Swift のコーディング規約については `skills/swift-coding-standards/SKILL.md` を参照すること。
