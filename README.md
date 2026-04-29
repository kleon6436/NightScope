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

## 利用上の注意

### 現在採用しているデータソースのライセンス概要

| データソース | ライセンス / 規約 | 個人利用時の主な要件 |
|---|---|---|
| Apple WeatherKit | Apple Weather Terms of Service | Apple Developer Program への参加、画面ごとの帰属表示 |
| Falchi et al. 2016 World Atlas | CC BY 4.0 | 著者名・出典・DOI・ライセンスの明示 |
| Copernicus DEM GLO-30 | CC BY 4.0 | Copernicus / EU / ESA(DLR) 系の帰属表示 |
| Yale BSC5 / CDS VizieR | Public Domain | 帰属表示を推奨 |
| d3-celestial constellation data | BSD 3-Clause | 著作権表示・条件・免責の保持 |
| Apple MapKit | Apple Developer Program 規約 | 規約の範囲内で利用 |

- 各データソースの条件を守る前提で利用できます。
- WeatherKit は `WeatherKitService` を通じて利用しており、Apple Developer Program への参加が必要です。
- 帰属表示はアプリ内「設定 > データソースとクレジット」と、天気表示ビュー内の `WeatherAttributionBadge` で行っています。
- データ提供元の利用規約や公開内容が更新される可能性があるため、利用前に最新情報を確認してください。

### 利用する権限とセンサー

- 位置情報は、現在地の観測条件を表示するために使用します。
- iPhone 版では、星図を実景に重ねて表示する機能のためにカメラを使用します。
- iPhone 版では、端末の向きに合わせて星図を表示するためにモーションセンサーを使用します。

## 開発メモ

- API 利用規約は変更される可能性があるため、リリース前に再確認してください。
- 本 README の内容は 2026-04-25 時点の実装/調査に基づきます。
