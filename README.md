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

- `xcodebuild -quiet -project NightScope.xcodeproj -scheme NightScopeiOS -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build`

## プロジェクト構成（抜粋）

- `NightScope/Controllers/` : 外部API取得・計算ロジック
- `NightScope/Models/` : ドメインモデル
- `NightScope/ViewModels/` : 表示用ロジック
- `NightScope/Views/` : SwiftUIビュー
- `NightScopeTests/` : 単体テスト

## 外部データソースとクレジット

NightScope は以下の外部データ/サービスを利用しています。

| サービス / データ | 用途 | 主な帰属・出典 | ライセンス | 取得方法 |
|---|---|---|---|---|
| MET Norway Locationforecast 2.0 | 天気予報取得 | Norwegian Meteorological Institute (MET Norway) — https://api.met.no/ | CC BY 4.0 | 実行時 API（ネットワーク必須） |
| Falchi et al. 2016 – World Atlas of Artificial Night Sky Brightness | 光害マップ | Falchi, F. et al. (2016) / GFZ Data Services — https://doi.org/10.5880/GFZ.1.4.2016.001 | CC BY 4.0 | バンドルバイナリ（`bortle_map.bin`、`Tools/generate_bortle_map.py` で生成） |
| NASA Shuttle Radar Topography Mission (SRTM) | 地形・標高データ | NASA / USGS SRTM — https://srtm.csi.cgiar.org/ | Public Domain | バンドルバイナリ（`srtm_elevation.bin`、`Tools/prepare_srtm.py` で生成） |
| Yale Bright Star Catalogue (BSC5 / CDS V/50) | 星カタログ | Yale BSC5 / CDS VizieR — https://vizier.cds.unistra.fr/viz-bin/VizieR-3?-source=V/50 | Public Domain | バンドル JSON（`stars_fill.json`、`Tools/generate_stars.py` で生成） |
| Apple MapKit (MKReverseGeocodingRequest) | 逆ジオコーディング・地名取得 | Apple Inc. | Apple Developer Program 規約 | システムフレームワーク（ネットワーク不要） |

## バンドルデータの準備手順

`bortle_map.bin` と `srtm_elevation.bin` は、環境に応じて**生成するか、別途配布されたアセットを配置する**運用を想定しています。

### bortle_map.bin（光害データ）

```bash
pip install numpy scipy
python3 Tools/generate_bortle_map.py \
    --output NightScope/Models/bortle_map.bin
```

### srtm_elevation.bin（地形データ）

`srtm.py` パッケージが SRTM3 タイルを公開 CDN（`srtm.kurviger.de`）から自動取得します。登録不要です。

```bash
pip install srtm.py numpy

# --resolution 0.5 → 約 0.5 MB、数分で完了（推奨）
python3 Tools/prepare_srtm.py --auto \
    --output NightScope/Models/srtm_elevation.bin \
    --resolution 0.5

# より詳細なデータが必要な場合（約 12 MB、時間がかかる）
python3 Tools/prepare_srtm.py --auto \
    --output NightScope/Models/srtm_elevation.bin \
    --resolution 0.1
```

ローカルに GeoTIFF / .hgt タイルがある場合:
```bash
pip install numpy rasterio scipy
python3 Tools/prepare_srtm.py --input-dir ~/srtm_tiles/ \
    --output NightScope/Models/srtm_elevation.bin --resolution 0.1
```

> [!NOTE]
> `srtm_elevation.bin` が存在しない場合、`TerrainService` は nil を返し地形データなし（平坦地扱い）で動作します。ビルド・実行は可能ですが、地平線障害物の計算は行われません。

## バンドルデータの運用方針

- `bortle_map.bin` は派生バイナリとしてサイズが大きくなりやすいため、**通常の Git 追跡を前提にしない**運用を推奨します。
- 推奨候補は以下のいずれかです。
  - Git LFS で管理する
  - リリースアセット / 社内配布物として配る
  - 開発環境ごとに `Tools/generate_bortle_map.py` で生成する
- `srtm_elevation.bin` は `bortle_map.bin` より軽量ですが、長期的には同じ運用ポリシーに揃えると判断しやすくなります。
- いずれの方式でも、**生成スクリプト・フォーマット仕様・README 手順はリポジトリで管理**する前提です。

## 利用上の注意（個人利用 / 将来商用）

### 現在採用しているデータソースのライセンス概要

| データソース | ライセンス | 商用利用 | 主な要件 |
|---|---|---|---|
| MET Norway Locationforecast 2.0 | CC BY 4.0 | ✅ 可 | 帰属表示・User-Agent 設定 |
| Falchi et al. 2016 World Atlas | CC BY 4.0 | ✅ 可 | 帰属表示（論文・DOI の明示） |
| NASA SRTM | Public Domain | ✅ 可 | 帰属表示（推奨） |
| Yale BSC5 / CDS VizieR | Public Domain | ✅ 可 | 帰属表示（推奨） |
| Apple MapKit | Apple Developer Program 規約 | ✅ 可（規約の範囲内） | Apple Developer Program への参加 |

全データソースが **CC BY 4.0 / Public Domain / Apple Developer Program 規約**のみで構成されており、商用配布・課金・法人利用においても帰属表示を適切に行うことで利用可能な状態です。

### 個人利用（現状）

- 各データソースの条件を守る前提で利用可能です。
- MET Norway は User-Agent ヘッダの設定が必須です（`WeatherService` で対応済み）。
- 帰属表示はアプリ内「設定 > データソースとクレジット」で行っています。

### 商用化時の確認事項

- MET Norway の利用規約に変更がないことを確認してください。今後、Apple Developer Programに参加した際には、Apple Weather Kitに置き換える予定。
- CC BY 4.0 データソースの帰属表示がアプリ内・配布物（App Store ページ等）に含まれていることを確認してください。
- Apple Developer Program 規約の最新版を確認してください。

## 商用化前チェックリスト

- [ ] MET Norway Locationforecast 2.0 の利用規約に変更がないことを確認
- [ ] Falchi World Atlas (CC BY 4.0) の帰属表示（Falchi et al. 2016 / GFZ Data Services / DOI）がアプリ内・配布物に含まれている
- [ ] NASA SRTM の利用条件（Public Domain）に変更がないことを確認
- [ ] Yale BSC5 の帰属表示が設定画面に含まれている
- [ ] Apple MapKit の利用が Apple Developer Program 規約の範囲内であることを確認
- [ ] README とアプリ内「設定 > データソースとクレジット」で全帰属が明示されている

## 開発メモ

- API 利用規約は変更される可能性があるため、リリース前に再確認してください。
- 本 README の内容は 2026-04-11 時点の実装/調査に基づきます。
