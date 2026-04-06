import Foundation

/// NightScope のデータを LLM 用システムプロンプトに変換する純粋関数コレクション
enum AssistantContextBuilder {

    // MARK: - System Prompt

    /// 観測条件を埋め込んだシステムプロンプトを生成する
    static func buildSystemPrompt(
        nightSummary: NightSummary?,
        starGazingIndex: StarGazingIndex?,
        weather: DayWeatherSummary?,
        bortleClass: Double?,
        locationName: String,
        date: Date
    ) -> String {
        let role = """
        あなたは NightScope に組み込まれた星空アシスタントです。
        天文観測、星空撮影、観測計画に関する質問に実用的かつ簡潔に答えてください。
        ユーザーの言語（日本語または英語）に合わせて回答してください。
        NightScope のデータに存在しない天体データや気象情報を創作してはいけません。
        回答には必ず以下のコンテキストブロックの具体的な数値を根拠として使用してください。
        天文・観測計画以外の話題はていねいにお断りしてください。
        """

        let context = buildContextBlock(
            nightSummary: nightSummary,
            starGazingIndex: starGazingIndex,
            weather: weather,
            bortleClass: bortleClass,
            locationName: locationName,
            date: date
        )

        return [role, context].joined(separator: "\n\n")
    }

    /// 日付カード選択時の自動要約メッセージを生成する（モデルへの送信文）
    static func buildProactiveMessage(
        nightSummary: NightSummary?,
        starGazingIndex: StarGazingIndex?,
        weather: DayWeatherSummary?,
        date: Date
    ) -> String {
        let dateStr = DateFormatters.fullDate.string(from: date)

        guard let index = starGazingIndex else {
            return "\(dateStr) の星空予報が選択されました。データを取得中です。少しお待ちください。"
        }

        var parts: [String] = ["\(dateStr) の星空予報を確認しました。"]
        parts.append("星空指数は **\(index.score)点（\(index.label)）** です。")

        if let summary = nightSummary {
            if !summary.darkRangeText.isEmpty {
                parts.append("暗い時間帯: \(summary.darkRangeText)。")
            }
            if let w = weather,
               let rangeText = summary.weatherAwareRangeText(nighttimeHours: w.nighttimeHours),
               !rangeText.isEmpty, rangeText != "月明かり" {
                parts.append("天気を考慮した観測推奨時間: \(rangeText)。")
            }
            if let alt = summary.maxAltitude, let dir = summary.bestDirection {
                parts.append(String(format: "天の川: 最高高度 %.0f°（%@方向）。", alt, dir))
            }
        }

        parts.append("何かご質問があればどうぞ！")
        return parts.joined(separator: "\n")
    }

    // MARK: - Card Mode

    /// カード表示用 LLM プロンプト（天気に応じてアドバイス指示を切り替える）
    static func buildCardPrompt(weather: DayWeatherSummary?) -> String {
        let isBad = isBadWeather(weather)

        if isBad {
            return """
            今夜の観測条件について、以下の形式で回答してください。各セクションは1〜2文以内に収めてください。

            ## 要約
            （星空指数・雲量・降水状況など悪天候の根拠となる数値を引用し、今夜の観測が困難な理由を端的に）

            ## アドバイス1
            （悪天候の具体的な原因（雲量・降水・視程など）に触れ、天気回復後の観測に備える心構えを一言で）

            ## アドバイス2
            （今夜できる実践的な準備：機材メンテナンス・充電・星図学習・観測計画立案など具体的な行動を1つ）
            """
        } else {
            return """
            今夜の観測条件について、以下の形式で回答してください。各セクションは1〜2文以内に収めてください。
            コンテキストに記載された数値（スコア・時刻・高度・方角・気象値）を積極的に引用してください。

            ## 要約
            （星空指数の合計点と主要なサブスコア、天気概況を引用し今夜の観測適性を一文で結論づける）

            ## アドバイス1
            （観測推奨時間帯と天の川ウィンドウのピーク時刻・高度・方角を引用して、最適な観測プランを具体的に）

            ## アドバイス2
            （シーイング・結露リスク・光害レベルを踏まえた機材設定や撮影準備のポイントを具体的に）
            """
        }
    }

