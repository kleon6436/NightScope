#!/usr/bin/env python3
"""
generate_bortle_map.py
======================
光害 GeoTIFF をバンドル用バイナリ (bortle_map.bin) に変換するスクリプト。
--input を省略すると、ソースに応じてデータを自動取得または自動検出します。

対応データソース:
  [falchi]  Cinzano P, Falchi F (2016): World Atlas 2015.
            GFZ Data Services. https://doi.org/10.5880/GFZ.1.4.2016.001
            入力単位: mcd/m² (人工輝度)
            ライセンス: CC BY 4.0
            自動取得: GFZ Data Services より直接ダウンロード（要インターネット）

  [viirs]   VIIRS DNB Annual Composite V2.2 (推奨 / デフォルト)
            Earth Observation Group, Payne Institute, Colorado School of Mines.
            https://eogdata.mines.edu/products/vnl/
            入力単位: nW/cm²/sr (平均放射輝度)
            ライセンス: CC BY 4.0
            引用: Elvidge et al. (2021) Remote Sensing 13(5), 922.
            変換: brightness_mcd = radiance_nWcm2sr * VIIRS_TO_MCD_FACTOR
            自動取得: EOG アカウントが必要 (--eog-username / --eog-password)
                      登録: https://eogdata.mines.edu/products/register/

依存パッケージ:
  pip install numpy rasterio requests tqdm

使い方:
  # VIIRS (推奨・デフォルト) — EOG アカウント必要
  python3 Tools/generate_bortle_map.py \\
      --source viirs \\
      --eog-username your@email.com \\
      --eog-password yourpassword \\
      --output NightScope/Models/bortle_map.bin \\
      --resolution 0.1

  # Falchi World Atlas 2015 — 自動ダウンロード (アカウント不要)
  python3 Tools/generate_bortle_map.py \\
      --source falchi \\
      --output NightScope/Models/bortle_map.bin \\
      --resolution 0.1

  # 非圧縮 (v1) で出力
  python3 Tools/generate_bortle_map.py \\
      --source falchi \\
      --no-compress \\
      --output NightScope/Models/bortle_map.bin

  # 既存ファイルを指定して変換
  python3 Tools/generate_bortle_map.py \\
      --input /path/to/World_Atlas_2015.tif \\
      --source falchi \\
      --resolution 0.05

出力フォーマット v1 (bortle_map.bin, --no-compress):
  Magic:     4 bytes  = b"BORT"
  Version:   uint32 LE = 1
  LatCells:  int32  LE  (南→北, -90〜+90)
  LonCells:  int32  LE  (西→東, -180〜+180)
  Data:      float32[] LE, row-major, 人工輝度 [mcd/m² 相当]

出力フォーマット v2 (bortle_map.bin, デフォルト --compress):
  Magic:     4 bytes  = b"BORT"
  Version:   uint32 LE = 2
  LatCells:  int32  LE  (南→北, -90〜+90)
  LonCells:  int32  LE  (西→東, -180〜+180)
  RawSize:   uint32 LE  (非圧縮データサイズ)
  CompData:  zlib compressed float32[] LE
"""

import argparse
import os
import struct
import sys
import tarfile
import tempfile
from pathlib import Path
from typing import Optional

try:
    import numpy as np
    import rasterio
    import rasterio.warp
    import rasterio.transform
    from rasterio.enums import Resampling
except ImportError:
    print("ERROR: 必要なパッケージがありません。", file=sys.stderr)
    print("  pip install numpy rasterio requests tqdm", file=sys.stderr)
    sys.exit(1)

try:
    import requests
    from tqdm import tqdm
    HAS_REQUESTS = True
except ImportError:
    HAS_REQUESTS = False

# VIIRS nW/cm²/sr → mcd/m² 相当への経験的変換係数。
# Duriscoe (2014) および Hölker et al. の相互検証に基づく近似値。
# 実測 SQM 値との比較で精度検証・調整を推奨。
DEFAULT_VIIRS_TO_MCD_FACTOR = 0.55

