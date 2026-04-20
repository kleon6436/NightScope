#!/usr/bin/env python3
"""
prepare_srtm.py
===============
NASA SRTM / Copernicus DEM GLO-30 データをバンドル用バイナリに変換するスクリプト。

データソース:
  NASA/USGS Shuttle Radar Topography Mission (SRTM)
  ライセンス: パブリックドメイン

  Copernicus DEM GLO-30 (1 arc-second, ~30m)
  AWS S3 公開バケット: copernicus-dem-30m（認証不要）
  ライセンス: DLR / ESA (https://spacedata.copernicus.eu/documents/20126/0/CSCDA_ESA_Mission-specific+Annex.pdf)

━━━  モード 1: 自動ダウンロード（推奨・登録不要）  ━━━

  pip install srtm.py numpy

  # 日本のみ（推奨・高速・163 KB）
  python3 Tools/prepare_srtm.py --auto --region japan \\
      --output NightScope/Models/elevation_japan.bin \\
      --resolution 0.1

  # カスタム範囲
  python3 Tools/prepare_srtm.py --auto \\
      --lat-min 20 --lat-max 46 --lon-min 122 --lon-max 154 \\
      --output NightScope/Models/elevation_global.bin \\
      --resolution 0.1

  タイル（SRTM3、1°×1°）を srtm.kurviger.de から自動取得します。
  ダウンロード済みタイルは ~/.cache/srtm/ にキャッシュされます。

━━━  モード 2: Copernicus DEM GLO-30（高精度・30m）  ━━━

  pip install rasterio numpy

  # 全球 0.05°, zlib 圧縮
  python3 Tools/prepare_srtm.py --source copernicus --resolution 0.05 \\
      --compress --output NightScope/Models/elevation_global.bin.z

  # 日本 0.01°, zlib 圧縮
  python3 Tools/prepare_srtm.py --source copernicus --region japan --resolution 0.01 \\
      --compress --output NightScope/Models/elevation_japan.bin.z

  AWS S3 公開バケット copernicus-dem-30m から COG タイルを認証不要で取得します。
  ダウンロード済みタイルは ~/.cache/copernicus-dem/ にキャッシュされます。

━━━  モード 3: ローカル GeoTIFF から生成  ━━━

  pip install numpy rasterio scipy

  python3 Tools/prepare_srtm.py \\
      --input /path/to/srtm30_global.tif \\
      --output NightScope/Models/elevation_global.bin \\
      --resolution 0.1

━━━  モード 4: ローカル .hgt タイルディレクトリから生成  ━━━

  python3 Tools/prepare_srtm.py \\
      --input-dir /path/to/srtm_tiles/ \\
    --output NightScope/Models/elevation_global.bin \\
      --resolution 0.1

出力フォーマット (*.bin / *.bin.z):

  Version 1（全球）:
    Magic:     4 bytes  = b"SRTM"
    Version:   uint32 LE = 1
    LatCells:  int32  LE  (南→北, -90〜+90)
    LonCells:  int32  LE  (西→東, -180〜+180)
    Data:      int16[] LE, row-major, 標高 [m, 海面上]

  Version 2（領域限定・--region / --lat-min 等使用時）:
    Magic:     4 bytes  = b"SRTM"
    Version:   uint32 LE = 2
    LatCells:  int32  LE
    LonCells:  int32  LE
    LatMin:    float32 LE  (南端)
    LatMax:    float32 LE  (北端)
    LonMin:    float32 LE  (西端)
    LonMax:    float32 LE  (東端)
    Data:      int16[] LE, row-major, 標高 [m, 海面上]

  範囲外座標は Swift 側で 0m（平坦地）扱い。

zlib 圧縮フォーマット（--compress 有効時）:

    Magic:     4 bytes  = b"SRTZ"
    Payload:   zlib 圧縮済みバイナリ（上記 SRTM フォーマット全体を zlib.compress(..., 9)）
"""

import argparse
import struct
import sys
import os
import zlib

# 地域プリセット定義
REGION_PRESETS = {
    # 沖縄〜北海道 + 対馬・南西諸島・択捉島をカバー
    "japan": {"lat_min": 20.0, "lat_max": 46.0, "lon_min": 122.0, "lon_max": 154.0},
}


