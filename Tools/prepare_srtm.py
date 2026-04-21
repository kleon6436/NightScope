#!/usr/bin/env python3
"""
prepare_srtm.py
===============
Copernicus DEM GLO-30 データを NightScope 用の標高バイナリへ変換するスクリプト。

データソース:
  Copernicus DEM GLO-30 (1 arc-second, ~30m)
  AWS S3 公開バケット: copernicus-dem-30m（認証不要）
  ライセンス: DLR / ESA

主な利用例:

  pip install rasterio numpy scipy

  # 全球 0.05°, zlib 圧縮
  python3 Tools/prepare_srtm.py --resolution 0.05 \
      --compress --output NightScope/Models/elevation_global.bin.z

  # 日本 0.01°, zlib 圧縮
  python3 Tools/prepare_srtm.py --region japan --resolution 0.01 \
      --compress --output NightScope/Models/elevation_japan.bin.z

  # ローカル GeoTIFF を使う
  python3 Tools/prepare_srtm.py --input /path/to/dem.tif \
      --output NightScope/Models/elevation_global.bin.z --compress

出力フォーマット (*.bin / *.bin.z):

  Version 1（全球）:
    Magic:     4 bytes  = b"ELEV"
    Version:   uint32 LE = 1
    LatCells:  int32  LE  (南→北, -90〜+90)
    LonCells:  int32  LE  (西→東, -180〜+180)
    Data:      int16[] LE, row-major, 標高 [m, 海面上]

  Version 2（領域限定）:
    Magic:     4 bytes  = b"ELEV"
    Version:   uint32 LE = 2
    LatCells:  int32  LE
    LonCells:  int32  LE
    LatMin:    float32 LE
    LatMax:    float32 LE
    LonMin:    float32 LE
    LonMax:    float32 LE
    Data:      int16[] LE, row-major, 標高 [m, 海面上]

  zlib 圧縮（--compress 時）:
    Magic:     4 bytes  = b"ELVZ"
    Payload:   上記 ELEV バイナリ全体の zlib 圧縮データ
"""

import argparse
import glob
import os
import struct
import sys
import zlib

REGION_PRESETS = {
    # 沖縄〜北海道 + 対馬・南西諸島・択捉島をカバー
    "japan": {"lat_min": 20.0, "lat_max": 46.0, "lon_min": 122.0, "lon_max": 154.0},
}

_COPERNICUS_URL_TEMPLATE = (
    "https://copernicus-dem-30m.s3.eu-central-1.amazonaws.com/"
    "Copernicus_DSM_COG_10_{NS}{lat:02d}_00_{EW}{lon:03d}_00_DEM/"
    "Copernicus_DSM_COG_10_{NS}{lat:02d}_00_{EW}{lon:03d}_00_DEM.tif"
)
_COPERNICUS_CACHE_DIR = os.path.expanduser("~/.cache/copernicus-dem")


def _copernicus_tile_url(tile_lat: int, tile_lon: int) -> str:
    ns = "N" if tile_lat >= 0 else "S"
    ew = "E" if tile_lon >= 0 else "W"
    return _COPERNICUS_URL_TEMPLATE.format(NS=ns, lat=abs(tile_lat), EW=ew, lon=abs(tile_lon))


def _download_copernicus_tile(tile_lat: int, tile_lon: int) -> "str | None":
    import urllib.error
    import urllib.request

    ns = "N" if tile_lat >= 0 else "S"
    ew = "E" if tile_lon >= 0 else "W"
    filename = f"Copernicus_DSM_COG_10_{ns}{abs(tile_lat):02d}_00_{ew}{abs(tile_lon):03d}_00_DEM.tif"
    cache_path = os.path.join(_COPERNICUS_CACHE_DIR, filename)

    if os.path.exists(cache_path):
        return cache_path

    os.makedirs(_COPERNICUS_CACHE_DIR, exist_ok=True)
    url = _copernicus_tile_url(tile_lat, tile_lon)
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
                return None
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