# GFZ Falchi データの直接ダウンロード URL
FALCHI_TAR_URL = (
    "https://datapub.gfz-potsdam.de/download/"
    "10.5880.GFZ.1.4.2016.001-Lzhlq/World_Atlas_2015v2.tar.gz"
)
# tar.gz 内のファイル名
FALCHI_TIF_NAME = "World_Atlas_2015v2/skyglow_world.tif"

# EOG Keycloak 認証エンドポイント
EOG_TOKEN_URL = (
    "https://eogauth-new.mines.edu/realms/eog/"
    "protocol/openid-connect/token"
)
EOG_CLIENT_ID = "eogdata-new-apache"

# VIIRS Annual V2.2 最新ファイル（2023年版・グローバル平均マスク済み）
VIIRS_TIF_URL = (
    "https://eogdata.mines.edu/nighttime_light/annual/v22/2023/"
    "VNL_v22_npp-j01_2023_global_vcmslcfg_c202402081600"
    ".average_masked.dat.tif.gz"
)

# Falchi データのローカル検索パス（順番に探す）
FALCHI_SEARCH_PATHS = [
    Path.home() / "Downloads" / "World_Atlas_2015" / "World_Atlas_2015.tif",
    Path.home() / "Downloads" / "World_Atlas_2015v2" / "skyglow_world.tif",
    Path.home() / "Downloads" / "skyglow_world.tif",
    Path.home() / "Downloads" / "World_Atlas_2015.tif",
    Path("World_Atlas_2015.tif"),
    Path("skyglow_world.tif"),
]


# ---------------------------------------------------------------------------
# ダウンロードユーティリティ
# ---------------------------------------------------------------------------

def download_file(url: str, dest: Path, headers: Optional[dict] = None) -> None:
    """HTTP GET でファイルをダウンロードし、進捗を表示する。"""
    if not HAS_REQUESTS:
        print("ERROR: requests / tqdm が未インストールです。", file=sys.stderr)
        print("  pip install requests tqdm", file=sys.stderr)
        sys.exit(1)

    print(f"ダウンロード: {url}")
    with requests.get(url, headers=headers or {}, stream=True, timeout=60) as r:
        r.raise_for_status()
        total = int(r.headers.get("content-length", 0))
        with open(dest, "wb") as f, tqdm(
            total=total, unit="B", unit_scale=True, unit_divisor=1024,
            desc=dest.name, ncols=80
        ) as bar:
            for chunk in r.iter_content(chunk_size=1024 * 256):
                f.write(chunk)
                bar.update(len(chunk))


def get_eog_token(username: str, password: str) -> str:
    """EOG Keycloak から Bearer トークンを取得する。"""
    if not HAS_REQUESTS:
        print("ERROR: requests が未インストールです: pip install requests tqdm", file=sys.stderr)
        sys.exit(1)

    print("EOG 認証中...")
    resp = requests.post(
        EOG_TOKEN_URL,
        data={
            "client_id": EOG_CLIENT_ID,
            "grant_type": "password",
            "username": username,
            "password": password,
        },
        timeout=30,
    )
    if resp.status_code != 200:
        print(f"ERROR: EOG 認証に失敗しました (HTTP {resp.status_code})", file=sys.stderr)
        print("  ユーザー登録: https://eogdata.mines.edu/products/register/", file=sys.stderr)
        sys.exit(1)
    token = resp.json().get("access_token")
    if not token:
        print("ERROR: EOG トークンが取得できませんでした。", file=sys.stderr)
        sys.exit(1)
    print("  認証成功")
    return token


# ---------------------------------------------------------------------------
# ソースファイル取得
# ---------------------------------------------------------------------------