# ──────────────────────────────────────────────
# モード 1: srtm.py を使った自動ダウンロード
# ──────────────────────────────────────────────

def build_auto(lat_cells: int, lon_cells: int, res: float,
               lat_min: float, lat_max: float, lon_min: float, lon_max: float):
    """srtm.py パッケージ経由でタイルを自動取得してグリッドを構築する。
    タイル単位（1°×1°）で処理するため cell-by-cell 方式より大幅に高速。
    lat_min/lat_max/lon_min/lon_max は取得対象範囲（グリッドの論理範囲）。
    """
    try:
        import srtm
        import numpy as np
    except ImportError:
        print("ERROR: 必要なパッケージがありません。", file=sys.stderr)
        print("  pip install srtm.py numpy", file=sys.stderr)
        sys.exit(1)

    import io

    is_regional = not (lat_min == -90.0 and lat_max == 90.0
                       and lon_min == -180.0 and lon_max == 180.0)
    region_label = f"lat [{lat_min:+.0f}〜{lat_max:+.0f}], lon [{lon_min:+.0f}〜{lon_max:+.0f}]"
    print(f"SRTM3 タイルを自動ダウンロードします（srtm.kurviger.de、登録不要）...")
    print(f"  範囲: {region_label}")
    print(f"  キャッシュ先: ~/.cache/srtm/")

    _orig_stdout = sys.stdout
    sys.stdout = io.StringIO()
    try:
        elevation_data = srtm.get_data()
    finally:
        sys.stdout = _orig_stdout

    grid = np.zeros((lat_cells, lon_cells), dtype=np.float32)

    # 対象タイル範囲（SRTM3 は lat -60〜59 までカバー）
    tile_lat_lo = max(-60, int(np.floor(lat_min)))
    tile_lat_hi = min(59,  int(np.floor(lat_max - 0.001)))
    tile_lon_lo = max(-180, int(np.floor(lon_min)))
    tile_lon_hi = min(179,  int(np.floor(lon_max - 0.001)))

    lat_bands = list(range(tile_lat_lo, tile_lat_hi + 1))
    total = len(lat_bands) * (tile_lon_hi - tile_lon_lo + 1)
    done = 0

    for tile_lat in lat_bands:
        for tile_lon in range(tile_lon_lo, tile_lon_hi + 1):
            done += 1
            pct = done / total * 100
            print(f"  {pct:.0f}%  ({done}/{total} tiles, lat {tile_lat:+d} lon {tile_lon:+d})",
                  end="\r", flush=True)

            # グリッド内インデックス（グリッド座標系 = lat_min 基準）
            lat_i_lo = max(0, int(np.ceil((tile_lat - lat_min) / res - 0.5)))
            lat_i_hi = min(lat_cells, int(np.floor((tile_lat + 1 - lat_min) / res - 0.5)) + 1)
            lon_j_lo = max(0, int(np.ceil((tile_lon - lon_min) / res - 0.5)))
            lon_j_hi = min(lon_cells, int(np.floor((tile_lon + 1 - lon_min) / res - 0.5)) + 1)
            if lat_i_lo >= lat_i_hi or lon_j_lo >= lon_j_hi:
                continue

            sys.stdout = io.StringIO()
            try:
                geo_file = elevation_data.get_file(tile_lat, tile_lon)
            finally:
                sys.stdout = _orig_stdout

            if geo_file is None or not geo_file.data:
                continue

            raw = geo_file.data
            samples = 1201 if len(raw) == 1201 * 1201 * 2 else 3601
            arr = np.frombuffer(raw, dtype=">i2").reshape(samples, samples).astype(np.float32)
            arr[arr == -32768] = 0.0  # nodata → 0m
            arr = np.flipud(arr)       # row0=North → row0=South（南起点に）

            lat_centers = lat_min + (np.arange(lat_i_lo, lat_i_hi) + 0.5) * res
            lon_centers = lon_min + (np.arange(lon_j_lo, lon_j_hi) + 0.5) * res
            lat_idx = np.clip(np.round((lat_centers - tile_lat) * (samples - 1)).astype(int), 0, samples - 1)
            lon_idx = np.clip(np.round((lon_centers - tile_lon) * (samples - 1)).astype(int), 0, samples - 1)

            grid[lat_i_lo:lat_i_hi, lon_j_lo:lon_j_hi] = arr[np.ix_(lat_idx, lon_idx)]

    print()
    return grid


