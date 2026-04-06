# プロジェクトガイドライン（iOS / iPadOS アプリ開発用）

## 前提

- **回答は必ず日本語で行うこと。**
- コードの変更をする際、変更量が200行を超える可能性が高い場合は、事前に「この指示では変更量が200行を超える可能性がありますが、実行しますか？」とユーザーに確認をとること。
- 何か大きい変更を加える場合、まず何をするのか計画を立てた上で、ユーザーに「このような計画で進めようと思います。」と提案すること。
- 各セクションに **【iPhone のみ】**・**【iPad のみ】**・**【ユニバーサルのみ】** のタグが付いた指示は、「対応デバイス」の設定に応じて以下のとおり扱うこと。
  - **「iPhone のみ」** の場合: 【iPad のみ】【ユニバーサルのみ】タグの指示は無視する
  - **「iPad のみ」** の場合: 【iPhone のみ】【ユニバーサルのみ】タグの指示は無視する
  - **「ユニバーサル」** の場合: タグに関わらずすべての指示を適用する

## プロジェクト概要

- **プロジェクト名**: NightScope
- **概要**: 星空観察支援 macOS アプリ。Open-Meteo API による天気予報・lightpollutionmap.info API による光害情報・天文計算エンジンを組み合わせて星空指数（0〜100）を算出し、月相・観測可能ウィンドウ・2週間予報を表示する。
- **対象プラットフォーム**: iOS 26.0+
- **対応デバイス**: iPhone のみ
- **最低 Deployment Target**: iOS 26.0
- **リポジトリ構成**: シングルレポ

## 技術スタック

### 推奨

| カテゴリ | 技術 / ツール | バージョン | 備考 |
|---------|-------------|-----------|------|
| 言語 | Swift | 6 | |
| IDE | Xcode | 26 | |
| プロジェクト管理 | XcodeGen | 最新 | project.yml で管理 |
| パッケージマネージャ | Swift Package Manager | | |
| UI フレームワーク | SwiftUI | iOS 26 SDK | UIKit との混在は最小限に |
| UI フレームワーク（補助） | UIKit | | SwiftUI で対応不可な場合のみ |
| アーキテクチャ | MVC | | |
| テスト | XCTest / Swift Testing | | 両フレームワーク併用可 |
| リンター / フォーマッター | SwiftLint | 最新 | .swiftlint.yml で設定 |
| アイコン作成 | Icon Composer | Xcode 26 内蔵 | レイヤー構造のアイコンを作成 |
| CI/CD | {例: GitHub Actions} | | |

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

## Apple HIG 準拠ルール

- **SF Symbols を優先使用する。** テキストラベルよりもアイコンを活用し、インターフェースをクリーンに保つ。タブバー・ツールバーでは filled バリアントを使用する。
- **システムカラー・アクセントカラーを使用する。** ハードコードされた色の代わりに `Color.accentColor` や `ShapeStyle` のセマンティックカラーを使用する。
- **ライト / ダークモードの両対応を必須とする。** カスタムカラーは Light・Dark・増加コントラスト（Increased Contrast）の各バリアントを定義する。
- **コントロールを密集・重複させない。** Liquid Glass 要素をレイヤーとして重ねない。
- **標準スペーシングメトリクスを使用する。** システムのデフォルトスペーシングを上書きしない。
- **VoiceOver / Voice Control 対応を行う。** すべてのカスタム UI に適切な `accessibilityLabel` / `accessibilityHint` を設定する。
- **Dynamic Type に対応する。** フォントには必ずシステムフォント（`.body`・`.headline` 等）または `Font.custom(_:size:relativeTo:)` を使用し、固定サイズのフォントを避ける。
- **Safe Area を尊重する。** ノッチ・Dynamic Island・ホームインジケーターの領域にインタラクティブな要素を配置しない。

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

### 6. サイズクラス対応（iPhone / iPad）

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

### 7. ハプティクス

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

### 8. 空状態・エラー状態のデザイン

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

### 9. ローディング / スケルトン UI

- データ取得中の中間状態には **`.redacted(reason: .placeholder)`** でスケルトン表示を実現する。`ProgressView()` の全画面表示は避ける。

  ```swift
  // ✅ Good — データ取得中はプレースホルダーを表示
  ItemRowView(item: placeholderItem)
      .redacted(reason: isLoading ? .placeholder : [])
  ```

- `List` 全体のローディングには `List` + `.redacted` を組み合わせ、レイアウトシフトを防ぐ。

---

### 10. アダプティブレイアウト

- コンテナに収まらない場合の代替レイアウトには **`ViewThatFits`** を使用する。

  ```swift
  // ✅ Good — 横幅が足りない場合は縦並びに自動切り替え
  ViewThatFits {
      HStack { LabelView(); ValueView() }
      VStack { LabelView(); ValueView() }
  }
  ```

- 固定幅 `frame(width: 200)` を避け、`.frame(maxWidth: .infinity)` や `.fixedSize()` を優先する。
- **`containerRelativeFrame`** で比率ベースのサイズ指定を行い、iPhone の機種差（幅 375〜440 pt）を吸収する。

  ```swift
  // ✅ Good — 画面幅の 80% を占めるカード（機種・向きに依存しない）
  CardView()
      .containerRelativeFrame(.horizontal) { size, _ in
          size * 0.8
      }
  ```

- `GeometryReader` の過剰使用を避ける。`Layout` プロトコルや `ViewThatFits` で代替できる場合はそちらを使用する。

---

### 11. キーボード・フォーカス管理

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

### 12. iPhone 画面サイズ対応テスト【iPhone のみ / ユニバーサル】

Apple 公式 HIG は「最大・最小レイアウトを先にテストせよ」と明言している。以下の機種でレイアウトを必ず確認すること。

| テスト対象 | 幅（pt） | 高さ（pt） | 確認ポイント |
|---|---|---|---|
| iPhone SE（4.7-inch） | 375 | 667 | 最小クラス。コンテンツが欠けないこと |
| iPhone 17 Pro Max | 440 | 956 | 最大クラス。横向き時 `horizontalSizeClass` = Regular |

- テキストが Safe Area 内に収まり、切れていないことを確認する。
- ボタン・コントロールが Safe Area に収まっていることを確認する。
- Dynamic Type の最大サイズ（Accessibility XL 相当）でコンテンツが崩れないことを確認する。
- 横向き（Landscape）でのレイアウトが `verticalSizeClass` に基づき正しく切り替わることを確認する。

---

## コーディング規約

Swift のコーディング規約については `skills/swift-coding-standards/SKILL.md` を参照すること。