def resolve_falchi_input(tmpdir: Path) -> Path:
    """Falchi TIF のパスを解決する。ローカルになければ GFZ からダウンロード。"""
    # ローカルファイルを検索
    for candidate in FALCHI_SEARCH_PATHS:
        if candidate.exists():
            print(f"  既存ファイルを使用: {candidate}")
            return candidate

    # ダウンロード
    print("  Falchi データが見つかりません。GFZ からダウンロードします...")
    tar_path = tmpdir / "World_Atlas_2015v2.tar.gz"
    download_file(FALCHI_TAR_URL, tar_path)

    print("  展開中...")
    with tarfile.open(tar_path, "r:gz") as tf:
        # tar 内から TIF を探して展開
        tif_member = next(
            (m for m in tf.getmembers() if m.name.endswith(".tif")), None
        )
        if tif_member is None:
            print("ERROR: tar.gz 内に .tif ファイルが見つかりません。", file=sys.stderr)
            sys.exit(1)
        tf.extract(tif_member, path=tmpdir)
        tif_path = tmpdir / tif_member.name
    print(f"  展開完了: {tif_path}")
    return tif_path


def resolve_viirs_input(tmpdir: Path, username: str, password: str) -> Path:
    """EOG から VIIRS Annual V2.2 TIF をダウンロードして返す。"""
    token = get_eog_token(username, password)
    headers = {"Authorization": f"Bearer {token}"}

    gz_path = tmpdir / "VNL_v22_global.tif.gz"
    download_file(VIIRS_TIF_URL, gz_path, headers=headers)

    import gzip, shutil
    tif_path = tmpdir / "VNL_v22_global.tif"
    print("  gunzip 中...")
    with gzip.open(gz_path, "rb") as f_in, open(tif_path, "wb") as f_out:
        shutil.copyfileobj(f_in, f_out)
    print(f"  展開完了: {tif_path}")
    return tif_path


# ---------------------------------------------------------------------------
# グリッド変換
# ---------------------------------------------------------------------------

def reproject_to_grid(src, lat_cells: int, lon_cells: int) -> np.ndarray:
    """GeoTIFF バンド1 を EPSG:4326 の均一グリッドにリプロジェクトして返す。"""
    data = np.zeros((lat_cells, lon_cells), dtype=np.float32)
    rasterio.warp.reproject(
        source=rasterio.band(src, 1),
        destination=data,
        src_transform=src.transform,
        src_crs=src.crs,
        dst_transform=rasterio.transform.from_bounds(
            -180, -90, 180, 90, lon_cells, lat_cells
        ),
        dst_crs="EPSG:4326",
        resampling=Resampling.average,
    )
    return data


def clean_data(data: np.ndarray, nodata) -> np.ndarray:
    """nodata / NaN / 負値をゼロに置換し、south-first に flip する。"""
    if nodata is not None:
        data[data == nodata] = 0.0
    data = np.nan_to_num(data, nan=0.0)
    data = np.clip(data, 0.0, None)
    # GeoTIFF は north-up なので flipud して先頭行が南緯90°になるよう調整
    return np.flipud(data)