# ──────────────────────────────────────────────
# モード 2: Copernicus DEM GLO-30 自動ダウンロード
# ──────────────────────────────────────────────

_COPERNICUS_URL_TEMPLATE = (
    "https://copernicus-dem-30m.s3.eu-central-1.amazonaws.com/"
    "Copernicus_DSM_COG_10_{NS}{lat:02d}_00_{EW}{lon:03d}_00_DEM/"
    "Copernicus_DSM_COG_10_{NS}{lat:02d}_00_{EW}{lon:03d}_00_DEM.tif"
)
_COPERNICUS_CACHE_DIR = os.path.expanduser("~/.cache/copernicus-dem")


def _copernicus_tile_url(tile_lat: int, tile_lon: int) -> str:
    """1°×1° タイルの Copernicus DEM COG URL を返す。"""
    ns = "N" if tile_lat >= 0 else "S"
    ew = "E" if tile_lon >= 0 else "W"
    return _COPERNICUS_URL_TEMPLATE.format(
        NS=ns, lat=abs(tile_lat), EW=ew, lon=abs(tile_lon)
    )


def _download_copernicus_tile(tile_lat: int, tile_lon: int) -> "str | None":
    """Copernicus DEM タイルをキャッシュにダウンロードし、ローカルパスを返す。
    タイルが存在しない（海洋など）場合は None を返す。
    """
    import urllib.request
    import urllib.error

    ns = "N" if tile_lat >= 0 else "S"
    ew = "E" if tile_lon >= 0 else "W"
    filename = (
        f"Copernicus_DSM_COG_10_{ns}{abs(tile_lat):02d}_00_{ew}{abs(tile_lon):03d}_00_DEM.tif"
    )
    cache_path = os.path.join(_COPERNICUS_CACHE_DIR, filename)

    if os.path.exists(cache_path):
        return cache_path

    url = _copernicus_tile_url(tile_lat, tile_lon)
    os.makedirs(_COPERNICUS_CACHE_DIR, exist_ok=True)
    max_retries = 5
    for attempt in range(max_retries):
        try:
            with urllib.request.urlopen(url, timeout=60) as resp:  # nosec B310
                data = resp.read()
            with open(cache_path, "wb") as f:
                f.write(data)
            return cache_path
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None  # 海洋・未収録タイル
            if attempt < max_retries - 1:
                import time as _time
                _time.sleep(2 ** attempt)
                continue
            raise
        except (urllib.error.URLError, ConnectionResetError, OSError):
            if attempt < max_retries - 1:
                import time as _time
                _time.sleep(2 ** attempt)
                continue
            raise


