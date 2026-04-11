#!/usr/bin/env python3
"""
Generate stars_fill.json from Yale Bright Star Catalogue (BSC5) – FULL catalog.
Downloads BSC5 catalog from VizieR and outputs fill star data for NightScope.

Output: NightScope/Models/stars_fill.json
Format: [[ra_deg, dec_deg, magnitude], ...]  (all ~9000 BSC5 stars minus named stars)
"""
import json
import math
import urllib.request
import gzip

# Named stars RA+Dec from StarCatalog.swift — used to exclude duplicates
NAMED_STARS = [
    (101.287, -16.716),  # シリウス
    ( 95.988, -52.696),  # カノープス
    (219.899, -60.835),  # ケンタウルスα
    (213.915,  19.182),  # アークトゥルス
    (279.234,  38.784),  # ベガ
    ( 79.172,  45.998),  # カペラ
    ( 78.634,  -8.201),  # リゲル
    (114.826,   5.225),  # プロキオン
    ( 24.429, -57.237),  # アケルナル
    ( 88.793,   7.407),  # ベテルギウス
    (210.956, -60.373),  # ハダル
    (297.696,   8.868),  # アルタイル
    (186.649, -63.099),  # アクルックス
    ( 68.980,  16.509),  # アルデバラン
    (201.298, -11.161),  # スピカ
    (247.352, -26.432),  # アンタレス
    (116.329,  28.026),  # ポルックス
    (344.413, -29.622),  # フォーマルハウト
    (310.358,  45.280),  # デネブ
    (191.930, -59.688),  # ミモザ
    (152.093,  11.967),  # レグルス
    (104.656, -28.972),  # アダラ
    (113.649,  31.888),  # カストル
    (263.402, -37.103),  # シャウラ
    (187.791, -57.113),  # ガクルックス
    ( 81.283,   6.350),  # ベラトリックス
    ( 81.573,  28.608),  # エルナト
    (138.300, -69.717),  # ミアプラキドゥス
    ( 84.053,  -1.202),  # アルニラム
    (332.058, -46.961),  # アルナイル
    (193.507,  55.960),  # アリオト
    ( 85.190,  -1.943),  # アルニタク
    (165.932,  61.751),  # ドゥベ
    ( 51.081,  49.861),  # ミルファク
    (107.098, -26.393),  # ウェゼン
    (125.628, -59.509),  # アヴィオル
    (264.330, -42.997),  # サルガス
    (206.885,  49.313),  # アルカイド
    (276.043, -34.385),  # カウス・オーストラリス
    ( 89.882,  44.948),  # メンカリナン
    (247.562, -68.679),  # アトリア
    ( 99.428,  16.400),  # アルヘナ
    (306.412, -56.735),  # ピーコック
    ( 37.954,  89.264),  # ポラリス
    ( 95.675, -17.956),  # ミルザム
    (141.897,  -8.659),  # アルファルド
    (154.993,  19.841),  # アルギエバ
    ( 31.793,  23.463),  # ハマル
    ( 10.897, -17.987),  # デネブ・カイトス
    (200.981,  54.925),  # ミザール
    (283.816, -26.297),  # ヌンキ
    (  2.097,  29.090),  # アルフェラッツ
    ( 17.433,  35.620),  # ミラク
    ( 86.939,  -9.670),  # サイフ
    (263.734,  12.560),  # ラスアルハゲ
    (222.676,  74.156),  # コキャブ
    ( 47.042,  40.956),  # アルゴル
    (340.654, -46.885),  # ティアキ
    (177.265,  14.572),  # デネボラ
    (190.379, -48.959),  # ムフルファイン
    (247.555, -28.216),  # タウ・スコルピ
    (305.557,  40.257),  # サドル
    (252.541, -34.293),  # イプシロン・スコルピ
    (240.083, -22.622),  # デシュッバ
    (165.460,  56.383),  # メラク
    (178.458,  53.695),  # フェクダ
    (345.944,  28.083),  # シェアト
    ( 14.177,  60.717),  # ガンマ・カシオペア
    (346.190,  15.205),  # マルカブ
    ( 45.570,   4.090),  # メンカル
    (168.527,  20.524),  # ゾズマ
    (285.653, -29.880),  # アスケラ
    (241.359, -19.805),  # グラフィアス
    (220.482, -47.388),  # アルファ・ルピ
    ( 21.454,  60.236),  # ルクバー
    (219.461,  18.398),  # ムフリド
    (274.407, -29.828),  # カウスメディア
    (296.565,  10.613),  # タラゼド
    (190.415,  -1.449),  # ポリマ
    (276.992, -25.422),  # カウスボレアリス
    (195.544,  10.959),  # ヴィンデミアトリックス
    (  3.309,  15.184),  # アルゲニブ
    (311.553,  33.970),  # ギエナ
    (296.244,  45.131),  # デルタ・キグヌス
    ( 95.740,  22.514),  # テジャト
    ( 83.000,  -0.300),  # ミンタカ
    (258.661,  14.390),  # ラスアルゲティ
    (257.595, -15.724),  # サビク
    (111.024, -29.303),  # アルドラ
    (269.151,  51.489),  # エルタニン
    ( 10.127,  56.537),  # シェダル
    (  2.294,  59.150),  # カフ
    ( 84.411,  21.143),  # ゼータ・タウリ
    (292.680,  27.960),  # アルビレオ
    (253.084, -38.047),  # ムー・スコルピ
    (286.736, -27.671),  # アルナスル
    (271.452, -30.424),  # ナッシュ
    (230.182,  71.834),  # フルカド
    (100.983,  25.131),  # メブスダ
    (253.504, -42.363),  # ゼータ・スコルピ
    (254.655, -43.239),  # エータ・スコルピ
    (264.330, -37.303),  # ウプシロン・スコルピ
    (224.633, -43.133),  # ベータ・ルピ
    (288.138,   5.569),  # ゼータ・アクィラ
    (284.736,  32.690),  # スラファト
    (282.520,  33.363),  # シェリアク
    ( 28.599,  63.670),  # セギン
    (183.857,  57.033),  # メグレズ
    (146.463,  23.774),  # ラス・エラセド
    (148.028,  16.762),  # エータ・レオニス
    (154.171,  23.417),  # アドハフェラ
    (110.031,  21.982),  # ワサット
    (101.321,  12.896),  # アルツィル
    ( 56.871,  24.105),  # イータ・タウリ
    ( 26.350,  20.808),  # シェラト
    ( 65.649,  15.629),  # ガンマ・タウリ
    ( 67.154,  17.542),  # デルタ・タウリ
    ( 68.499,  19.180),  # エプシロン・タウリ
    ( 75.492,  43.823),  # アルマアズ
    (290.418,  -0.821),  # テータ・アクィラ
    (277.893, -26.987),  # ファイ・スゲータリ
]


