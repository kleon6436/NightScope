---
description: "NightScope iOS ターゲット（NightScopeiOS/）開発時に適用されるガイドライン。iOS 26 / iPhone専用 / Liquid Glass / NavigationStack / タブバー / presentationDetents / ハプティクス / サイズクラス / 画面サイズ対応に関する指示を含む。Use when: writing iOS SwiftUI code, iPhone views, iOS navigation, tab bar, sheets, haptics, size classes."
applyTo: "NightScopeiOS/**"
---

# プロジェクトガイドライン（iOS / iPadOS アプリ開発用）

## プロジェクト概要

- **プロジェクト名**: NightScope
- **概要**: 星空観察支援 iOS アプリ。Open-Meteo API による天気予報・lightpollutionmap.info API による光害情報・天文計算エンジンを組み合わせて星空指数（0〜100）を算出し、月相・観測可能ウィンドウ・2週間予報を表示する。
- **対象プラットフォーム**: iOS 26.0+
- **対応デバイス**: iPhone のみ
- **最低 Deployment Target**: iOS 26.0
- **リポジトリ構成**: シングルレポ

## 前提（iOS 固有）

- 各セクションに **【iPhone のみ】**・**【iPad のみ】**・**【ユニバーサルのみ】** のタグが付いた指示は、「対応デバイス」の設定に応じて以下のとおり扱うこと。
  - **「iPhone のみ」** の場合: 【iPad のみ】【ユニバーサルのみ】タグの指示は無視する
  - **「iPad のみ」** の場合: 【iPhone のみ】【ユニバーサルのみ】タグの指示は無視する
  - **「ユニバーサル」** の場合: タグに関わらずすべての指示を適用する

## 技術スタック

### 推奨

| カテゴリ | 技術 / ツール | バージョン | 備考 |
|---------|-------------|-----------|------|
| 言語 | Swift | 6 | |
| IDE | Xcode | 26 | |
| パッケージマネージャ | Swift Package Manager | | |
| UI フレームワーク | SwiftUI | iOS 26 SDK | UIKit との混在は最小限に |
| UI フレームワーク（補助） | UIKit | | SwiftUI で対応不可な場合のみ |
| アーキテクチャ | MVC | | |
| テスト | XCTest / Swift Testing | | 両フレームワーク併用可 |
| リンター / フォーマッター | SwiftLint | 最新 | .swiftlint.yml で設定 |
| アイコン作成 | Icon Composer | Xcode 26 内蔵 | レイヤー構造のアイコンを作成 |

### 今後追加予定

| カテゴリ | 技術 / ツール | バージョン | 備考 |
|---------|-------------|-----------|------|
| ウィジェット | WidgetKit | | ホーム画面・ロック画面ウィジェット |
| システム連携 | App Intents | | Siri / Shortcuts 対応 |

## Liquid Glass デザインガイドライン

iOS 26 / iPadOS 26 では **Liquid Glass** と呼ばれる新しいマテリアルが全プラットフォームに導入された。
ガラスの光学特性と流動性を組み合わせたこのマテリアルは、ナビゲーション要素やコントロールの機能的なレイヤーを形成する。
以下のルールを遵守して実装すること。

