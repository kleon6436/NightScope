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

- `xcodebuild -quiet -project NightScope.xcodeproj -target NightScopeiOS -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build`

## プロジェクト構成（抜粋）

- `NightScope/Controllers/` : 外部API取得・計算ロジック
- `NightScope/Models/` : ドメインモデル
- `NightScope/Data/` : バンドルするJSON / バイナリデータ
- `NightScope/ViewModels/` : 表示用ロジック
- `NightScope/Views/` : SwiftUIビュー
- `NightScopeTests/` : 単体テスト

## 外部データソースとクレジット

NightScope は以下の外部データ/サービスを利用しています。

| サービス / データ | 用途 | 主な帰属・出典 | ライセンス | 取得方法 |
|---|---|---|---|---|
| Apple WeatherKit | 天気予報取得 | Apple Inc. — https://developer.apple.com/weatherkit/ | Apple Weather Terms of Service | 実行時 API（ネットワーク必須） |
| Falchi et al. 2016 – World Atlas of Artificial Night Sky Brightness | 光害マップ | Falchi, F. et al. (2016) / GFZ Data Services — https://doi.org/10.5880/GFZ.1.4.2016.001 | CC BY 4.0 | バンドルバイナリ（`bortle_map.bin`、`Tools/generate_bortle_map.py` で生成） |
| Copernicus DEM GLO-30 | 地形・標高データ | Copernicus DEM (DLR/ESA) — https://dataspace.copernicus.eu | CC BY 4.0 | バンドルバイナリ（`elevation_global.bin.z`, `elevation_japan.bin.z`、`Tools/prepare_srtm.py` で生成） |
| Yale Bright Star Catalogue (BSC5 / CDS V/50) | 星カタログ | Yale BSC5 / CDS VizieR — https://vizier.cds.unistra.fr/viz-bin/VizieR-3?-source=V/50 | Public Domain | バンドル JSON（`stars_fill.json`、`Tools/generate_stars.py` で生成） |
| d3-celestial constellation data | 星座線・星座ラベル基準点 | Olaf Frohn / d3-celestial — https://github.com/ofrohn/d3-celestial | BSD 3-Clause | バンドル JSON（`constellations_iau.json`、`Tools/generate_constellations.py` で生成） |
| Apple MapKit (MKReverseGeocodingRequest) | 逆ジオコーディング・地名取得 | Apple Inc. | Apple Developer Program 規約 | システムフレームワーク（ネットワーク不要） |

## バンドルデータの準備手順

### bortle_map.bin（光害データ）

```bash
pip install numpy scipy
python3 Tools/generate_bortle_map.py \
    --output NightScope/Data/bortle_map.bin
```

### constellations_iau.json（星座線データ）

```bash
python3 Tools/generate_constellations.py \
    --output NightScope/Data/constellations_iau.json
```

> [!NOTE]
> `Tools/generate_constellations.py` は d3-celestial の commit `7e720a3de062059d4c5400a379146a601d9010e0` に固定して生成します。将来データを更新する場合は、更新対象 commit と差分確認結果を README または PR に明記してください。

> [!IMPORTANT]
> d3-celestial (BSD 3-Clause) notice: Copyright (c) Olaf Frohn. Redistribution and use in source and binary forms, with or without modification, are permitted provided that the copyright notice, license conditions, and disclaimer are retained. This software is provided "as is", without warranties or conditions of any kind.

### elevation_global.bin.z / elevation_japan.bin.z（地形データ）

`prepare_srtm.py` は Copernicus DEM を使って地形バイナリを生成します。

```bash
pip install rasterio numpy scipy

# Copernicus DEM（全球）
python3 Tools/prepare_srtm.py --resolution 0.05 \
    --compress --output NightScope/Data/elevation_global.bin.z

# Copernicus DEM（日本高解像度）
python3 Tools/prepare_srtm.py --region japan --resolution 0.01 \
    --compress --output NightScope/Data/elevation_japan.bin.z
```

ローカルに GeoTIFF / .hgt タイルがある場合:
```bash
python3 Tools/prepare_srtm.py --input-dir ~/dem_tiles/ \
    --output NightScope/Data/elevation_global.bin --resolution 0.1
```

> [!NOTE]
> `elevation_global.bin(.z)` / `elevation_japan.bin(.z)` が存在しない場合、`TerrainService` は nil を返し地形データなし（平坦地扱い）で動作します。ビルド・実行は可能ですが、地平線障害物の計算は行われません。

## 利用上の注意（個人利用 / 将来商用）

### 現在採用しているデータソースのライセンス概要

| データソース | ライセンス | 商用利用 | 主な要件 |
|---|---|---|---|
| Apple WeatherKit | Apple Weather Terms of Service | ✅ 可（Apple Developer Program 規約範囲内） | Apple Developer Program への参加 |
| Falchi et al. 2016 World Atlas | CC BY 4.0 | ✅ 可 | 帰属表示（論文・DOI の明示） |
| Yale BSC5 / CDS VizieR | Public Domain | ✅ 可 | 帰属表示（推奨） |
| d3-celestial constellation data | BSD 3-Clause | ✅ 可 | ライセンス表示・著作権表示 |
| Apple MapKit | Apple Developer Program 規約 | ✅ 可（規約の範囲内） | Apple Developer Program への参加 |