def build_copernicus(
    lat_cells: int,
    lon_cells: int,
    res: float,
    lat_min: float,
    lat_max: float,
    lon_min: float,
    lon_max: float,
):
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

    region_label = f"lat [{lat_min:+.0f}〜{lat_max:+.0f}], lon [{lon_min:+.0f}〜{lon_max:+.0f}]"
    print("Copernicus DEM GLO-30 タイルを AWS S3 からダウンロードします（認証不要）...")
    print(f"  範囲: {region_label}")
    print(f"  キャッシュ先: {_COPERNICUS_CACHE_DIR}/")

    grid = np.zeros((lat_cells, lon_cells), dtype=np.float32)
    tile_lat_lo = int(np.floor(lat_min))
    tile_lat_hi = int(np.floor(lat_max - 1e-9))
    tile_lon_lo = int(np.floor(lon_min))
    tile_lon_hi = int(np.floor(lon_max - 1e-9))

    from concurrent.futures import ThreadPoolExecutor, as_completed

    tile_coords = [
        (lat, lon)
        for lat in range(tile_lat_lo, tile_lat_hi + 1)
        for lon in range(tile_lon_lo, tile_lon_hi + 1)
    ]

    total = len(tile_coords)
    workers = min(10, max(1, total))
    tile_paths = {}
    done = 0

    print(f"  並列ダウンロード（{workers} スレッド）...")
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {pool.submit(_download_copernicus_tile, lat, lon): (lat, lon) for lat, lon in tile_coords}
        for future in as_completed(futures):
            coord = futures[future]
            done += 1
            tile_paths[coord] = future.result()
            if done % 100 == 0 or done == total:
                pct = done / total * 100
                print(f"  DL {pct:.0f}%  ({done}/{total} tiles)", end="\r", flush=True)

    land_count = sum(1 for value in tile_paths.values() if value is not None)
    print(f"\n  ダウンロード完了: {land_count} 陸地タイル / {total} 合計")

    processed = 0
    for tile_lat, tile_lon in tile_coords:
        local_path = tile_paths[(tile_lat, tile_lon)]
        if local_path is None:
            continue

        processed += 1
        print(f"  投影 {processed}/{land_count} (lat {tile_lat:+d} lon {tile_lon:+d})", end="\r", flush=True)

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

        grid[lat_i_lo:lat_i_hi, lon_j_lo:lon_j_hi] = np.flipud(tile_dst)

    print()
    return grid


def load_from_directory(input_dir: str):
    patterns = ["*.hgt", "*.HGT", "*.tif", "*.TIF", "*.tiff", "*.TIFF"]
    files = []
    for pattern in patterns:
        files.extend(glob.glob(os.path.join(input_dir, "**", pattern), recursive=True))

    if not files:
        print(f"ERROR: {input_dir} に HGT/TIF ファイルが見つかりません。", file=sys.stderr)
        sys.exit(1)

    print(f"{len(files)} ファイルを結合します...")
    import rasterio
    from rasterio.merge import merge as rasterio_merge

    datasets = [rasterio.open(file_path) for file_path in sorted(files)]
    mosaic, transform = rasterio_merge(datasets)
    for dataset in datasets:
        dataset.close()
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
            dst_transform=rasterio.transform.from_bounds(-180, -90, 180, 90, lon_cells, lat_cells),
            dst_crs="EPSG:4326",
            resampling=Resampling.average,
        )
        if src.nodata is not None:
            data[data == src.nodata] = 0.0

    return np.flipud(data)


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
    return np.flipud(data)


