---
description: "NightScope macOS ターゲット（NightScope/、NightScopeTests/）開発時に適用されるガイドライン。macOS Tahoe / Liquid Glass / NavigationSplitView / キーボードショートカット / ウィンドウ管理 / macOS固有UIに関する指示を含む。Use when: writing macOS SwiftUI code, macOS views, macOS app architecture, AppController, sidebar layout."
applyTo: ["NightScope/**", "NightScopeTests/**"]
---

# プロジェクトガイドライン（macOS Tahoe アプリ開発用）

## プロジェクト概要

- **プロジェクト名**: NightScope
- **概要**: 星空観察支援 macOS アプリ。MET Norway Locationforecast 2.0 による天気予報・Falchi 光害アトラス（バンドル）による光害情報・NASA SRTM（バンドル）による標高データ・天文計算エンジンを組み合わせて星空指数（0〜100）を算出し、月相・観測可能ウィンドウ・2週間予報グリッドを表示する。
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
  **例外**: 没入型コンテンツアプリ（写真・地図・星空観察など）では `.toolbarBackground(.hidden, for: .windowToolbar)` を使用し、コンテンツをツールバー背後まで広げるディストラクションフリーなデザインが適切な場合がある。Apple HIG も「Consider temporarily hiding toolbars for a distraction-free experience」として明示的に許容している。NightScope はこの例外に該当するため、`DetailView` での `.toolbarBackground(.hidden)` は意図的な設計として維持する。

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

## macOS 固有 UI レイアウト原則

---

### コンテンツファーストレイアウト

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

### アダプティブレイアウト（macOS）

- ウィンドウのリサイズに追従するよう、`NavigationSplitView` の列幅は固定しない。

---

### キーボードショートカット・フォーカス管理

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