def angular_distance_deg(ra1, dec1, ra2, dec2):
    """Compute angular distance between two points (all in degrees)."""
    r1 = math.radians(ra1)
    d1 = math.radians(dec1)
    r2 = math.radians(ra2)
    d2 = math.radians(dec2)
    cos_d = (math.sin(d1) * math.sin(d2) +
             math.cos(d1) * math.cos(d2) * math.cos(r1 - r2))
    cos_d = max(-1.0, min(1.0, cos_d))
    return math.degrees(math.acos(cos_d))


def is_named(ra, dec, tol=0.15):
    """Return True if star is within tol degrees of any named star."""
    for nra, ndec in NAMED_STARS:
        if angular_distance_deg(ra, dec, nra, ndec) < tol:
            return True
    return False


def download_bsc5():
    """Download BSC5 catalog.gz from VizieR."""
    urls = [
        "https://cdsarc.cds.unistra.fr/ftp/V/50/catalog.gz",
        "http://cdsarc.u-strasbg.fr/ftp/V/50/catalog.gz",
    ]
    for url in urls:
        try:
            print(f"Downloading BSC5 from {url} ...")
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req, timeout=60) as resp:
                raw = resp.read()
            return gzip.decompress(raw).decode("ascii", errors="replace")
        except Exception as e:
            print(f"  Failed: {e}")
    raise RuntimeError("Could not download BSC5 catalog.")


def parse_bsc5(text):
    """
    Parse BSC5 fixed-format lines.
    Empirically verified column positions (0-indexed):
      75-76  RA2000 hours    (2 chars)
      77-78  RA2000 minutes  (2 chars)
      79-82  RA2000 seconds  (4 chars, F4.1)
      83     Dec2000 sign    (1 char)
      84-85  Dec2000 degrees (2 chars)
      86-87  Dec2000 arcmin  (2 chars)
      88-89  Dec2000 arcsec  (2 chars, integer)
     102-106 Vmag            (5 chars, F5.2)
    Verified: Sirius gives RA=101.287 Dec=-16.716 Vmag=-1.46 ✓
    """
    stars = []
    for line in text.splitlines():
        if len(line) < 107:
            continue

        # RA J2000 (0-indexed)
        ra_h_s  = line[75:77].strip()
        ra_m_s  = line[77:79].strip()
        ra_s_s  = line[79:83].strip()

        # Dec J2000 (0-indexed)
        sign    = line[83]
        dec_d_s = line[84:86].strip()
        dec_m_s = line[86:88].strip()
        dec_s_s = line[88:90].strip()

        # Vmag (0-indexed: 102-107)
        vmag_s  = line[102:107].strip()

        if not ra_h_s or not vmag_s:
            continue

        try:
            ra_deg  = (float(ra_h_s) + float(ra_m_s or 0) / 60 +
                       float(ra_s_s or 0) / 3600) * 15.0
            dec_abs = (float(dec_d_s or 0) + float(dec_m_s or 0) / 60 +
                       float(dec_s_s or 0) / 3600)
            dec_deg = -dec_abs if sign == '-' else dec_abs
            vmag    = float(vmag_s)
        except ValueError:
            continue

        if is_named(ra_deg, dec_deg):
            continue

        stars.append([round(ra_deg, 3), round(dec_deg, 3), round(vmag, 2)])

    return stars


if __name__ == "__main__":
    import os, sys

    text   = download_bsc5()
    stars  = parse_bsc5(text)
    print(f"Parsed {len(stars)} fill stars from BSC5.")

    out_dir  = os.path.join(os.path.dirname(__file__), "..", "NightScope", "Models")
    out_path = os.path.join(out_dir, "stars_fill.json")
    os.makedirs(out_dir, exist_ok=True)

    with open(out_path, "w") as f:
        json.dump(stars, f, separators=(",", ":"))

    size_kb = os.path.getsize(out_path) / 1024
    print(f"Written to {out_path}  ({size_kb:.1f} KB)")
