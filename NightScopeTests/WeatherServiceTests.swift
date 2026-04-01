import XCTest
@testable import NightScope

@MainActor
final class WeatherServiceTests: XCTestCase {

    private let service = WeatherService()

    // MARK: - Helpers

    /// デバイスのローカルタイムゾーンで指定時刻の時刻文字列を生成
    /// parse() の formatter と cal.component(.hour) が同じタイムゾーンを使うよう
    /// レスポンスの timezone には TimeZone.current.identifier を指定すること
    private func makeTimeString(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0) -> String {
        let tz = TimeZone.current
        var comps = DateComponents()
        comps.timeZone = tz
        comps.year = year; comps.month = month; comps.day = day
        comps.hour = hour; comps.minute = minute
        let date = Calendar(identifier: .gregorian).date(from: comps)!
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd'T'HH:mm"
        fmt.timeZone = tz
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.string(from: date)
    }

    /// 最小限のモック OpenMeteoResponse を生成
    private func makeResponse(
        times: [String],
        clouds: [Double?]? = nil,
        timezone: String? = nil,
        visibility: [Double?]? = nil,
        windGusts: [Double?]? = nil,
        cloudLow: [Double?]? = nil,
        cloudMid: [Double?]? = nil,
        cloudHigh: [Double?]? = nil,
        windSpeed500hpa: [Double?]? = nil
    ) -> OpenMeteoResponse {
        let n = times.count
        let tz = timezone ?? TimeZone.current.identifier
        let cloudData: [Double?] = clouds ?? Array(repeating: 0.0, count: n)
        return OpenMeteoResponse(
            hourly: OpenMeteoResponse.Hourly(
                time: times,
                temperature_2m: Array(repeating: 20.0, count: n),
                cloudcover: cloudData,
                precipitation: Array(repeating: 0.0, count: n),
                windspeed_10m: Array(repeating: 5.0, count: n),
                relative_humidity_2m: Array(repeating: 50.0, count: n),
                dewpoint_2m: Array(repeating: 10.0, count: n),
                weathercode: Array(repeating: 0, count: n),
                visibility: visibility,
                windgusts_10m: windGusts,
                cloud_cover_low: cloudLow,
                cloud_cover_mid: cloudMid,
                cloud_cover_high: cloudHigh,
                windspeed_500hpa: windSpeed500hpa
            ),
            timezone: tz
        )
    }

    // MARK: - dateKey

    func test_dateKey_format() {
        // 正午に作成した日付 → "yyyy-MM-dd" 形式で返る
        var comps = DateComponents()
        comps.year = 2024; comps.month = 6; comps.day = 15; comps.hour = 12
        let date = Calendar(identifier: .gregorian).date(from: comps)!
        XCTAssertEqual(service.dateKey(date), "2024-06-15")
    }

    func test_dateKey_singleDigitMonthAndDay_zeroPadded() {
        var comps = DateComponents()
        comps.year = 2024; comps.month = 1; comps.day = 3; comps.hour = 12
        let date = Calendar(identifier: .gregorian).date(from: comps)!
        XCTAssertEqual(service.dateKey(date), "2024-01-03")
    }

    // MARK: - parse: 夜間時間帯フィルタリング

    func test_parse_eveningHour_assignedToCurrentDay() {
        // hour=21 (≥20) → 当日夜のキーに入る
        let t21 = makeTimeString(year: 2024, month: 6, day: 15, hour: 21)
        let result = service.parse(response: makeResponse(times: [t21]))
        XCTAssertEqual(result.count, 1)
        XCTAssertNotNil(result["2024-06-15"], "hour=21 は当日キー '2024-06-15' に入るはず")
        XCTAssertEqual(result["2024-06-15"]?.nighttimeHours.count, 1)
    }

    func test_parse_earlyMorningHour_assignedToPreviousDay() {
        // hour=02 (≤6) → 前日夜のキーに入る (翌02h → 前日の夜)
        let t02 = makeTimeString(year: 2024, month: 6, day: 16, hour: 2)
        let result = service.parse(response: makeResponse(times: [t02]))
        XCTAssertEqual(result.count, 1)
        XCTAssertNotNil(result["2024-06-15"], "hour=02 は前日キー '2024-06-15' に入るはず")
    }

    func test_parse_hour4_includedAsEarlyMorning() {
        // hour=4 は ≤6 に含まれる → 前日キーに入る
        let t04 = makeTimeString(year: 2024, month: 6, day: 16, hour: 4)
        let result = service.parse(response: makeResponse(times: [t04]))
        XCTAssertEqual(result.count, 1)
        XCTAssertNotNil(result["2024-06-15"], "hour=4 は前日キーに入るはず")
    }

    func test_parse_hour5_includedAsEarlyMorning() {
        // hour=5 は ≤6 に含まれる → 天文薄明として前日キーに入る
        let t05 = makeTimeString(year: 2024, month: 6, day: 16, hour: 5)
        let result = service.parse(response: makeResponse(times: [t05]))
        XCTAssertEqual(result.count, 1)
        XCTAssertNotNil(result["2024-06-15"], "hour=5 は天文薄明として前日キー '2024-06-15' に入るはず")
    }

    func test_parse_hour6_includedAsEarlyMorning() {
        // hour=6 は ≤6 の上限 → 天文薄明として前日キーに入る
        let t06 = makeTimeString(year: 2024, month: 6, day: 16, hour: 6)
        let result = service.parse(response: makeResponse(times: [t06]))
        XCTAssertEqual(result.count, 1)
        XCTAssertNotNil(result["2024-06-15"], "hour=6 は天文薄明として前日キー '2024-06-15' に入るはず")
    }