全データソースが **Apple Weather Terms of Service / CC BY 4.0 / Public Domain / BSD 3-Clause / Apple Developer Program 規約**で構成されており、商用配布・課金・法人利用においても各規約の条件を守ることで利用可能な状態です。

### App Store 公開向けの補足

- WeatherKit は **天気データを表示する画面ごとに Apple Weather の帰属表示**が必要です。NightScope では主要な天気表示ビューと設定画面で `WeatherAttributionBadge` を表示しています。
- Falchi データは CC BY 4.0 のため、**著者名・出典・DOI・ライセンス**をアプリ内と配布物で明示してください。
- Copernicus DEM は CC BY 4.0 相当の扱いとして、**Copernicus / EU / ESA(DLR) 系の帰属**を配布物にも含めてください。
- d3-celestial は BSD 3-Clause のため、**著作権表示・条件・免責**を保持してください。
- Apple MapKit / WeatherKit は Apple Developer Program 規約に従い、取得データを独自 API や再配布データとして扱わないでください。

### 個人利用（現状）

- 各データソースの条件を守る前提で利用可能です。
- WeatherKit は Apple Developer Program への参加が必須です（`WeatherKitService` で対応済み）。
- 帰属表示はアプリ内「設定 > データソースとクレジット」で行っています。

### 商用化時の確認事項

- Apple WeatherKit の利用規約（Apple Weather Terms of Service）に変更がないことを確認してください。
- CC BY 4.0 データソースの帰属表示がアプリ内・配布物（App Store ページ等）に含まれていることを確認してください。
- Apple Developer Program 規約の最新版を確認してください。

## 商用化前チェックリスト

- [ ] Apple WeatherKit の利用規約（Apple Weather Terms of Service）に変更がないことを確認
- [ ] Falchi World Atlas (CC BY 4.0) の帰属表示（Falchi et al. 2016 / GFZ Data Services / DOI）がアプリ内・配布物に含まれている
- [ ] Yale BSC5 の帰属表示が設定画面に含まれている
- [ ] d3-celestial constellation data (BSD 3-Clause) の帰属表示が設定画面や配布物に含まれている
- [ ] Apple MapKit の利用が Apple Developer Program 規約の範囲内であることを確認
- [ ] README とアプリ内「設定 > データソースとクレジット」で全帰属が明示されている

## App Store 公開準備の実装状況

| 項目 | 状況 | 備考 |
|---|---|---|
| WeatherKit 帰属表示 | ✅ 実装済み | 主要な天気表示ビューと設定画面で表示 |
| 外部データソースのクレジット | ✅ 実装済み | 設定画面と README に記載 |
| Privacy Manifest | ✅ 実装済み | `NightScope/PrivacyInfo.xcprivacy` を両ターゲットに同梱 |
| Required Reason API | ✅ 実装済み | `UserDefaults` に対して `CA92.1` を申告 |
| Export Compliance | ✅ 実装済み | `ITSAppUsesNonExemptEncryption = NO` を設定 |
| App Privacy Details | ⏳ 手動 | App Store Connect で位置情報利用を実態どおり入力 |
| サポート URL / プライバシーポリシー URL | ⏳ 手動 | 公開 URL を用意して App Store Connect に設定 |
| 有料アプリ契約 / 税務 / 銀行口座 | ⏳ 手動 | Paid Apps Agreement と価格設定が必要 |
| App Store Connect アプリ作成 | ⏳ 手動 | Bundle ID 確定後に作成 |
| スクリーンショット / 説明文 / 審査メモ | ⏳ 草案あり | 下記を初稿として使用可能 |

## App Store Connect 入力草案

### 説明文（初稿）

NightScope は、星空観測に必要な情報を iPhone と Mac でまとめて確認できるアプリです。観測地点ごとの天気、光害、天体情報、観測に向いた時間帯をひとつの画面で把握できます。

- 現在地や任意の地点を選んで観測条件を確認
- Apple WeatherKit による夜間の天気情報を表示
- 光害マップと地形データをもとに観測環境を補助表示
- 星図、観測時間帯、今後の観測候補日を一覧化

### サブタイトル候補

- 星空観測に向く時間と場所をすばやく確認

### キーワード候補

星空,天体観測,天気,光害,星図,夜空,天文

### 審査メモ草案

- 本アプリはログイン不要です。
- 位置情報は現在地の観測条件表示のためにのみ使用します。
- iPhone 版では、星図を実景に重ねる機能のためにカメラとモーションセンサーを使用します。
- 天気データは Apple WeatherKit を利用しています。
- 光害・地形・星カタログデータはアプリ内バンドルデータを使用しています。

## App Store 公開前の手動チェック

1. Bundle ID を最終確定する（現状: `com.kleon.NightScope` / `com.kleon.NightScopeiOS`）。
2. App Store Connect で macOS / iOS のアプリレコードを作成する。
3. 有料アプリ用の契約、税務情報、銀行口座、価格を設定する。
4. Support URL と Privacy Policy URL を公開し、App Store Connect に登録する。
5. App Privacy Details に位置情報の利用目的を実態どおり入力する。
6. iPhone / macOS のスクリーンショットを Release Archive 相当のビルドから撮影する。
7. Archive を作成し、Organizer の Validate App / privacy report を確認する。

## 開発メモ

- API 利用規約は変更される可能性があるため、リリース前に再確認してください。
- 本 README の内容は 2026-04-25 時点の実装/調査に基づきます。