def build_copernicus(lat_cells: int, lon_cells: int, res: float,
                     lat_min: float, lat_max: float, lon_min: float, lon_max: float):
    """Copernicus DEM GLO-30 の COG タイルを AWS S3 から取得してグリッドを構築する。
    タイルは ~/.cache/copernicus-dem/ にキャッシュされる。
    rasterio は本関数内でのみ import する。
    """
    try:
        import numpy as np
        import rasterio
        import rasterio.warp
        from rasterio.enums import Resampling
        from rasterio.transform import from_bounds
    except ImportError:
        print("ERROR: 必要なパッケージがありません。", file=sys.stderr)
        print("  pip install rasterio numpy", file=sys.stderr)
        sys.exit(1)

    is_regional = not (lat_min == -90.0 and lat_max == 90.0
                       and lon_min == -180.0 and lon_max == 180.0)
    region_label = f"lat [{lat_min:+.0f}〜{lat_max:+.0f}], lon [{lon_min:+.0f}〜{lon_max:+.0f}]"
    print("Copernicus DEM GLO-30 タイルを AWS S3 からダウンロードします（認証不要）...")
    print(f"  範囲: {region_label}")
    print(f"  キャッシュ先: {_COPERNICUS_CACHE_DIR}/")

    grid = np.zeros((lat_cells, lon_cells), dtype=np.float32)

    tile_lat_lo = int(np.floor(lat_min))
    tile_lat_hi = int(np.floor(lat_max - 1e-9))
    tile_lon_lo = int(np.floor(lon_min))
    tile_lon_hi = int(np.floor(lon_max - 1e-9))

    lat_bands = list(range(tile_lat_lo, tile_lat_hi + 1))
    total = len(lat_bands) * (tile_lon_hi - tile_lon_lo + 1)

    dst_transform = from_bounds(lon_min, lat_min, lon_max, lat_max, lon_cells, lat_cells)

    # Phase 1: 並列ダウンロード
    from concurrent.futures import ThreadPoolExecutor, as_completed
    tile_coords = [(lat, lon)
                   for lat in lat_bands
                   for lon in range(tile_lon_lo, tile_lon_hi + 1)]
    tile_paths = {}  # (lat, lon) -> path or None
    workers = min(10, len(tile_coords))
    print(f"  並列ダウンロード（{workers} スレッド）...")
    done = 0
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {pool.submit(_download_copernicus_tile, lat, lon): (lat, lon)
                   for lat, lon in tile_coords}
        for future in as_completed(futures):
            coord = futures[future]
            done += 1
            tile_paths[coord] = future.result()
            if done % 100 == 0 or done == total:
                pct = done / total * 100
                print(f"  DL {pct:.0f}%  ({done}/{total} tiles)",
                      end="\r", flush=True)
    land_count = sum(1 for v in tile_paths.values() if v is not None)
    print(f"\n  ダウンロード完了: {land_count} 陸地タイル / {total} 合計")

    # Phase 2: 逐次リプロジェクション
    processed = 0
    for tile_lat, tile_lon in tile_coords:
        local_path = tile_paths[(tile_lat, tile_lon)]
        if local_path is None:
            continue
        processed += 1
        print(f"  投影 {processed}/{land_count} (lat {tile_lat:+d} lon {tile_lon:+d})",
              end="\r", flush=True)

        # グリッド内インデックス
        lat_i_lo = max(0, int(np.ceil((tile_lat - lat_min) / res - 0.5)))
        lat_i_hi = min(lat_cells, int(np.floor((tile_lat + 1 - lat_min) / res - 0.5)) + 1)
        lon_j_lo = max(0, int(np.ceil((tile_lon - lon_min) / res - 0.5)))
        lon_j_hi = min(lon_cells, int(np.floor((tile_lon + 1 - lon_min) / res - 0.5)) + 1)
        if lat_i_lo >= lat_i_hi or lon_j_lo >= lon_j_hi:
            continue

        tile_cells_lat = lat_i_hi - lat_i_lo
        tile_cells_lon = lon_j_hi - lon_j_lo

        tile_dst = np.zeros((tile_cells_lat, tile_cells_lon), dtype=np.float32)
        tile_transform = from_bounds(
            lon_min + lon_j_lo * res,
            lat_min + lat_i_lo * res,
            lon_min + lon_j_hi * res,
            lat_min + lat_i_hi * res,
            tile_cells_lon,
            tile_cells_lat,
        )

        with rasterio.open(local_path) as src:
            rasterio.warp.reproject(
                source=rasterio.band(src, 1),
                destination=tile_dst,
                src_transform=src.transform,
                src_crs=src.crs,
                dst_transform=tile_transform,
                dst_crs="EPSG:4326",
                resampling=Resampling.average,
            )
            nodata = src.nodata
            if nodata is not None:
                tile_dst[tile_dst == nodata] = 0.0

        # North-up → flip して南起点に揃える
        grid[lat_i_lo:lat_i_hi, lon_j_lo:lon_j_hi] = np.flipud(tile_dst)

    print()
    return grid


# ──────────────────────────────────────────────
# モード 3 / 4: ローカルファイルから構築
# ──────────────────────────────────────────────