    func test_parse_hour7_excluded() {
        // hour=7 はどちらの範囲にも含まれない → 除外
        let t07 = makeTimeString(year: 2024, month: 6, day: 15, hour: 7)
        let result = service.parse(response: makeResponse(times: [t07]))
        XCTAssertTrue(result.isEmpty, "hour=7 は夜間範囲外なので除外されるはず")
    }

    func test_parse_middayHour_excluded() {
        // hour=12 は昼間 → 除外
        let t12 = makeTimeString(year: 2024, month: 6, day: 15, hour: 12)
        let result = service.parse(response: makeResponse(times: [t12]))
        XCTAssertTrue(result.isEmpty, "hour=12 は除外されるはず")
    }

    func test_parse_hour20_includedAsEvening() {
        // hour=20 は ≥18 の範囲内 → 当日キーに入る
        let t20 = makeTimeString(year: 2024, month: 6, day: 15, hour: 20)
        let result = service.parse(response: makeResponse(times: [t20]))
        XCTAssertNotNil(result["2024-06-15"], "hour=20 は当日キーに入るはず")
    }

    // MARK: - parse: 同一夜のデータ結合

    func test_parse_eveningAndMorning_combinedIntoOneNight() {
        // evening (21h) と early morning (翌02h) が同じキーにまとまる
        let t21 = makeTimeString(year: 2024, month: 6, day: 15, hour: 21)
        let t02 = makeTimeString(year: 2024, month: 6, day: 16, hour: 2)
        let result = service.parse(response: makeResponse(times: [t21, t02]))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result["2024-06-15"]?.nighttimeHours.count, 2)
    }

    func test_parse_multipleNights_separateKeys() {
        // 2夜分のデータが別キーに分かれる
        let t21a = makeTimeString(year: 2024, month: 6, day: 15, hour: 21)
        let t21b = makeTimeString(year: 2024, month: 6, day: 16, hour: 21)
        let result = service.parse(response: makeResponse(times: [t21a, t21b]))
        XCTAssertEqual(result.count, 2)
        XCTAssertNotNil(result["2024-06-15"])
        XCTAssertNotNil(result["2024-06-16"])
    }

    // MARK: - parse: nil 値のデフォルト処理

    func test_parse_nilValues_defaultToZero() {
        let t21 = makeTimeString(year: 2024, month: 6, day: 15, hour: 21)
        let response = OpenMeteoResponse(
            hourly: OpenMeteoResponse.Hourly(
                time: [t21],
                temperature_2m: [nil],
                cloudcover: [nil],
                precipitation: [nil],
                windspeed_10m: [nil],
                relative_humidity_2m: [nil],
                dewpoint_2m: [nil],
                weathercode: [nil],
                visibility: nil,
                windgusts_10m: nil,
                cloud_cover_low: nil,
                cloud_cover_mid: nil,
                cloud_cover_high: nil,
                windspeed_500hpa: nil
            ),
            timezone: TimeZone.current.identifier
        )
        let result = service.parse(response: response)
        guard let hw = result["2024-06-15"]?.nighttimeHours.first else {
            return XCTFail("パース結果が空")
        }
        XCTAssertEqual(hw.cloudCoverPercent, 0)
        XCTAssertEqual(hw.precipitationMM, 0)
        XCTAssertEqual(hw.windSpeedKmh, 0)
        XCTAssertEqual(hw.humidityPercent, 0)
        XCTAssertEqual(hw.weatherCode, 0)
    }

    func test_parse_nilTemperature_dewpointFallsBackToTemp() {
        // dewpoint_2m が nil のとき temperature を使う (temp=0 のフォールバック)
        let t21 = makeTimeString(year: 2024, month: 6, day: 15, hour: 21)
        let response = OpenMeteoResponse(
            hourly: OpenMeteoResponse.Hourly(
                time: [t21],
                temperature_2m: [15.0],
                cloudcover: [0.0],
                precipitation: [0.0],
                windspeed_10m: [0.0],
                relative_humidity_2m: [0.0],
                dewpoint_2m: [nil], // nil → temp にフォールバック
                weathercode: [0],
                visibility: nil,
                windgusts_10m: nil,
                cloud_cover_low: nil,
                cloud_cover_mid: nil,
                cloud_cover_high: nil,
                windspeed_500hpa: nil
            ),
            timezone: TimeZone.current.identifier
        )
        let result = service.parse(response: response)
        let hw = result["2024-06-15"]?.nighttimeHours.first
        XCTAssertEqual(hw?.dewpointCelsius, 15.0, "dewpoint nil のとき temperature (15.0) にフォールバックするはず")
    }

    // MARK: - parse: DayWeatherSummary の集計値

    func test_parse_cloudCover_averaged() {
        // 20% と 40% の2時間 → avgCloudCover = 30%
        let t21 = makeTimeString(year: 2024, month: 6, day: 15, hour: 21)
        let t22 = makeTimeString(year: 2024, month: 6, day: 15, hour: 22)
        let result = service.parse(response: makeResponse(times: [t21, t22], clouds: [20.0, 40.0]))
        XCTAssertEqual(result["2024-06-15"]?.avgCloudCover ?? -1, 30.0, accuracy: 0.001)
    }

    func test_parse_nighttimeHours_sortedByDate() {
        // 逆順で渡しても nighttimeHours は date 昇順で返る
        let t22 = makeTimeString(year: 2024, month: 6, day: 15, hour: 22)
        let t21 = makeTimeString(year: 2024, month: 6, day: 15, hour: 21)
        let result = service.parse(response: makeResponse(times: [t22, t21]))
        let hours = result["2024-06-15"]?.nighttimeHours
        XCTAssertEqual(hours?.count, 2)
        if let h = hours, h.count == 2 {
            XCTAssertLessThan(h[0].date, h[1].date, "nighttimeHours は date 昇順であるべき")
        }
    }
}