    /// LLM レスポンスを summary・advices に分割してパースする
    static func parseCardResponse(_ text: String) -> (summary: String, advices: [String]) {
        var dict: [String: String] = [:]
        var currentKey: String?
        var currentLines: [String] = []

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("## ") {
                if let key = currentKey {
                    dict[key] = currentLines.joined(separator: "\n")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
                currentKey = String(trimmed.dropFirst(3))
                currentLines = []
            } else if currentKey != nil {
                currentLines.append(line)
            }
        }
        if let key = currentKey {
            dict[key] = currentLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let summary = dict.first { $0.key.contains("要約") }?.value ?? ""
        let advice1 = dict.first { $0.key.contains("アドバイス1") || $0.key.hasSuffix("1") }?.value ?? ""
        let advice2 = dict.first { $0.key.contains("アドバイス2") || $0.key.hasSuffix("2") }?.value ?? ""
        return (summary, [advice1, advice2].filter { !$0.isEmpty })
    }

    /// LLM 非利用時のテンプレートアドバイス
    static func buildTemplateAdvices(
        nightSummary: NightSummary?,
        tier: StarGazingIndex.Tier?,
        weather: DayWeatherSummary?
    ) -> [String] {
        // 天候不良時は観測向けアドバイスを出さない
        if isBadWeather(weather) {
            let weatherLabel = weather?.weatherLabel ?? "天候不良"
            return [
                "今夜は\(weatherLabel)のため星空観測は困難です。天気が回復する日を待ちましょう。",
                "悪天候の日は機材のメンテナンスや充電、星図アプリで次回の観測計画を立てるのに最適です。"
            ]
        }

        let advice1: String
        if let summary = nightSummary {
            if let time = summary.bestViewingTime, let dir = summary.bestDirection,
               let alt = summary.maxAltitude {
                advice1 = String(
                    format: "%@頃、%@方向（高度 %.0f°）が天の川の見頃です。月明かりの影響が少ない時間帯を優先してください。",
                    time.nightTimeString(), dir, alt
                )
            } else if !summary.darkRangeText.isEmpty {
                advice1 = "暗い時間帯（\(summary.darkRangeText)）に観測してください。地平線付近の光害が少ない方向を選ぶとより良い結果が得られます。"
            } else {
                advice1 = "薄明・月明かりの影響を受けにくい時間帯を選んで観測してください。"
            }
        } else {
            advice1 = "観測データを取得中です。しばらくお待ちください。"
        }

        let advice2: String
        switch tier {
        case .excellent:
            advice2 = "絶好の条件です。ISO 3200〜6400・F1.4〜F2.8・20〜25秒露出で天の川をダイナミックに撮影できます。"
        case .good:
            advice2 = "良好なコンディションです。ISO 3200・F2.8・20秒露出を基本に調整してください。"
        case .fair:
            advice2 = "まずまずの条件です。ISO 1600〜3200・F2.8・15〜20秒露出で試してみてください。雲の切れ目を狙いましょう。"
        case .poor, .bad:
            advice2 = "観測条件が厳しい夜です。次の好条件日に備えて機材の確認と充電をしておきましょう。"
        case nil:
            advice2 = "明るいレンズ（F1.4〜F2.8）と三脚は必須です。観測前に星図アプリで天体の位置を確認しておくとスムーズです。"
        }

        return [advice1, advice2]
    }

    // MARK: - Suggestion Chips

    /// 現在の条件に応じたサジェスト質問を返す
    static func suggestionChips(for tier: StarGazingIndex.Tier?) -> [String] {
        switch tier {
        case .excellent, .good:
            return [
                "今夜のベストな観測時間は？",
                "天の川撮影のおすすめ設定は？",
                "今夜見やすい天体を教えて",
            ]
        case .fair:
            return [
                "今夜の観測条件を詳しく教えて",
                "雲があっても観測できる？",
                "この条件で撮影するコツは？",
            ]
        case .poor, .bad:
            return [
                "なぜ星空指数が低いの？",
                "次に条件が良くなるのはいつ？",
                "悪天候の日にできる準備は？",
            ]
        case nil:
            return [
                "今夜の星空について教えて",
                "観測に必要な機材は？",
                "ボートル等級とは何ですか？",
            ]
        }
    }

    // MARK: - Private Helpers

    private static func buildContextBlock(
        nightSummary: NightSummary?,
        starGazingIndex: StarGazingIndex?,
        weather: DayWeatherSummary?,
        bortleClass: Double?,
        locationName: String,
        date: Date
    ) -> String {
        let dateStr = DateFormatters.fullDate.string(from: date)
        var lines: [String] = ["## 今夜の観測条件（\(dateStr) / \(locationName)）"]

        // MARK: 星空指数
        if let index = starGazingIndex {
            lines.append("")
            lines.append("### 星空指数")
            lines.append("総合: \(index.score)/100（\(index.label)）")
            lines.append("- 空の暗さ: \(index.constellationScore)/\(StarGazingIndex.maxConstellationScore)（\(scoreLabel(index.constellationScore, max: StarGazingIndex.maxConstellationScore))）")
            let weatherDataNote = index.hasWeatherData ? "" : "・気象データなし"
            lines.append("- 天気:     \(index.weatherScore)/\(StarGazingIndex.maxWeatherScore)（\(scoreLabel(index.weatherScore, max: StarGazingIndex.maxWeatherScore))\(weatherDataNote)）")
            let pollutionDataNote = index.hasLightPollutionData ? "" : "・光害データなし"
            lines.append("- 光害:     \(index.lightPollutionScore)/\(StarGazingIndex.maxLightPollutionScore)（\(scoreLabel(index.lightPollutionScore, max: StarGazingIndex.maxLightPollutionScore))\(pollutionDataNote)）")
            lines.append("- 天の川可視性（参考）: \(index.milkyWayScore)/\(StarGazingIndex.maxMilkyWayScore)（\(scoreLabel(index.milkyWayScore, max: StarGazingIndex.maxMilkyWayScore))）")
        }

        if let summary = nightSummary {

            // MARK: 月・天文薄明
            lines.append("")
            lines.append("### 月・天文薄明")
            let illumination = Int((1.0 - cos(summary.moonPhaseAtMidnight * 2.0 * .pi)) / 2.0 * 100)
            lines.append("- 月相: \(summary.moonPhaseName)（照度 \(illumination)%）")
            lines.append("- 月明かりへの影響: \(summary.isMoonFavorable ? "少ない（新月付近）" : "あり（明るい月）")")
            let moonFraction = Int(summary.moonAboveHorizonFractionDuringDark * 100)
            lines.append("- 暗い時間帯に月が出ている割合: \(moonFraction)%")
            if summary.totalDarkHours > 0 {
                lines.append(String(format: "- 天文薄明後の暗い時間: %.1f時間（%@）", summary.totalDarkHours, summary.darkRangeText))
            } else {
                lines.append("- 天文薄明後の暗い時間: なし（月明かりまたは薄明が全時間に重なる）")
            }

            // MARK: 天の川観測ウィンドウ
            lines.append("")
            lines.append("### 天の川観測ウィンドウ")
            if summary.viewingWindows.isEmpty {
                lines.append("- 観測可能なウィンドウなし（銀河系中心が地平線上に出ない、または薄明・月明かりと重複）")
            } else {
                for (i, window) in summary.viewingWindows.enumerated() {
                    let durationH = window.duration / 3600
                    lines.append(String(
                        format: "- ウィンドウ%d: %@〜%@（%.1f時間）/ ピーク %@ 高度 %.0f° %@方向",
                        i + 1,
                        window.start.nightTimeString(),
                        window.end.nightTimeString(),
                        durationH,
                        window.peakTime.nightTimeString(),
                        window.peakAltitude,
                        window.peakDirectionName
                    ))
                }
                lines.append(String(format: "- 合計観測可能時間: %.1f時間", summary.totalViewingHours))
            }

            // Weather-aware recommended range
            if let w = weather,
               let rangeText = summary.weatherAwareRangeText(nighttimeHours: w.nighttimeHours) {
                let label: String
                if rangeText.isEmpty {
                    label = "天候不良のため観測不可"
                } else if rangeText == "月明かり" {
                    label = "月明かりの影響で制限あり"
                } else {
                    label = rangeText
                }
                lines.append("- 気象・月を考慮した観測推奨時間帯: \(label)")
            }

            // MARK: 天気詳細
            if let w = weather {
                lines.append("")
                lines.append("### 天気詳細")
                lines.append("- 天気概況: \(w.weatherLabel)（雲量 \(Int(w.avgCloudCover))%）")

                // cloud layers
                if let effective = w.effectiveCloudCover {
                    lines.append(String(format: "- 実効雲量（透明度影響度）: %.0f%%", effective))
                } else {
                    var layerParts: [String] = []
                    if let low = w.avgCloudCoverLow  { layerParts.append(String(format: "下層 %.0f%%", low)) }
                    if let mid = w.avgCloudCoverMid  { layerParts.append(String(format: "中層 %.0f%%", mid)) }
                    if let high = w.avgCloudCoverHigh { layerParts.append(String(format: "上層 %.0f%%", high)) }
                    if !layerParts.isEmpty {
                        lines.append("- 雲量（層別）: \(layerParts.joined(separator: "・"))")
                    }
                }

                if w.maxPrecipitation > 0 {
                    lines.append(String(format: "- 最大降水量: %.1f mm/h", w.maxPrecipitation))
                }

                // wind & seeing
                lines.append(String(format: "- 地上風速: %.0f km/h", w.avgWindSpeed))
                if let gusts = w.maxWindGusts {
                    lines.append(String(format: "- 最大瞬間風速: %.0f km/h", gusts))
                }
                if let upper = w.avgWindSpeed500hpa {
                    let seeingQuality: String
                    switch upper {
                    case ..<30:  seeingQuality = "良好"
                    case ..<60:  seeingQuality = "やや悪い"
                    default:     seeingQuality = "悪い"
                    }
                    lines.append(String(format: "- 上空風速（500 hPa）: %.0f km/h → シーイング: %@", upper, seeingQuality))
                }

                // temperature & dew risk
                lines.append(String(format: "- 最低気温: %.1f°C / 湿度: %.0f%%", w.minTemperature, w.avgHumidity))
                if w.avgDewpointSpread > 0 {
                    let dewRisk: String
                    switch w.avgDewpointSpread {
                    case ..<3:  dewRisk = "結露リスク高（レンズヒーター推奨）"
                    case ..<6:  dewRisk = "結露リスクあり（注意）"
                    default:    dewRisk = "結露リスク低"
                    }
                    lines.append(String(format: "- 露点温度差: %.1f°C → %@", w.avgDewpointSpread, dewRisk))
                }

                // visibility
                if let vis = w.avgVisibilityMeters {
                    let visKm = vis / 1000.0
                    let visLabel: String
                    switch visKm {
                    case 20...:  visLabel = "良好"
                    case 10...:  visLabel = "普通"
                    case 5...:   visLabel = "やや悪い"
                    default:     visLabel = "悪い"
                    }
                    lines.append(String(format: "- 視程: %.0f km（%@）", visKm, visLabel))
                }
            }
        }

        // MARK: 光害環境
        if let bortle = bortleClass {
            lines.append("")
            lines.append("### 光害環境")
            lines.append(String(format: "- ボートル等級: %.0f（%@）", bortle, bortleDescription(bortle)))
        }

        if nightSummary == nil && starGazingIndex == nil {
            lines.append("")
            lines.append("（データ取得中 — 質問には一般的な星空情報でお答えします）")
        }

        return lines.joined(separator: "\n")
    }

    /// サブスコアの達成率から定性的なラベルを返す
    private static func scoreLabel(_ score: Int, max: Int) -> String {
        let ratio = Double(score) / Double(max)
        switch ratio {
        case 0.85...: return "優秀"
        case 0.67...: return "良好"
        case 0.50...: return "標準"
        case 0.33...: return "低め"
        default:      return "不足"
        }
    }

    private static func bortleDescription(_ bortle: Double) -> String {
        switch bortle {
        case ..<2:  return "最暗空"
        case ..<3:  return "非常に暗い"
        case ..<4:  return "田舎の空"
        case ..<5:  return "郊外・農村の空"
        case ..<6:  return "郊外の空"
        case ..<7:  return "明るい郊外"
        case ..<8:  return "郊外と都市の間"
        case ..<9:  return "都市の空"
        default:    return "都市中心部"
        }
    }

    /// 天候不良かどうかを判定する（雨・雪・濃霧・雲量75%超）
    private static func isBadWeather(_ weather: DayWeatherSummary?) -> Bool {
        guard let weather else { return false }
        return weather.representativeWeatherCode >= 51 || weather.avgCloudCover >= 75
    }
}

// MARK: - DayWeatherSummary helpers

private extension DayWeatherSummary {
    var avgVisibilityKm: Double? {
        guard let meters = avgVisibilityMeters else { return nil }
        return meters / 1000.0
    }
}
