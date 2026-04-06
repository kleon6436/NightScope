import Foundation

// MARK: - Star Model

struct Star {
    let name: String        // 日本語名 (一般的な呼称)
    let ra: Double          // 赤経 (度, J2000.0)
    let dec: Double         // 赤緯 (度, J2000.0)
    let magnitude: Double   // 実視等級
}

// MARK: - Star Catalog

/// 全天の明るい恒星カタログ (等級 < 2.6 程度, 70星)
/// 座標は J2000.0 epoch
enum StarCatalog {
    static let stars: [Star] = [
        Star(name: "シリウス",          ra: 101.287, dec: -16.716, magnitude: -1.46),
        Star(name: "カノープス",         ra:  95.988, dec: -52.696, magnitude: -0.74),
        Star(name: "ケンタウルスα",      ra: 219.899, dec: -60.835, magnitude: -0.27),
        Star(name: "アークトゥルス",     ra: 213.915, dec:  19.182, magnitude: -0.05),
        Star(name: "ベガ",               ra: 279.234, dec:  38.784, magnitude:  0.03),
        Star(name: "カペラ",             ra:  79.172, dec:  45.998, magnitude:  0.08),
        Star(name: "リゲル",             ra:  78.634, dec:  -8.201, magnitude:  0.13),
        Star(name: "プロキオン",         ra: 114.826, dec:   5.225, magnitude:  0.34),
        Star(name: "アケルナル",         ra:  24.429, dec: -57.237, magnitude:  0.46),
        Star(name: "ベテルギウス",       ra:  88.793, dec:   7.407, magnitude:  0.50),
        Star(name: "ハダル",             ra: 210.956, dec: -60.373, magnitude:  0.61),
        Star(name: "アルタイル",         ra: 297.696, dec:   8.868, magnitude:  0.77),
        Star(name: "アクルックス",       ra: 186.649, dec: -63.099, magnitude:  0.79),
        Star(name: "アルデバラン",       ra:  68.980, dec:  16.509, magnitude:  0.85),
        Star(name: "スピカ",             ra: 201.298, dec: -11.161, magnitude:  0.97),
        Star(name: "アンタレス",         ra: 247.352, dec: -26.432, magnitude:  1.06),
        Star(name: "ポルックス",         ra: 116.329, dec:  28.026, magnitude:  1.14),
        Star(name: "フォーマルハウト",   ra: 344.413, dec: -29.622, magnitude:  1.16),
        Star(name: "デネブ",             ra: 310.358, dec:  45.280, magnitude:  1.25),
        Star(name: "ミモザ",             ra: 191.930, dec: -59.688, magnitude:  1.25),
        Star(name: "レグルス",           ra: 152.093, dec:  11.967, magnitude:  1.35),
        Star(name: "アダラ",             ra: 104.656, dec: -28.972, magnitude:  1.50),
        Star(name: "カストル",           ra: 113.649, dec:  31.888, magnitude:  1.57),
        Star(name: "シャウラ",           ra: 263.402, dec: -37.103, magnitude:  1.62),
        Star(name: "ガクルックス",       ra: 187.791, dec: -57.113, magnitude:  1.63),
        Star(name: "ベラトリックス",     ra:  81.283, dec:   6.350, magnitude:  1.64),
        Star(name: "エルナト",           ra:  81.573, dec:  28.608, magnitude:  1.65),
        Star(name: "ミアプラキドゥス",   ra: 138.300, dec: -69.717, magnitude:  1.67),
        Star(name: "アルニラム",         ra:  84.053, dec:  -1.202, magnitude:  1.69),
        Star(name: "アルナイル",         ra: 332.058, dec: -46.961, magnitude:  1.73),
        Star(name: "アリオト",           ra: 193.507, dec:  55.960, magnitude:  1.76),
        Star(name: "アルニタク",         ra:  85.190, dec:  -1.943, magnitude:  1.77),
        Star(name: "ドゥベ",             ra: 165.932, dec:  61.751, magnitude:  1.79),
        Star(name: "ミルファク",         ra:  51.081, dec:  49.861, magnitude:  1.79),
        Star(name: "ウェゼン",           ra: 107.098, dec: -26.393, magnitude:  1.83),
        Star(name: "アヴィオル",         ra: 125.628, dec: -59.509, magnitude:  1.86),
        Star(name: "サルガス",           ra: 264.330, dec: -42.997, magnitude:  1.86),
        Star(name: "アルカイド",         ra: 206.885, dec:  49.313, magnitude:  1.86),
        Star(name: "カウス・オーストラリス", ra: 276.043, dec: -34.385, magnitude:  1.85),
        Star(name: "メンカリナン",       ra:  89.882, dec:  44.948, magnitude:  1.90),
        Star(name: "アトリア",           ra: 247.562, dec: -68.679, magnitude:  1.92),
        Star(name: "デルタ・ベラ",       ra: 131.176, dec: -54.709, magnitude:  1.93),
        Star(name: "アルヘナ",           ra:  99.428, dec:  16.400, magnitude:  1.93),
        Star(name: "ピーコック",         ra: 306.412, dec: -56.735, magnitude:  1.94),
        Star(name: "ポラリス",           ra:  37.954, dec:  89.264, magnitude:  1.97),
        Star(name: "ミルザム",           ra:  95.675, dec: -17.956, magnitude:  1.98),
        Star(name: "アルファルド",       ra: 141.897, dec:  -8.659, magnitude:  1.99),
        Star(name: "ハマル",             ra:  31.793, dec:  23.463, magnitude:  2.00),
        Star(name: "ヌンキ",             ra: 283.816, dec: -26.297, magnitude:  2.05),
        Star(name: "デネブ・カイトス",   ra:  10.897, dec: -17.987, magnitude:  2.04),
        Star(name: "サイフ",             ra:  86.939, dec:  -9.670, magnitude:  2.07),
        Star(name: "ラスアルハゲ",       ra: 263.734, dec:  12.560, magnitude:  2.08),
        Star(name: "コキャブ",           ra: 222.676, dec:  74.156, magnitude:  2.08),
        Star(name: "アルフェラッツ",     ra:   2.097, dec:  29.090, magnitude:  2.07),
        Star(name: "ミラク",             ra:  17.433, dec:  35.620, magnitude:  2.07),
        Star(name: "アルゴル",           ra:  47.042, dec:  40.956, magnitude:  2.09),
        Star(name: "ティアキ",           ra: 340.654, dec: -46.885, magnitude:  2.11),
        Star(name: "ムフルファイン",     ra: 190.379, dec: -48.959, magnitude:  2.17),
        Star(name: "シェダル",           ra:  10.127, dec:  56.537, magnitude:  2.23),
        Star(name: "エルタニン",         ra: 269.151, dec:  51.489, magnitude:  2.24),
        Star(name: "カフ",               ra:   2.294, dec:  59.150, magnitude:  2.27),
        Star(name: "デネボラ",           ra: 177.265, dec:  14.572, magnitude:  2.14),
        Star(name: "メンケント",         ra: 211.671, dec: -36.370, magnitude:  2.06),
        Star(name: "シェアト",           ra: 345.944, dec:  28.083, magnitude:  2.44),
        Star(name: "マルカブ",           ra: 346.190, dec:  15.205, magnitude:  2.49),
        Star(name: "メンカル",           ra:  45.570, dec:   4.090, magnitude:  2.53),
        Star(name: "サビク",             ra: 257.595, dec: -15.724, magnitude:  2.43),
        Star(name: "ムフリド",           ra: 219.461, dec:  18.398, magnitude:  2.68),
        Star(name: "アルゲニブ",         ra:   3.309, dec:  15.184, magnitude:  2.84),
        Star(name: "アルフィルク",       ra: 322.165, dec:  10.132, magnitude:  2.44),
    ]
}
