# NightScope

NightScope は、星空観測向けの macOS / iOS アプリです。  
観測地点・天候・光害・天体情報をまとめて確認し、観測に向いた時間帯を判断しやすくすることを目的としています。

> [!IMPORTANT]
> このドキュメントの「外部データ利用条件」は実装・運用上の整理です。法的助言ではありません。

## 対応プラットフォーム

- macOS (`NightScope`)
- iOS (`NightScopeiOS`)

## 主な機能

- 観測地点ベースの星空観測指標表示
- 光害情報の参照
- 天気予報（観測向け情報）
- 天体表示・観測時間帯の補助情報

## クイックスタート

前提:

- Xcode がインストール済み
- macOS で `xcodebuild` が利用可能

### macOS ビルド

- `xcodebuild -quiet -project NightScope.xcodeproj -scheme NightScope -destination 'platform=macOS' build`

### macOS テスト

- `xcodebuild -quiet -project NightScope.xcodeproj -scheme NightScope -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO test`

### iOS (Simulator) ビルド

- `xcodebuild -quiet -project NightScope.xcodeproj -scheme NightScopeiOS -destination 'generic/platform=iOS Simulator' build`

## プロジェクト構成（抜粋）

- `NightScope/Controllers/` : 外部API取得・計算ロジック
- `NightScope/Models/` : ドメインモデル
- `NightScope/ViewModels/` : 表示用ロジック
- `NightScope/Views/` : SwiftUIビュー
- `NightScopeTests/` : 単体テスト

## 外部データソースとクレジット

NightScope は以下の外部データ/サービスを利用しています。

| サービス / データ | 用途 | 主な帰属・出典 | 現状判定（個人利用） | 将来商用化時アクション |
|---|---|---|---|---|
| Open-Meteo | 天気予報取得 | Open-Meteo を出典表記 | 条件付きで利用可 | 商用プラン/規約条件を再確認 |
| Nominatim / OpenStreetMap | 逆ジオコーディング・地名補助 | `© OpenStreetMap contributors` + https://www.openstreetmap.org/copyright | 条件付きで利用可 | レート制限順守確認、必要に応じ代替/自己ホスト検討 |
| lightpollutionmap.info | 光害タイル/WMS・光害値参照 | `Jurij Stare, www.lightpollutionmap.info`（必要時 NASA Black Marble 併記） | 条件付きで利用可 | 商用前に利用許諾確認（推奨）または代替ソース方針確定 |
| Open-Elevation | 標高取得 | Open-Elevation を出典表記 | 条件付きで利用可 | 利用量増加時の運用（キャッシュ/代替）を検討 |
| Yale Bright Star Catalogue (BSC5 / CDS V/50) | 星カタログ生成 | BSC5 / CDS V/50 を出典表記 | 条件付きで利用可 | 再配布・商用条件を再確認 |

## 利用上の注意（個人利用 / 将来商用）

### 個人利用（現状）

- 現在の実装範囲では、**各サービスの条件を守る前提で利用可能**という整理です。
- ただし帰属表示や利用制限順守は必須です。

### 将来商用化

- 商用配布・課金・法人利用を開始する前に、各データソースの利用規約を再確認してください。
- 特に `lightpollutionmap.info` は、商用利用時の確認を事前に行うことを推奨します。

## 商用化前チェックリスト

- [ ] Open-Meteo の商用利用条件/契約要否を確認
- [ ] OSM/Nominatim の利用ポリシー（レート・識別可能UA・帰属）を満たしている
- [ ] lightpollutionmap.info の利用許諾（または代替データ計画）を確定
- [ ] Open-Elevation の利用量・可用性に対する運用方針（キャッシュ等）を定義
- [ ] BSC5 の再配布・商用利用条件を再確認
- [ ] README とアプリ内表示（設定画面など）で帰属が明示されている

## 開発メモ

- API利用規約は変更される可能性があるため、リリース前に再確認してください。
- 本READMEの内容は 2026-04-11 時点の実装/調査に基づきます。