参考: [Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass) / [HIG](https://developer.apple.com/design/human-interface-guidelines/)

---

### 1. 基本方針

- **標準コンポーネントを最大活用する。**  
  `NavigationStack`、`NavigationSplitView`、`TabView`、ツールバー、シート、ポップオーバーなどの標準コンポーネントは Liquid Glass を自動適用するため、積極的に使用すること。

- **ナビゲーション要素へのカスタム背景適用を禁止する。**  
  タブバー・ナビゲーションバー・ツールバー・シートなどに独自の `background` / `visualEffect` を設定しない。システムの Liquid Glass を妨げるため。

- **`glassEffect` の過剰使用を禁止する。**  
  `glassEffect(_:in:)` はカスタムコントロールなど最も重要な機能要素に限定する。複数箇所への適用はコンテンツからの注意分散につながる。

- **アクセシビリティ設定でテストする。**  
  「透明度を下げる（Reduce Transparency）」「視差効果を減らす（Reduce Motion）」を有効にした状態でカスタムエフェクトが適切に変化することを確認する。
  標準コンポーネントを使っている場合は自動的に対応される。

---

### 2. ナビゲーション構造

- **iPhone** では **`NavigationStack`** を基本とする。

  ```swift
  // ✅ Good — iPhone
  NavigationStack(path: $path) {
      ContentView()
          .navigationDestination(for: Item.self) { item in
              DetailView(item: item)
          }
  }
  ```

- **【iPad のみ】** **`NavigationSplitView`** を使用し、サイドバーレイアウトを実現する。

  ```swift
  // ✅ Good — iPad
  NavigationSplitView {
      SidebarView()
  } detail: {
      DetailView()
  }
  ```

- **【iPad のみ】** インスペクターパネルは **`inspector(isPresented:content:)`** API を使用する。

  ```swift
  .inspector(isPresented: $showInspector) {
      InspectorView()
  }
  ```

- **【iPad のみ】** サイドバー・インスペクターの隣のコンテンツには **`backgroundExtensionEffect()`** を適用し、エッジトゥエッジ体験を実現する。

  ```swift
  // ✅ Good — サイドバー下にコンテンツが延びる視覚的効果
  Image("hero")
      .resizable()
      .scaledToFill()
      .backgroundExtensionEffect()
  ```

---

### 3. タブバー

iOS と iPadOS ではタブバーの挙動・配置が異なる。以下の違いを意識して実装すること。

| 項目 | iOS（iPhone） | iPadOS |
|------|--------------|--------|
| 表示位置 | 画面下部（フローティング） | 画面上部 |
| Liquid Glass | タブアイテムが Liquid Glass 背景の上に浮かぶ | 同様 |
| サイドバー変換 | 非対応 | `.sidebarAdaptable` で変換可 |
| カスタマイズ | — | `TabViewCustomization` で項目の追加・削除可 |

- タブバーベースのナビゲーションの基本実装:

  ```swift
  TabView {
      Tab("ホーム", systemImage: "house.fill") {
          HomeView()
      }
      Tab("ライブラリ", systemImage: "books.vertical.fill") {
          LibraryView()
      }
      Tab(role: .search) {
          SearchView()
      }
  }
  // 【iPad のみ】サイドバーへの自動変換を許可する
  .tabViewStyle(.sidebarAdaptable)
  ```

- **【iPad のみ】** `TabViewCustomization` でユーザーがタブ項目を追加・削除できるようにする。

- **【iPhone のみ】** スクロール時にタブバーを縮小する（`.tabBarMinimizeBehavior`）。

  ```swift
  TabView {
      // ...
  }
  .tabBarMinimizeBehavior(.onScrollDown)
  ```

- **タブバーを無効化・非表示にしない。** コンテンツが空の場合も、その理由を説明することでタブを表示し続けること。
- タブラベルは **単語単位で簡潔に** 記述する。
- タブバーアイコンには **SF Symbols の filled バリアント** を優先使用する。

---

### 4. ツールバー

- ツールバーアイテムは **機能ごとにグループ化** し、`ToolbarSpacer` で区切る。

  ```swift
  // ✅ Good — 編集系と共有系を分離
  .toolbar {
      ToolbarItemGroup(placement: .bottomBar) {
          Button("編集", systemImage: "pencil") { }
          Button("削除", systemImage: "trash") { }
      }
      ToolbarSpacer(.fixed)
      ToolbarItemGroup(placement: .bottomBar) {
          Button("共有", systemImage: "square.and.arrow.up") { }
      }
  }
  ```

- アイコンのみのツールバーアイテムには **必ず `accessibilityLabel` を設定** する。
- ツールバーアイテムの非表示には ビューの `.hidden()` ではなく **`ToolbarContent/hidden(_:)`** を使用する。
- コンテンツがスクロールする場合は **`scrollEdgeEffectStyle`** を設定してツールバーの可読性を確保する。

---

### 5. コントロール

- グラス効果のボタンは独自実装せず **`.buttonStyle(.glass)`** / **`.buttonStyle(.glassProminent)`** を活用する。

  ```swift
  // ✅ Good
  Button("追加") { }
      .buttonStyle(.glass)

  Button("確認") { }
      .buttonStyle(.glassProminent)
  ```

- カスタムコントロールの角丸は **`ConcentricRectangle`** または **`rect(corners:isUniform:)`** を使用し、デバイスのエッジ・周囲要素と同心円的に揃える。

- 複数のカスタム Liquid Glass エフェクトは **`GlassEffectContainer`** でまとめ、各ビューに **`glassEffectID(_:in:)`** を付与する（パフォーマンス最適化 + モーフィングアニメーション）。

  ```swift
  // ✅ Good
  GlassEffectContainer {
      ForEach(items) { item in
          ItemView(item: item)
              .glassEffect(.regular, in: .capsule)
              .glassEffectID(item.id, in: namespace)
      }
  }
  ```

---

### 6. シート・モーダル

- iOS 26 のシートは **角丸が増加** し、ハーフシートは画面端からインセット表示される。
  コンテンツが角丸付近に重ならないよう余白を確保すること。

- **`presentationDetents`** で適切なサイズ制御を行う。

  ```swift
  .sheet(isPresented: $showSheet) {
      SheetContentView()
          .presentationDetents([.medium, .large])
          .presentationDragIndicator(.visible)
  }
  ```

- シート・ポップオーバーのカスタム背景ビュー（`visualEffectView` 等）は **削除** し、システムの Liquid Glass 背景に委ねる。

- アクションシートは **`confirmationDialog`** を使用し、`presenting` パラメーターで起点コントロールを指定する。

  ```swift
  .confirmationDialog(
      "操作を選択",
      isPresented: $showDialog,
      titleVisibility: .visible,
      presenting: selectedItem
  ) { item in
      Button("削除", role: .destructive) { delete(item) }
      Button("共有") { share(item) }
  }
  ```

---

### 7. リスト・フォーム

- フォームには **`.formStyle(.grouped)`** を使用してプラットフォームのレイアウトメトリクスに自動準拠する。

  ```swift
  Form {
      Section("設定") {
          Toggle("通知", isOn: $notificationsEnabled)
          Slider(value: $volume, in: 0...1)
      }
  }
  .formStyle(.grouped)
  ```

- `Section` ヘッダーは **タイトルスタイルの大文字化**（Title Case）で記述する。ALL CAPS は使用しない。
- コンテキストメニューの先頭アクションと、スワイプアクションの先頭アクションを **一致** させる。

  ```swift
  // ✅ Good — スワイプとコンテキストメニューで同じ「削除」を先頭に
  .swipeActions(edge: .trailing, allowsFullSwipe: true) {
      Button("削除", role: .destructive) { delete(item) }
  }
  .contextMenu {
      Button("削除", role: .destructive) { delete(item) }
      Button("共有") { share(item) }
  }
  ```

---

### 8. 検索

- 検索タブは **`Tab(role: .search)`** で定義し、システムが自動的にトレーリング端に配置するようにする。

  ```swift
  Tab(role: .search) {
      SearchView()
  }
  ```

- **iPhone** では検索フィールドをボトムツールバー内に配置する。  
  **iPad** では画面上部のトレーリング端に自動配置される。

- 検索フィールドがフォーカスを受け取るとキーボードが表示され、フィールドが上方にスライドする。この挙動が他のアプリ・システム体験と一致しているかテストすること。

---

### 9. アプリアイコン

- **Icon Composer**（Xcode 26 内蔵）でレイヤー構造のアイコンを作成する。
  - レイヤー構成: 前景 / 中景 / 背景（システムが反射・屈折・シャドウ・ブラーを自動適用）
  - 不規則な形状のアイコンにはシステムが自動でバックグラウンドを付与する
- 以下の4バリアントをすべて提供する:
  - Default（Light）
  - Dark
  - Clear
  - Tinted
- 要素はアイコン中央に配置し、iOS の角丸クリッピングを考慮する（重要な要素が端に寄らないようにする）。

## iOS 固有 UI レイアウト原則

---

### コンテンツファーストレイアウト

- Liquid Glass の思想は「コンテンツをナビゲーション要素の背後から透かして見せる」こと。コンテンツをフルブリードで配置し、ナビゲーション要素が浮かぶ構造を意識する。
- ヒーローイメージなど没入感を高めたいコンテンツには **`ignoresSafeArea(.container, edges: .top)`** を適用する。

  ```swift
  // ✅ Good — 上部までコンテンツを広げ、タブバー背後からも見せる
  ScrollView {
      HeroImageView()
          .ignoresSafeArea(.container, edges: .top)
      ContentSection()
  }
  ```

- コンテンツが Liquid Glass 要素（タブバー・ナビゲーションバー）の背後に自然にスクロールするよう、`contentMargins` や `safeAreaPadding` を適切に設定する。

---

### サイズクラス対応（iPhone / iPad）

- `@Environment(\.horizontalSizeClass)` でレイアウト幅クラスを判定する。Apple 公式仕様に基づく対応表：
  - **Compact 幅**: iPhone（縦横とも）、iPad 縦向きの狭いウィンドウ
  - **Regular 幅**: iPad 横向き・広いウィンドウ、**iPhone Pro Max / Plus の横向き**

  ```swift
  @Environment(\.horizontalSizeClass) var horizontalSizeClass

  var body: some View {
      if horizontalSizeClass == .compact {
          // iPhone 縦横 / iPad 縦: 1カラムレイアウト
          VStack { ... }
      } else {
          // iPad 横 / iPhone Pro Max 横: 2カラム以上のレイアウト
          HStack { ... }
      }
  }
  ```

- iPhone の縦向き・横向き切替には `@Environment(\.verticalSizeClass)` を使用する。
  - 縦向き（Portrait）: `verticalSizeClass == .regular`
  - 横向き（Landscape）: `verticalSizeClass == .compact`（**すべての iPhone モデルで共通**）

  ```swift
  @Environment(\.verticalSizeClass) var verticalSizeClass

  var body: some View {
      if verticalSizeClass == .compact {
          // iPhone 横向き: 水平方向に広いレイアウト
          HStack { ContentArea(); ControlPanel() }
      } else {
          // 縦向き: 通常の縦スクロールレイアウト
          VStack { ContentArea(); ControlPanel() }
      }
  }
  ```

- Compact では縦スクロール 1 カラム、Regular では 2 カラム以上を基本とする。
- HStack / VStack を自動切り替えする `AdaptiveStack` を共通コンポーネントとして定義することを推奨する。

---

### ハプティクス

- SwiftUI の **`.sensoryFeedback(_:trigger:)`** モディファイアを使用する。`UIImpactFeedbackGenerator` は SwiftUI で対応不可な場合のみ許可する。

  ```swift
  // ✅ Good
  Button("削除") { delete() }
      .sensoryFeedback(.warning, trigger: isDeleted)

  Toggle("通知", isOn: $enabled)
      .sensoryFeedback(.selection, trigger: enabled)
  ```

- アクションの種類とフィードバックの対応:
  - 成功・完了: `.success`
  - 警告・削除: `.warning`
  - エラー: `.error`
  - 選択変更: `.selection`
  - 軽いタップ: `.impact(weight: .light)`

---

### アダプティブレイアウト（iOS）

- **`containerRelativeFrame`** で比率ベースのサイズ指定を行い、iPhone の機種差（幅 375〜440 pt）を吸収する。

  ```swift
  // ✅ Good — 画面幅の 80% を占めるカード（機種・向きに依存しない）
  CardView()
      .containerRelativeFrame(.horizontal) { size, _ in
          size * 0.8
      }
  ```

---

### キーボード・フォーカス管理

- **`@FocusState`** でキーボードフォーカスを明示的に管理する（iPhone・iPad 共通）。

  ```swift
  @FocusState private var isFieldFocused: Bool

  TextField("名前", text: $name)
      .focused($isFieldFocused)
  ```

- **【iPad のみ】** 外部キーボード利用を想定し、主要アクションには **`KeyboardShortcut`** を割り当てる。

  ```swift
  Button("新規作成") { createItem() }
      .keyboardShortcut("n", modifiers: .command)

  Button("保存") { save() }
      .keyboardShortcut("s", modifiers: .command)
  ```

---

### iPhone 画面サイズ対応テスト【iPhone のみ / ユニバーサル】

Apple 公式 HIG は「最大・最小レイアウトを先にテストせよ」と明言している。以下の機種でレイアウトを必ず確認すること。

| テスト対象 | 幅（pt） | 高さ（pt） | 確認ポイント |
|---|---|---|---|
| iPhone SE（4.7-inch） | 375 | 667 | 最小クラス。コンテンツが欠けないこと |
| iPhone 17 Pro Max | 440 | 956 | 最大クラス。横向き時 `horizontalSizeClass` = Regular |

- テキストが Safe Area 内に収まり、切れていないことを確認する。
- ボタン・コントロールが Safe Area に収まっていることを確認する。
- Dynamic Type の最大サイズ（Accessibility XL 相当）でコンテンツが崩れないことを確認する。
- 横向き（Landscape）でのレイアウトが `verticalSizeClass` に基づき正しく切り替わることを確認する。
