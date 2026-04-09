import Foundation

// MARK: - Star Model

struct Star {
    let name: String        // 日本語名 (明るい星のみ)
    let ra: Double          // 赤経 (度, J2000.0)
    let dec: Double         // 赤緯 (度, J2000.0)
    let magnitude: Double   // 実視等級
}

// MARK: - Star Catalog
// namedStars: 日本語名付き 121 星 (等級 ≤ 3.8)
// fillStars:  Yale BSC5 全星 ~8,971 星 (名前なし、stars_fill.json から読み込み)
// 合計 ~9,092 星
// 座標は Yale Bright Star Catalogue (BSC5) J2000.0 赤道座標

enum StarCatalog {
    static let stars: [Star] = namedStars + fillStars

    // MARK: - Named Stars (150 星, 日本語名付き)
    private static let namedStars: [Star] = [

        // MARK: -1.5 ~ 0.0
        Star(name: "シリウス",           ra: 101.287, dec: -16.716, magnitude: -1.46),
        Star(name: "カノープス",          ra:  95.988, dec: -52.696, magnitude: -0.74),
        Star(name: "ケンタウルスα",       ra: 219.899, dec: -60.835, magnitude: -0.27),
        Star(name: "アークトゥルス",      ra: 213.915, dec:  19.182, magnitude: -0.05),
        Star(name: "ベガ",                ra: 279.234, dec:  38.784, magnitude:  0.03),
        Star(name: "カペラ",              ra:  79.172, dec:  45.998, magnitude:  0.08),

        // MARK: 0.1 ~ 1.0
        Star(name: "リゲル",              ra:  78.634, dec:  -8.201, magnitude:  0.13),
        Star(name: "プロキオン",          ra: 114.826, dec:   5.225, magnitude:  0.34),
        Star(name: "アケルナル",          ra:  24.429, dec: -57.237, magnitude:  0.46),
        Star(name: "ベテルギウス",        ra:  88.793, dec:   7.407, magnitude:  0.50),
        Star(name: "ハダル",              ra: 210.956, dec: -60.373, magnitude:  0.61),
        Star(name: "アルタイル",          ra: 297.696, dec:   8.868, magnitude:  0.76),
        Star(name: "アクルックス",        ra: 186.649, dec: -63.099, magnitude:  0.79),
        Star(name: "アルデバラン",        ra:  68.980, dec:  16.509, magnitude:  0.85),
        Star(name: "スピカ",              ra: 201.298, dec: -11.161, magnitude:  0.97),

        // MARK: 1.0 ~ 2.0
        Star(name: "アンタレス",          ra: 247.352, dec: -26.432, magnitude:  1.06),
        Star(name: "ポルックス",          ra: 116.329, dec:  28.026, magnitude:  1.14),
        Star(name: "フォーマルハウト",    ra: 344.413, dec: -29.622, magnitude:  1.16),
        Star(name: "デネブ",              ra: 310.358, dec:  45.280, magnitude:  1.25),
        Star(name: "ミモザ",              ra: 191.930, dec: -59.688, magnitude:  1.25),
        Star(name: "レグルス",            ra: 152.093, dec:  11.967, magnitude:  1.35),
        Star(name: "アダラ",              ra: 104.656, dec: -28.972, magnitude:  1.50),
        Star(name: "カストル",            ra: 113.649, dec:  31.888, magnitude:  1.57),
        Star(name: "シャウラ",            ra: 263.402, dec: -37.103, magnitude:  1.62),
        Star(name: "ガクルックス",        ra: 187.791, dec: -57.113, magnitude:  1.63),
        Star(name: "ベラトリックス",      ra:  81.283, dec:   6.350, magnitude:  1.64),
        Star(name: "エルナト",            ra:  81.573, dec:  28.608, magnitude:  1.65),
        Star(name: "ミアプラキドゥス",    ra: 138.300, dec: -69.717, magnitude:  1.67),
        Star(name: "アルニラム",          ra:  84.053, dec:  -1.202, magnitude:  1.69),
        Star(name: "アルナイル",          ra: 332.058, dec: -46.961, magnitude:  1.73),
        Star(name: "アリオト",            ra: 193.507, dec:  55.960, magnitude:  1.76),
        Star(name: "アルニタク",          ra:  85.190, dec:  -1.943, magnitude:  1.77),
        Star(name: "ドゥベ",              ra: 165.932, dec:  61.751, magnitude:  1.79),
        Star(name: "ミルファク",          ra:  51.081, dec:  49.861, magnitude:  1.79),
        Star(name: "ウェゼン",            ra: 107.098, dec: -26.393, magnitude:  1.83),
        Star(name: "アヴィオル",          ra: 125.628, dec: -59.509, magnitude:  1.86),
        Star(name: "サルガス",            ra: 264.330, dec: -42.997, magnitude:  1.86),
        Star(name: "アルカイド",          ra: 206.885, dec:  49.313, magnitude:  1.86),
        Star(name: "カウス・オーストラリス", ra: 276.043, dec: -34.385, magnitude:  1.85),
        Star(name: "メンカリナン",        ra:  89.882, dec:  44.948, magnitude:  1.90),
        Star(name: "アトリア",            ra: 247.562, dec: -68.679, magnitude:  1.92),
        Star(name: "アルヘナ",            ra:  99.428, dec:  16.400, magnitude:  1.93),
        Star(name: "ピーコック",          ra: 306.412, dec: -56.735, magnitude:  1.94),
        Star(name: "ポラリス",            ra:  37.954, dec:  89.264, magnitude:  1.97),
        Star(name: "ミルザム",            ra:  95.675, dec: -17.956, magnitude:  1.98),
        Star(name: "アルファルド",        ra: 141.897, dec:  -8.659, magnitude:  1.99),
        Star(name: "アルギエバ",          ra: 154.993, dec:  19.841, magnitude:  2.01),

        // MARK: 2.0 ~ 2.5
        Star(name: "ハマル",              ra:  31.793, dec:  23.463, magnitude:  2.00),
        Star(name: "デネブ・カイトス",    ra:  10.897, dec: -17.987, magnitude:  2.04),
        Star(name: "ミザール",            ra: 200.981, dec:  54.925, magnitude:  2.04),
        Star(name: "ヌンキ",              ra: 283.816, dec: -26.297, magnitude:  2.05),
        Star(name: "アルフェラッツ",      ra:   2.097, dec:  29.090, magnitude:  2.07),
        Star(name: "ミラク",              ra:  17.433, dec:  35.620, magnitude:  2.07),
        Star(name: "サイフ",              ra:  86.939, dec:  -9.670, magnitude:  2.07),
        Star(name: "ラスアルハゲ",        ra: 263.734, dec:  12.560, magnitude:  2.08),
        Star(name: "コキャブ",            ra: 222.676, dec:  74.156, magnitude:  2.08),
        Star(name: "アルゴル",            ra:  47.042, dec:  40.956, magnitude:  2.09),
        Star(name: "ティアキ",            ra: 340.654, dec: -46.885, magnitude:  2.11),
        Star(name: "デネボラ",            ra: 177.265, dec:  14.572, magnitude:  2.14),
        Star(name: "ムフルファイン",      ra: 190.379, dec: -48.959, magnitude:  2.17),
        Star(name: "タウ・スコルピ",      ra: 247.555, dec: -28.216, magnitude:  2.17),
        Star(name: "サドル",              ra: 305.557, dec:  40.257, magnitude:  2.20),
        Star(name: "イプシロン・スコルピ",ra: 252.541, dec: -34.293, magnitude:  2.29),
        Star(name: "デシュッバ",          ra: 240.083, dec: -22.622, magnitude:  2.32),
        Star(name: "メラク",              ra: 165.460, dec:  56.383, magnitude:  2.37),
        Star(name: "フェクダ",            ra: 178.458, dec:  53.695, magnitude:  2.44),
        Star(name: "シェアト",            ra: 345.944, dec:  28.083, magnitude:  2.44),
        Star(name: "ガンマ・カシオペア",  ra:  14.177, dec:  60.717, magnitude:  2.47),
        Star(name: "マルカブ",            ra: 346.190, dec:  15.205, magnitude:  2.49),
        Star(name: "メンカル",            ra:  45.570, dec:   4.090, magnitude:  2.53),
        Star(name: "ゾズマ",              ra: 168.527, dec:  20.524, magnitude:  2.56),
        Star(name: "アスケラ",            ra: 285.653, dec: -29.880, magnitude:  2.59),
        Star(name: "グラフィアス",        ra: 241.359, dec: -19.805, magnitude:  2.62),
        Star(name: "アルファ・ルピ",      ra: 220.482, dec: -47.388, magnitude:  2.30),
        Star(name: "ルクバー",            ra:  21.454, dec:  60.236, magnitude:  2.68),
        Star(name: "ムフリド",            ra: 219.461, dec:  18.398, magnitude:  2.68),
        Star(name: "カウスメディア",      ra: 274.407, dec: -29.828, magnitude:  2.70),
        Star(name: "タラゼド",            ra: 296.565, dec:  10.613, magnitude:  2.72),
        Star(name: "ポリマ",              ra: 190.415, dec:  -1.449, magnitude:  2.74),
        Star(name: "カウスボレアリス",    ra: 276.992, dec: -25.422, magnitude:  2.81),
        Star(name: "ヴィンデミアトリックス", ra: 195.544, dec:  10.959, magnitude:  2.83),
        Star(name: "アルゲニブ",          ra:   3.309, dec:  15.184, magnitude:  2.84),
        Star(name: "ギエナ",              ra: 311.553, dec:  33.970, magnitude:  2.48),
        Star(name: "デルタ・キグヌス",    ra: 296.244, dec:  45.131, magnitude:  2.87),
        Star(name: "テジャト",            ra:  95.740, dec:  22.514, magnitude:  2.87),
        Star(name: "ミンタカ",            ra:  83.000, dec:  -0.300, magnitude:  2.23),

        // MARK: 2.5 ~ 3.1
        Star(name: "ラスアルゲティ",      ra: 258.661, dec:  14.390, magnitude:  2.78),
        Star(name: "サビク",              ra: 257.595, dec: -15.724, magnitude:  2.43),
        Star(name: "アルドラ",            ra: 111.024, dec: -29.303, magnitude:  2.45),
        Star(name: "エルタニン",          ra: 269.151, dec:  51.489, magnitude:  2.24),
        Star(name: "シェダル",            ra:  10.127, dec:  56.537, magnitude:  2.23),
        Star(name: "カフ",                ra:   2.294, dec:  59.150, magnitude:  2.27),
        Star(name: "ゼータ・タウリ",      ra:  84.411, dec:  21.143, magnitude:  3.00),
        Star(name: "アルビレオ",          ra: 292.680, dec:  27.960, magnitude:  3.09),
        Star(name: "ムー・スコルピ",      ra: 253.084, dec: -38.047, magnitude:  3.04),
        Star(name: "アルナスル",          ra: 286.736, dec: -27.671, magnitude:  2.98),
        Star(name: "ナッシュ",            ra: 271.452, dec: -30.424, magnitude:  2.99),
        Star(name: "フルカド",            ra: 230.182, dec:  71.834, magnitude:  3.05),
        Star(name: "メブスダ",            ra: 100.983, dec:  25.131, magnitude:  3.06),
        Star(name: "ゼータ・スコルピ",    ra: 253.504, dec: -42.363, magnitude:  3.62),
        Star(name: "エータ・スコルピ",    ra: 254.655, dec: -43.239, magnitude:  3.33),
        Star(name: "ウプシロン・スコルピ",ra: 264.330, dec: -37.303, magnitude:  2.69),
        Star(name: "ベータ・ルピ",        ra: 224.633, dec: -43.133, magnitude:  2.68),
        Star(name: "ゼータ・アクィラ",    ra: 288.138, dec:   5.569, magnitude:  2.99),
        Star(name: "スラファト",          ra: 284.736, dec:  32.690, magnitude:  3.25),
        Star(name: "シェリアク",          ra: 282.520, dec:  33.363, magnitude:  3.52),

        // MARK: 3.1 ~ 3.8
        Star(name: "セギン",              ra:  28.599, dec:  63.670, magnitude:  3.37),
        Star(name: "メグレズ",            ra: 183.857, dec:  57.033, magnitude:  3.31),
        Star(name: "ラス・エラセド",      ra: 146.463, dec:  23.774, magnitude:  2.98),
        Star(name: "エータ・レオニス",    ra: 148.028, dec:  16.762, magnitude:  3.52),
        Star(name: "アドハフェラ",        ra: 154.171, dec:  23.417, magnitude:  3.44),
        Star(name: "ワサット",            ra: 110.031, dec:  21.982, magnitude:  3.53),
        Star(name: "アルツィル",          ra: 101.321, dec:  12.896, magnitude:  3.35),
        Star(name: "イータ・タウリ",      ra:  56.871, dec:  24.105, magnitude:  2.87),
        Star(name: "シェラト",            ra:  26.350, dec:  20.808, magnitude:  2.66),
        Star(name: "ガンマ・タウリ",      ra:  65.649, dec:  15.629, magnitude:  3.65),
        Star(name: "デルタ・タウリ",      ra:  67.154, dec:  17.542, magnitude:  3.77),
        Star(name: "エプシロン・タウリ",  ra:  68.499, dec:  19.180, magnitude:  3.54),
        Star(name: "アルマアズ",          ra:  75.492, dec:  43.823, magnitude:  2.99),
        Star(name: "テータ・アクィラ",    ra: 290.418, dec:  -0.821, magnitude:  3.24),
        Star(name: "ファイ・スゲータリ",  ra: 277.893, dec: -26.987, magnitude:  3.17),
    ]

    // MARK: - Fill Stars (名前なし、BSC5 全星)
    // stars_fill.json から読み込み: [[ra°, dec°, 等級], ...]
    // namedStars と重複しない全 BSC5 星 (~8,971 個)
    private static let fillStars: [Star] = {
        guard let url = Bundle.main.url(forResource: "stars_fill", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([[Double]].self, from: data)
        else { return [] }
        return entries.map { Star(name: "", ra: $0[0], dec: $0[1], magnitude: $0[2]) }
    }()

}