# ---------------------------------------------------------------------------
# メイン
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="光害 GeoTIFF → bortle_map.bin 変換ツール"
    )
    parser.add_argument(
        "--input",
        help="入力 GeoTIFF ファイルパス（省略時は自動取得または自動検出）"
    )
    parser.add_argument(
        "--source", choices=["viirs", "falchi"], default="falchi",
        help="データソース種別: falchi (デフォルト) または viirs"
    )
    parser.add_argument(
        "--output", default="NightScope/Models/bortle_map.bin",
        help="出力バイナリファイルパス"
    )
    parser.add_argument(
        "--resolution", type=float, default=0.1,
        help="グリッド解像度（度）(デフォルト: 0.1)"
    )
    parser.add_argument(
        "--compress", action="store_true", default=True,
        help="zlib 圧縮を有効にする (v2 フォーマット, デフォルト: 有効)"
    )
    parser.add_argument(
        "--no-compress", dest="compress", action="store_false",
        help="zlib 圧縮を無効にする (v1 フォーマット)"
    )
    parser.add_argument(
        "--viirs-factor", type=float, default=DEFAULT_VIIRS_TO_MCD_FACTOR,
        dest="viirs_factor",
        help=f"VIIRS nW/cm²/sr → mcd/m² 変換係数 (デフォルト: {DEFAULT_VIIRS_TO_MCD_FACTOR})"
    )
    parser.add_argument(
        "--eog-username", dest="eog_username", default="",
        help="EOG アカウントのメールアドレス (--source viirs 時に必要)"
    )
    parser.add_argument(
        "--eog-password", dest="eog_password", default="",
        help="EOG アカウントのパスワード (--source viirs 時に必要)"
    )
    args = parser.parse_args()

    res = args.resolution
    lat_cells = int(180.0 / res)
    lon_cells = int(360.0 / res)
    print(f"データソース: {args.source}")
    print(f"解像度: {res}°  → {lat_cells} lat × {lon_cells} lon = {lat_cells * lon_cells:,} セル")

    with tempfile.TemporaryDirectory() as tmpdir_str:
        tmpdir = Path(tmpdir_str)

        # 入力ファイルの解決
        if args.input:
            input_path = Path(args.input)
            if not input_path.exists():
                print(f"ERROR: 指定されたファイルが存在しません: {input_path}", file=sys.stderr)
                sys.exit(1)
        elif args.source == "falchi":
            input_path = resolve_falchi_input(tmpdir)
        elif args.source == "viirs":
            if not args.eog_username or not args.eog_password:
                print("ERROR: VIIRS の自動ダウンロードには EOG アカウントが必要です。", file=sys.stderr)
                print("  --eog-username YOUR_EMAIL --eog-password YOUR_PASSWORD を指定してください。", file=sys.stderr)
                print("  登録: https://eogdata.mines.edu/products/register/", file=sys.stderr)
                sys.exit(1)
            input_path = resolve_viirs_input(tmpdir, args.eog_username, args.eog_password)
        else:
            print("ERROR: --input または --source を指定してください。", file=sys.stderr)
            sys.exit(1)

        print(f"入力: {input_path}")

        with rasterio.open(input_path) as src:
            data = reproject_to_grid(src, lat_cells, lon_cells)
            data = clean_data(data, src.nodata)

    if args.source == "viirs":
        print(f"  VIIRS 変換係数: {args.viirs_factor} (nW/cm²/sr → mcd/m²)")
        data = data * np.float32(args.viirs_factor)
        unit_label = "mcd/m² (VIIRS換算)"
    else:
        unit_label = "mcd/m² (Falchi)"

    print(f"  min={data.min():.6f}  max={data.max():.6f}  {unit_label}")
    print(f"  非ゼロセル数: {np.count_nonzero(data):,} / {data.size:,}")

    # 出力先ディレクトリを作成
    output_path = args.output
    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)

    raw_bytes = data.astype("<f4").tobytes()
    print(f"出力: {output_path}")

    if args.compress:
        import zlib
        # Apple の Compression framework (COMPRESSION_ZLIB) は raw deflate を期待するため
        # wbits=-15 で zlib ヘッダー/トレーラーなしの raw deflate を出力
        compressor = zlib.compressobj(level=6, wbits=-15)
        compressed = compressor.compress(raw_bytes) + compressor.flush()
        with open(output_path, "wb") as f:
            f.write(b"BORT")                               # Magic
            f.write(struct.pack("<I", 2))                  # Version = 2
            f.write(struct.pack("<i", lat_cells))          # LatCells
            f.write(struct.pack("<i", lon_cells))          # LonCells
            f.write(struct.pack("<I", len(raw_bytes)))     # RawSize
            f.write(compressed)                            # raw deflate compressed data
        ratio = len(compressed) / len(raw_bytes) * 100
        print(f"  圧縮: {len(raw_bytes):,} → {len(compressed):,} bytes ({ratio:.1f}%)")
    else:
        with open(output_path, "wb") as f:
            f.write(b"BORT")                               # Magic
            f.write(struct.pack("<I", 1))                  # Version = 1
            f.write(struct.pack("<i", lat_cells))          # LatCells
            f.write(struct.pack("<i", lon_cells))          # LonCells
            f.write(raw_bytes)                             # float32 LE

    file_size_mb = os.path.getsize(output_path) / (1024 * 1024)
    print(f"完了: {file_size_mb:.1f} MB")


if __name__ == "__main__":
    main()