def postprocess_and_write(
    data,
    lat_cells: int,
    lon_cells: int,
    output_path: str,
    lat_min: float = -90.0,
    lat_max: float = 90.0,
    lon_min: float = -180.0,
    lon_max: float = 180.0,
    compress: bool = False,
):
    import numpy as np

    data = np.nan_to_num(data, nan=0.0)
    data = np.where(data < -500, 0.0, data)
    data_int16 = data.astype(np.int16)

    is_regional = not (lat_min == -90.0 and lat_max == 90.0 and lon_min == -180.0 and lon_max == 180.0)
    version = 2 if is_regional else 1

    print(f"  統計: min={data_int16.min()} m  max={data_int16.max()} m")
    print(
        f"  フォーマット: Version {version}"
        + (f" (lat {lat_min:+.1f}〜{lat_max:+.1f}, lon {lon_min:+.1f}〜{lon_max:+.1f})" if is_regional else " (全球)")
    )
    if compress:
        print("  圧縮: zlib (マジック ELVZ)")
    print(f"出力: {output_path}")

    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)

    payload = bytearray()
    payload += b"ELEV"
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
            f.write(b"ELVZ")
            f.write(zlib.compress(bytes(payload), 9))
        else:
            f.write(payload)

    size_kb = os.path.getsize(output_path) / 1024
    if size_kb >= 1024:
        print(f"完了: {size_kb / 1024:.1f} MB")
    else:
        print(f"完了: {size_kb:.0f} KB")


def main():
    parser = argparse.ArgumentParser(
        description="Copernicus DEM データ → 地形バイナリ変換ツール",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    group = parser.add_mutually_exclusive_group()
    group.add_argument("--input", help="入力 GeoTIFF ファイルパス")
    group.add_argument("--input-dir", help="入力ディレクトリ（.hgt/.tif を再帰検索）")

    parser.add_argument(
        "--output",
        default="NightScope/Models/elevation_global.bin",
        help="出力バイナリファイルパス（デフォルト: NightScope/Models/elevation_global.bin）",
    )
    parser.add_argument("--resolution", type=float, default=0.1, help="グリッド解像度（度）。デフォルト 0.1")
    parser.add_argument("--compress", action="store_true", help="zlib 圧縮出力を有効にする（マジック ELVZ）")

    region_group = parser.add_argument_group("領域指定（未指定時は全球）")
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

    lat_min, lat_max = -90.0, 90.0
    lon_min, lon_max = -180.0, 180.0

    if args.region:
        preset = REGION_PRESETS[args.region]
        lat_min = preset["lat_min"]
        lat_max = preset["lat_max"]
        lon_min = preset["lon_min"]
        lon_max = preset["lon_max"]

    if args.lat_min is not None:
        lat_min = args.lat_min
    if args.lat_max is not None:
        lat_max = args.lat_max
    if args.lon_min is not None:
        lon_min = args.lon_min
    if args.lon_max is not None:
        lon_max = args.lon_max

    if args.output.endswith(".bin.z") and not args.compress:
        print("INFO: 出力拡張子が .bin.z のため --compress を有効化します。")
        args.compress = True

    res = args.resolution
    lat_cells = round((lat_max - lat_min) / res)
    lon_cells = round((lon_max - lon_min) / res)
    est_bytes = lat_cells * lon_cells * 2
    est_label = f"{est_bytes / (1024 * 1024):.1f} MB" if est_bytes >= 1024 * 1024 else f"{est_bytes / 1024:.0f} KB"
    print(f"解像度: {res}°  → {lat_cells} lat × {lon_cells} lon = {lat_cells * lon_cells:,} cells  (バイナリ ≈ {est_label})")

    if args.input:
        data = build_from_geotiff(args.input, lat_cells, lon_cells)
    elif args.input_dir:
        data = build_from_directory(args.input_dir, lat_cells, lon_cells)
    else:
        data = build_copernicus(lat_cells, lon_cells, res, lat_min, lat_max, lon_min, lon_max)

    postprocess_and_write(
        data,
        lat_cells,
        lon_cells,
        args.output,
        lat_min,
        lat_max,
        lon_min,
        lon_max,
        compress=args.compress,
    )


if __name__ == "__main__":
    main()