def load_from_directory(input_dir: str):
    """ディレクトリ内の .hgt / .tif ファイルを結合して返す。"""
    import glob
    patterns = ["*.hgt", "*.HGT", "*.tif", "*.TIF", "*.tiff"]
    files = []
    for pattern in patterns:
        files.extend(glob.glob(os.path.join(input_dir, "**", pattern), recursive=True))
    if not files:
        print(f"ERROR: {input_dir} に HGT/TIF ファイルが見つかりません。", file=sys.stderr)
        sys.exit(1)
    print(f"{len(files)} ファイルを結合します...")
    import rasterio
    from rasterio.merge import merge as rasterio_merge
    datasets = [rasterio.open(f) for f in sorted(files)]
    mosaic, transform = rasterio_merge(datasets)
    for d in datasets:
        d.close()
    return mosaic[0], transform


def build_from_geotiff(input_path: str, lat_cells: int, lon_cells: int):
    try:
        import numpy as np
        import rasterio
        from rasterio.enums import Resampling
    except ImportError:
        print("ERROR: pip install numpy rasterio", file=sys.stderr)
        sys.exit(1)

    data = np.zeros((lat_cells, lon_cells), dtype=np.float32)
    print(f"入力: {input_path}")
    with rasterio.open(input_path) as src:
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
        nodata = src.nodata
        if nodata is not None:
            data[data == nodata] = 0.0
    # north-up → flipud して南から始める
    import numpy as np  # noqa: F811
    data = np.flipud(data)
    return data


def build_from_directory(input_dir: str, lat_cells: int, lon_cells: int):
    try:
        import numpy as np
        from scipy.ndimage import zoom as scipy_zoom
    except ImportError:
        print("ERROR: pip install numpy rasterio scipy", file=sys.stderr)
        sys.exit(1)

    raw_data, _ = load_from_directory(input_dir)
    scale_lat = lat_cells / raw_data.shape[0]
    scale_lon = lon_cells / raw_data.shape[1]
    data = scipy_zoom(raw_data.astype("float32"), (scale_lat, scale_lon), order=1)
    data = data[:lat_cells, :lon_cells]
    data = np.flipud(data)
    return data


# ──────────────────────────────────────────────
# 共通後処理・バイナリ出力
# ──────────────────────────────────────────────

def postprocess_and_write(data, lat_cells: int, lon_cells: int, output_path: str,
                          lat_min: float = -90.0, lat_max: float = 90.0,
                          lon_min: float = -180.0, lon_max: float = 180.0,
                          compress: bool = False):
    import numpy as np
    data = np.nan_to_num(data, nan=0.0)
    data = np.where(data < -500, 0.0, data)   # SRTM nodata（海洋）→ 0
    data_int16 = data.astype(np.int16)

    is_regional = not (lat_min == -90.0 and lat_max == 90.0
                       and lon_min == -180.0 and lon_max == 180.0)
    version = 2 if is_regional else 1

    print(f"  統計: min={data_int16.min()} m  max={data_int16.max()} m")
    print(f"  フォーマット: Version {version}"
          + (f" (lat {lat_min:+.1f}〜{lat_max:+.1f}, lon {lon_min:+.1f}〜{lon_max:+.1f})" if is_regional else " (全球)"))
    if compress:
        print("  圧縮: zlib (マジック SRTZ)")
    print(f"出力: {output_path}")
    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)

    # SRTM バイナリ本体を組み立てる
    payload = bytearray()
    payload += b"SRTM"
    payload += struct.pack("<I", version)
    payload += struct.pack("<i", lat_cells)
    payload += struct.pack("<i", lon_cells)
    if is_regional:
        payload += struct.pack("<f", lat_min)
        payload += struct.pack("<f", lat_max)
        payload += struct.pack("<f", lon_min)
        payload += struct.pack("<f", lon_max)
    payload += data_int16.astype("<i2").tobytes()

    with open(output_path, "wb") as f:
        if compress:
            f.write(b"SRTZ")
            f.write(zlib.compress(bytes(payload), 9))
        else:
            f.write(payload)

    size_kb = os.path.getsize(output_path) / 1024
    if size_kb >= 1024:
        print(f"完了: {size_kb / 1024:.1f} MB")
    else:
        print(f"完了: {size_kb:.0f} KB")


# ──────────────────────────────────────────────
# エントリポイント
# ──────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="SRTM / Copernicus DEM データ → 地形バイナリ変換ツール",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument(
        "--auto", action="store_true",
        help="srtm.py パッケージ経由で自動ダウンロード（登録不要）",
    )
    group.add_argument(
        "--source", choices=["srtm", "copernicus"],
        help="データソースを選択: srtm（--auto と同等）または copernicus（Copernicus DEM GLO-30）",
    )
    group.add_argument("--input",     help="入力 GeoTIFF ファイルパス")
    group.add_argument("--input-dir", help="入力ディレクトリ（.hgt/.tif を再帰検索）")

    parser.add_argument(
        "--output", default="NightScope/Models/elevation_global.bin",
        help="出力バイナリファイルパス（デフォルト: NightScope/Models/elevation_global.bin）",
    )
    parser.add_argument(
        "--resolution", type=float, default=0.1,
        help="グリッド解像度（度）。デフォルト 0.1",
    )
    parser.add_argument(
        "--compress", action="store_true",
        help="zlib 圧縮出力を有効にする（マジック SRTZ）",
    )

    # 領域指定（--auto / --source 時のみ有効）
    region_group = parser.add_argument_group("領域指定（--auto / --source 時のみ有効）")
    region_group.add_argument(
        "--region",
        choices=list(REGION_PRESETS.keys()),
        help="地域プリセット。現在: " + ", ".join(REGION_PRESETS.keys()),
    )
    region_group.add_argument("--lat-min", type=float, help="南端の緯度（デフォルト: -90）")
    region_group.add_argument("--lat-max", type=float, help="北端の緯度（デフォルト:  90）")
    region_group.add_argument("--lon-min", type=float, help="西端の経度（デフォルト: -180）")
    region_group.add_argument("--lon-max", type=float, help="東端の経度（デフォルト:  180）")

    args = parser.parse_args()

    # 領域バウンド確定
    lat_min, lat_max = -90.0, 90.0
    lon_min, lon_max = -180.0, 180.0

    if args.region:
        preset = REGION_PRESETS[args.region]
        lat_min = preset["lat_min"]
        lat_max = preset["lat_max"]
        lon_min = preset["lon_min"]
        lon_max = preset["lon_max"]

    if args.lat_min is not None: lat_min = args.lat_min
    if args.lat_max is not None: lat_max = args.lat_max
    if args.lon_min is not None: lon_min = args.lon_min
    if args.lon_max is not None: lon_max = args.lon_max

    # 拡張子が .bin.z の場合は --compress を自動有効化
    if args.output.endswith(".bin.z") and not args.compress:
        print("INFO: 出力拡張子が .bin.z のため --compress を有効化します。")
        args.compress = True

    is_auto_mode = args.auto or args.source is not None
    if not is_auto_mode and (lat_min != -90.0 or lat_max != 90.0 or
                              lon_min != -180.0 or lon_max != 180.0):
        parser.error("--region / --lat-min 等は --auto または --source と組み合わせて使用してください。")

    res = args.resolution
    lat_cells = round((lat_max - lat_min) / res)
    lon_cells = round((lon_max - lon_min) / res)
    est_bytes = lat_cells * lon_cells * 2
    est_label = f"{est_bytes / (1024*1024):.1f} MB" if est_bytes >= 1024*1024 else f"{est_bytes / 1024:.0f} KB"
    print(f"解像度: {res}°  → {lat_cells} lat × {lon_cells} lon = {lat_cells * lon_cells:,} cells  (バイナリ ≈ {est_label})")

    if args.auto or args.source == "srtm":
        data = build_auto(lat_cells, lon_cells, res, lat_min, lat_max, lon_min, lon_max)
    elif args.source == "copernicus":
        data = build_copernicus(lat_cells, lon_cells, res, lat_min, lat_max, lon_min, lon_max)
    elif args.input:
        data = build_from_geotiff(args.input, lat_cells, lon_cells)
    else:
        data = build_from_directory(args.input_dir, lat_cells, lon_cells)

    postprocess_and_write(data, lat_cells, lon_cells, args.output,
                          lat_min, lat_max, lon_min, lon_max,
                          compress=args.compress)


if __name__ == "__main__":
    main()
