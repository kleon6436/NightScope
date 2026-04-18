import XCTest
import CoreLocation
@testable import NightScope

@MainActor
final class WeatherServiceTests: XCTestCase {

    private let service = WeatherService()
    private let tokyoLocation = CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)
    private let tokyoTimeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current

    // MARK: - Helpers

    /// デバイスのローカルタイムゾーンで指定ローカル時刻に対応する UTC ISO8601 文字列を生成。
    /// MET Norway API はすべてのタイムスタンプを UTC ("Z" サフィックス) で返す。
    private func makeTimeString(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0) -> String {
        let tz = tokyoTimeZone
        var comps = DateComponents()
        comps.timeZone = tz
        comps.year = year; comps.month = month; comps.day = day
        comps.hour = hour; comps.minute = minute
        let date = Calendar(identifier: .gregorian).date(from: comps)!
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        return fmt.string(from: date)  // UTC ISO8601 e.g. "2024-06-15T12:00:00Z" (UTC+9 hour=21)
    }

    /// 1 タイムステップ分の MetNorwayResponse タイムシリーズエントリを生成するヘルパー。
    private func makeTimeseries(
        time: String,
        cloud: Double = 0,
        temp: Double = 20,
        windMps: Double = 5.0 / 3.6,
        humidity: Double = 50,
        dewpoint: Double = 10,
        precip: Double = 0,
        symbolCode: String = "clearsky_night",
        cloudLow: Double? = nil,
        cloudMid: Double? = nil,
        cloudHigh: Double? = nil,
        forecastStepHours: Int = 1
    ) -> MetNorwayResponse.Properties.Timeseries {
        let details = MetNorwayResponse.Properties.Timeseries.Data.Instant.Details(
            air_temperature: temp,
            cloud_area_fraction: cloud,
            cloud_area_fraction_low: cloudLow,
            cloud_area_fraction_medium: cloudMid,
            cloud_area_fraction_high: cloudHigh,
            wind_speed: windMps,
            wind_speed_of_gust: nil,
            relative_humidity: humidity,
            dew_point_temperature: dewpoint
        )
        let next1 = forecastStepHours == 1
            ? MetNorwayResponse.Properties.Timeseries.Data.Next1Hours(
                summary: .init(symbol_code: symbolCode),
                details: .init(precipitation_amount: precip)
            )
            : nil
        let next6 = forecastStepHours == 6
            ? MetNorwayResponse.Properties.Timeseries.Data.Next6Hours(
                summary: .init(symbol_code: symbolCode),
                details: .init(precipitation_amount: precip)
            )
            : nil
        let data = MetNorwayResponse.Properties.Timeseries.Data(
            instant: .init(details: details),
            next_1_hours: next1,
            next_6_hours: next6
        )
        return MetNorwayResponse.Properties.Timeseries(time: time, data: data)
    }

    /// 最小限のモック MetNorwayResponse を生成
    private func makeResponse(
        times: [String],
        clouds: [Double?]? = nil,
        cloudLow: [Double?]? = nil,
        cloudMid: [Double?]? = nil,
        cloudHigh: [Double?]? = nil
    ) -> MetNorwayResponse {
        let n = times.count
        var entries: [MetNorwayResponse.Properties.Timeseries] = []
        for i in 0..<n {
            entries.append(makeTimeseries(
                time: times[i],
                cloud: clouds?[i] ?? 0,
                cloudLow: cloudLow?[i] ?? nil,
                cloudMid: cloudMid?[i] ?? nil,
                cloudHigh: cloudHigh?[i] ?? nil
            ))
        }
        return MetNorwayResponse(properties: .init(timeseries: entries))
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
        let result = service.parse(response: makeResponse(times: [t21]), location: tokyoLocation, timeZone: tokyoTimeZone)
        XCTAssertEqual(result.count, 1)
        XCTAssertNotNil(result["2024-06-15"], "hour=21 は当日キー '2024-06-15' に入るはず")
        XCTAssertEqual(result["2024-06-15"]?.nighttimeHours.count, 1)
    }

    func test_parse_earlyMorningHour_assignedToPreviousDay() {
        // hour=02 (≤6) → 前日夜のキーに入る (翌02h → 前日の夜)
        let t02 = makeTimeString(year: 2024, month: 6, day: 16, hour: 2)
        let result = service.parse(response: makeResponse(times: [t02]), location: tokyoLocation, timeZone: tokyoTimeZone)
        XCTAssertEqual(result.count, 1)
        XCTAssertNotNil(result["2024-06-15"], "hour=02 は前日キー '2024-06-15' に入るはず")
    }

    func test_parse_hour4_excludedWhenOutsideRealNightInterval() {
        let t04 = makeTimeString(year: 2024, month: 6, day: 16, hour: 4)
        let result = service.parse(response: makeResponse(times: [t04]), location: tokyoLocation, timeZone: tokyoTimeZone)
        XCTAssertTrue(result.isEmpty, "hour=4 は実際の夜区間外なら除外されるはず")
    }

    func test_parse_hour5_excludedWhenOutsideRealNightInterval() {
        let t05 = makeTimeString(year: 2024, month: 6, day: 16, hour: 5)
        let result = service.parse(response: makeResponse(times: [t05]), location: tokyoLocation, timeZone: tokyoTimeZone)
        XCTAssertTrue(result.isEmpty, "hour=5 は実際の夜区間外なら除外されるはず")
    }

    func test_parse_hour6_excludedWhenOutsideRealNightInterval() {
        let t06 = makeTimeString(year: 2024, month: 6, day: 16, hour: 6)
        let result = service.parse(response: makeResponse(times: [t06]), location: tokyoLocation, timeZone: tokyoTimeZone)
        XCTAssertTrue(result.isEmpty, "hour=6 は実際の夜区間外なら除外されるはず")
    }

    func test_parse_hour7_excluded() {
        // hour=7 はどちらの範囲にも含まれない → 除外
        let t07 = makeTimeString(year: 2024, month: 6, day: 15, hour: 7)
        let result = service.parse(response: makeResponse(times: [t07]), location: tokyoLocation, timeZone: tokyoTimeZone)
        XCTAssertTrue(result.isEmpty, "hour=7 は夜間範囲外なので除外されるはず")
    }

    func test_parse_middayHour_excluded() {
        // hour=12 は昼間 → 除外
        let t12 = makeTimeString(year: 2024, month: 6, day: 15, hour: 12)
        let result = service.parse(response: makeResponse(times: [t12]), location: tokyoLocation, timeZone: tokyoTimeZone)
        XCTAssertTrue(result.isEmpty, "hour=12 は除外されるはず")
    }

    func test_parse_hour20_includedAsEvening() {
        // hour=20 は ≥18 の範囲内 → 当日キーに入る
        let t20 = makeTimeString(year: 2024, month: 6, day: 15, hour: 20)
        let result = service.parse(response: makeResponse(times: [t20]), location: tokyoLocation, timeZone: tokyoTimeZone)
        XCTAssertNotNil(result["2024-06-15"], "hour=20 は当日キーに入るはず")
    }

    // MARK: - parse: 同一夜のデータ結合

    func test_parse_eveningAndMorning_combinedIntoOneNight() {
        // evening (21h) と early morning (翌02h) が同じキーにまとまる
        let t21 = makeTimeString(year: 2024, month: 6, day: 15, hour: 21)
        let t02 = makeTimeString(year: 2024, month: 6, day: 16, hour: 2)
        let result = service.parse(response: makeResponse(times: [t21, t02]), location: tokyoLocation, timeZone: tokyoTimeZone)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result["2024-06-15"]?.nighttimeHours.count, 2)
    }

    func test_parse_next6Hours_expandsIntoHourlyNightCoverage() throws {
        let t21 = makeTimeString(year: 2024, month: 6, day: 15, hour: 21)
        let response = MetNorwayResponse(properties: .init(timeseries: [
            makeTimeseries(
                time: t21,
                cloud: 30,
                precip: 0.5,
                symbolCode: "rain",
                forecastStepHours: 6
            )
        ]))

        let result = service.parse(response: response, location: tokyoLocation, timeZone: tokyoTimeZone)
        let hours = try XCTUnwrap(result["2024-06-15"]?.nighttimeHours)
        let firstHour = try XCTUnwrap(hours.first)
        let lastHour = try XCTUnwrap(hours.last)

        XCTAssertEqual(hours.count, 6)
        XCTAssertEqual(firstHour.precipitationMM, 0.5 / 6.0, accuracy: 0.001)
        XCTAssertEqual(firstHour.weatherCode, 63)
        XCTAssertEqual(lastHour.date, firstHour.date.addingTimeInterval(5 * 3600))
    }

    func test_parse_multipleNights_separateKeys() {
        // 2夜分のデータが別キーに分かれる
        let t21a = makeTimeString(year: 2024, month: 6, day: 15, hour: 21)
        let t21b = makeTimeString(year: 2024, month: 6, day: 16, hour: 21)
        let result = service.parse(response: makeResponse(times: [t21a, t21b]), location: tokyoLocation, timeZone: tokyoTimeZone)
        XCTAssertEqual(result.count, 2)
        XCTAssertNotNil(result["2024-06-15"])
        XCTAssertNotNil(result["2024-06-16"])
    }

    func test_isForecastOutOfRange_returnsTrueOnlyAfterLatestForecastDay() {
        let baseDate = Calendar(identifier: .gregorian).date(from: DateComponents(
            timeZone: tokyoTimeZone,
            year: 2024,
            month: 6,
            day: 15,
            hour: 12
        ))!
        let weatherByDate = [
            service.dateKey(baseDate, timeZone: tokyoTimeZone): DayWeatherSummary(date: baseDate, nighttimeHours: []),
            service.dateKey(baseDate.addingTimeInterval(86_400), timeZone: tokyoTimeZone): DayWeatherSummary(
                date: baseDate.addingTimeInterval(86_400),
                nighttimeHours: []
            )
        ]

        XCTAssertFalse(service.isForecastOutOfRange(for: baseDate, in: weatherByDate, timeZone: tokyoTimeZone))
        XCTAssertFalse(
            service.isForecastOutOfRange(
                for: baseDate.addingTimeInterval(86_400),
                in: weatherByDate,
                timeZone: tokyoTimeZone
            )
        )
        XCTAssertTrue(
            service.isForecastOutOfRange(
                for: baseDate.addingTimeInterval(2 * 86_400),
                in: weatherByDate,
                timeZone: tokyoTimeZone
            )
        )
    }

    // MARK: - parse: nil 値のデフォルト処理

    func test_parse_missingCoreValues_excludesIncompleteHour() {
        let t21 = makeTimeString(year: 2024, month: 6, day: 15, hour: 21)
        let details = MetNorwayResponse.Properties.Timeseries.Data.Instant.Details(
            air_temperature: nil,
            cloud_area_fraction: nil,
            cloud_area_fraction_low: nil,
            cloud_area_fraction_medium: nil,
            cloud_area_fraction_high: nil,
            wind_speed: nil,
            wind_speed_of_gust: nil,
            relative_humidity: nil,
            dew_point_temperature: nil
        )
        let data = MetNorwayResponse.Properties.Timeseries.Data(
            instant: .init(details: details),
            next_1_hours: nil,
            next_6_hours: nil
        )
        let response = MetNorwayResponse(
            properties: .init(timeseries: [
                MetNorwayResponse.Properties.Timeseries(time: t21, data: data)
            ])
        )
        let result = service.parse(response: response, location: tokyoLocation, timeZone: tokyoTimeZone)
        XCTAssertTrue(result.isEmpty)
    }

    func test_parse_nilTemperature_dewpointFallsBackToTemp() {
        // dew_point_temperature が nil のとき air_temperature を使う
        let t21 = makeTimeString(year: 2024, month: 6, day: 15, hour: 21)
        let ts = makeTimeseries(time: t21, cloud: 0, temp: 15.0, dewpoint: 15.0)
        // dewpoint を nil にしたいので別途作る
        let details = MetNorwayResponse.Properties.Timeseries.Data.Instant.Details(
            air_temperature: 15.0,
            cloud_area_fraction: 0,
            cloud_area_fraction_low: nil,
            cloud_area_fraction_medium: nil,
            cloud_area_fraction_high: nil,
            wind_speed: 0,
            wind_speed_of_gust: nil,
            relative_humidity: 0,
            dew_point_temperature: nil  // nil → temp にフォールバック
        )
        let data = MetNorwayResponse.Properties.Timeseries.Data(
            instant: .init(details: details),
            next_1_hours: ts.data.next_1_hours,
            next_6_hours: nil
        )
        let response = MetNorwayResponse(
            properties: .init(timeseries: [
                MetNorwayResponse.Properties.Timeseries(time: t21, data: data)
            ])
        )
        let result = service.parse(response: response, location: tokyoLocation, timeZone: tokyoTimeZone)
        let hw = result["2024-06-15"]?.nighttimeHours.first
        XCTAssertEqual(hw?.dewpointCelsius, 15.0, "dewpoint nil のとき temperature (15.0) にフォールバックするはず")
    }

    // MARK: - parse: DayWeatherSummary の集計値

    func test_parse_cloudCover_averaged() {
        // 20% と 40% の2時間 → avgCloudCover = 30%
        let t21 = makeTimeString(year: 2024, month: 6, day: 15, hour: 21)
        let t22 = makeTimeString(year: 2024, month: 6, day: 15, hour: 22)
        let result = service.parse(
            response: makeResponse(times: [t21, t22], clouds: [20.0, 40.0]),
            location: tokyoLocation,
            timeZone: tokyoTimeZone
        )
        XCTAssertEqual(result["2024-06-15"]?.avgCloudCover ?? -1, 30.0, accuracy: 0.001)
    }

    func test_parse_nighttimeHours_sortedByDate() {
        // 逆順で渡しても nighttimeHours は date 昇順で返る
        let t22 = makeTimeString(year: 2024, month: 6, day: 15, hour: 22)
        let t21 = makeTimeString(year: 2024, month: 6, day: 15, hour: 21)
        let result = service.parse(response: makeResponse(times: [t22, t21]), location: tokyoLocation, timeZone: tokyoTimeZone)
        let hours = result["2024-06-15"]?.nighttimeHours
        XCTAssertEqual(hours?.count, 2)
        if let h = hours, h.count == 2 {
            XCTAssertLessThan(h[0].date, h[1].date, "nighttimeHours は date 昇順であるべき")
        }
    }

    // MARK: - fetchWeather

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func test_fetchWeather_setsMETHeadersAndStoresParsedWeather() async throws {
        let t21 = makeTimeString(year: 2024, month: 6, day: 15, hour: 21)
        let session = makeMockSession { request in
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "User-Agent"),
                "NightScope/1.0 github.com/nightscope/app"
            )
            XCTAssertNil(request.value(forHTTPHeaderField: "If-Modified-Since"))

            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Last-Modified": "Wed, 01 Jan 2025 00:00:00 GMT"]
            )!
            return (response, self.makePayload(times: [t21]))
        }

        let service = WeatherService(urlSession: session)
        await service.fetchWeather(latitude: 35.6762, longitude: 139.6503, timeZone: tokyoTimeZone)

        XCTAssertEqual(service.weatherByDate["2024-06-15"]?.nighttimeHours.count, 1)
        XCTAssertEqual(service.weatherByDate["2024-06-15"]?.avgCloudCover ?? -1, 0, accuracy: 0.001)
        XCTAssertNil(service.errorMessage)
    }

    func test_fetchWeather_304_keepsExistingWeatherData() async throws {
        let t21 = makeTimeString(year: 2024, month: 6, day: 15, hour: 21)
        var requestCount = 0
        let session = makeMockSession { request in
            requestCount += 1
            let url = try XCTUnwrap(request.url)

            if requestCount == 1 {
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Last-Modified": "Wed, 01 Jan 2025 00:00:00 GMT"]
                )!
                return (response, self.makePayload(times: [t21]))
            }

            XCTAssertNotNil(request.value(forHTTPHeaderField: "If-Modified-Since"))
            let response = HTTPURLResponse(
                url: url,
                statusCode: 304,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let service = WeatherService(urlSession: session)
        await service.fetchWeather(latitude: 35.6762, longitude: 139.6503, timeZone: tokyoTimeZone)
        let firstCloudCover = service.weatherByDate["2024-06-15"]?.avgCloudCover

        await service.fetchWeather(latitude: 35.6762, longitude: 139.6503, timeZone: tokyoTimeZone)

        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(service.weatherByDate["2024-06-15"]?.avgCloudCover, firstCloudCover)
    }

    func test_fetchWeather_differentLocation_doesNotReuseIfModifiedSince() async throws {
        let t21 = makeTimeString(year: 2024, month: 6, day: 15, hour: 21)
        var requestCount = 0
        let session = makeMockSession { request in
            requestCount += 1
            let url = try XCTUnwrap(request.url)

            if requestCount == 1 {
                XCTAssertNil(request.value(forHTTPHeaderField: "If-Modified-Since"))
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Last-Modified": "Wed, 01 Jan 2025 00:00:00 GMT"]
                )!
                return (response, self.makePayload(times: [t21], cloud: 15))
            }

            XCTAssertNil(request.value(forHTTPHeaderField: "If-Modified-Since"))
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Last-Modified": "Thu, 02 Jan 2025 00:00:00 GMT"]
            )!
            return (response, self.makePayload(times: [t21], cloud: 75))
        }

        let service = WeatherService(urlSession: session)
        await service.fetchWeather(latitude: 35.6762, longitude: 139.6503, timeZone: tokyoTimeZone)
        await service.fetchWeather(latitude: 34.6937, longitude: 135.5023, timeZone: tokyoTimeZone)

        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(service.weatherByDate["2024-06-15"]?.avgCloudCover ?? -1, 75, accuracy: 0.001)
    }

    func test_fetchWeather_differentCellCoordinatesUseDistinctCacheKeys() async throws {
        let t21 = makeTimeString(year: 2024, month: 6, day: 15, hour: 21)
        var requestCount = 0
        let session = makeMockSession { request in
            requestCount += 1
            let url = try XCTUnwrap(request.url)

            if requestCount == 1 {
                XCTAssertNil(request.value(forHTTPHeaderField: "If-Modified-Since"))
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Last-Modified": "Wed, 01 Jan 2025 00:00:00 GMT"]
                )!
                return (response, self.makePayload(times: [t21], cloud: 15))
            }

            XCTAssertNil(request.value(forHTTPHeaderField: "If-Modified-Since"))
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Last-Modified": "Thu, 02 Jan 2025 00:00:00 GMT"]
            )!
            return (response, self.makePayload(times: [t21], cloud: 65))
        }

        // Fix 4 後: 異なる1.1kmセル（0.01度超の差）に属する座標は別キー
        let service = WeatherService(urlSession: session)
        await service.fetchWeather(latitude: 35.676200, longitude: 139.650300, timeZone: tokyoTimeZone)
        await service.fetchWeather(latitude: 35.690000, longitude: 139.661000, timeZone: tokyoTimeZone)

        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(service.weatherByDate["2024-06-15"]?.avgCloudCover ?? -1, 65, accuracy: 0.001)
    }

    func test_fetchWeather_switchingLocationDuringInFlightRequest_keepsLatestWeather() async throws {
        let t21 = makeTimeString(year: 2024, month: 6, day: 15, hour: 21)
        var requestCount = 0
        let session = makeMockSession { request in
            requestCount += 1
            let url = try XCTUnwrap(request.url)

            if requestCount == 1 {
                Thread.sleep(forTimeInterval: 0.15)
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Last-Modified": "Wed, 01 Jan 2025 00:00:00 GMT"]
                )!
                return (response, self.makePayload(times: [t21], cloud: 15))
            }

            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Last-Modified": "Thu, 02 Jan 2025 00:00:00 GMT"]
            )!
            return (response, self.makePayload(times: [t21], cloud: 65))
        }

        let service = WeatherService(urlSession: session)
        let firstFetch = Task {
            await service.fetchWeather(latitude: 35.6762, longitude: 139.6503, timeZone: tokyoTimeZone)
        }

        try? await Task.sleep(nanoseconds: 20_000_000)
        await service.fetchWeather(latitude: 34.6937, longitude: 135.5023, timeZone: tokyoTimeZone)
        await firstFetch.value

        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(service.weatherByDate["2024-06-15"]?.avgCloudCover ?? -1, 65, accuracy: 0.001)
    }

    func test_fetchWeather_returningToPreviousLocation_304_restoresCachedWeatherForThatLocation() async throws {
        let t21 = makeTimeString(year: 2024, month: 6, day: 15, hour: 21)
        var requestCount = 0
        let session = makeMockSession { request in
            requestCount += 1
            let url = try XCTUnwrap(request.url)

            switch requestCount {
            case 1:
                XCTAssertTrue(url.absoluteString.contains("lat=35.6762"))
                XCTAssertNil(request.value(forHTTPHeaderField: "If-Modified-Since"))
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Last-Modified": "Wed, 01 Jan 2025 00:00:00 GMT"]
                )!
                return (response, self.makePayload(times: [t21], cloud: 15))
            case 2:
                XCTAssertTrue(url.absoluteString.contains("lat=34.6937"))
                XCTAssertNil(request.value(forHTTPHeaderField: "If-Modified-Since"))
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Last-Modified": "Thu, 02 Jan 2025 00:00:00 GMT"]
                )!
                return (response, self.makePayload(times: [t21], cloud: 75))
            case 3:
                XCTAssertTrue(url.absoluteString.contains("lat=35.6762"))
                XCTAssertNotNil(request.value(forHTTPHeaderField: "If-Modified-Since"))
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 304,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (response, Data())
            default:
                XCTFail("想定外のリクエスト回数: \(requestCount)")
                throw URLError(.badServerResponse)
            }
        }

        let service = WeatherService(urlSession: session)
        await service.fetchWeather(latitude: 35.6762, longitude: 139.6503, timeZone: tokyoTimeZone)
        XCTAssertEqual(service.weatherByDate["2024-06-15"]?.avgCloudCover ?? -1, 15, accuracy: 0.001)

        await service.fetchWeather(latitude: 34.6937, longitude: 135.5023, timeZone: tokyoTimeZone)
        XCTAssertEqual(service.weatherByDate["2024-06-15"]?.avgCloudCover ?? -1, 75, accuracy: 0.001)

        await service.fetchWeather(latitude: 35.6762, longitude: 139.6503, timeZone: tokyoTimeZone)

        XCTAssertEqual(requestCount, 3)
        XCTAssertEqual(service.weatherByDate["2024-06-15"]?.avgCloudCover ?? -1, 15, accuracy: 0.001)
    }

    func test_prepareForLocationChange_clearsDisplayedWeatherUntilRefreshCompletes() {
        service.weatherByDate = [
            "2024-06-15": DayWeatherSummary(
                date: Date(),
                nighttimeHours: [
                    HourlyWeather(
                        date: Date(),
                        temperatureCelsius: 12,
                        cloudCoverPercent: 40,
                        precipitationMM: 0,
                        windSpeedKmh: 5,
                        humidityPercent: 40,
                        dewpointCelsius: 5,
                        weatherCode: 0,
                        visibilityMeters: nil,
                        windGustsKmh: nil,
                        cloudCoverLowPercent: nil,
                        cloudCoverMidPercent: nil,
                        cloudCoverHighPercent: nil,
                        windSpeedKmh500hpa: nil
                    )
                ]
            )
        ]
        service.errorMessage = "stale"
        service.isLoading = true

        service.prepareForLocationChange(latitude: 34.6937, longitude: 135.5023, timeZone: tokyoTimeZone)

        XCTAssertTrue(service.weatherByDate.isEmpty)
        XCTAssertNil(service.errorMessage)
        XCTAssertFalse(service.isLoading)
    }

    // MARK: - symbolCodeToWMO

    func test_symbolCodeToWMO_clearsky() {
        XCTAssertEqual(WeatherService.symbolCodeToWMO("clearsky_night"), 0)
        XCTAssertEqual(WeatherService.symbolCodeToWMO("clearsky_day"), 0)
        XCTAssertEqual(WeatherService.symbolCodeToWMO("clearsky"), 0)
    }

    func test_symbolCodeToWMO_fair() {
        XCTAssertEqual(WeatherService.symbolCodeToWMO("fair_night"), 1)
    }

    func test_symbolCodeToWMO_partlycloudy() {
        XCTAssertEqual(WeatherService.symbolCodeToWMO("partlycloudy_day"), 2)
    }

    func test_symbolCodeToWMO_cloudy() {
        XCTAssertEqual(WeatherService.symbolCodeToWMO("cloudy"), 3)
    }

    func test_symbolCodeToWMO_rain() {
        XCTAssertEqual(WeatherService.symbolCodeToWMO("lightrain"), 61)
        XCTAssertEqual(WeatherService.symbolCodeToWMO("rain"), 63)
        XCTAssertEqual(WeatherService.symbolCodeToWMO("heavyrain"), 65)
    }

    func test_symbolCodeToWMO_snow() {
        XCTAssertEqual(WeatherService.symbolCodeToWMO("lightsnow"), 71)
        XCTAssertEqual(WeatherService.symbolCodeToWMO("snow"), 73)
        XCTAssertEqual(WeatherService.symbolCodeToWMO("heavysnow"), 75)
    }

    func test_symbolCodeToWMO_thunder() {
        XCTAssertEqual(WeatherService.symbolCodeToWMO("lightrainandthunder"), 95)
        XCTAssertEqual(WeatherService.symbolCodeToWMO("rainandthunder"), 95)
    }

    func test_symbolCodeToWMO_nil_returnsZero() {
        XCTAssertEqual(WeatherService.symbolCodeToWMO(nil), 0)
    }

    // MARK: - Bug fix: locationKey 粒度

    /// 同一の約11mセル内の2座標は同一 locationKey を返すこと（%.4f 粒度）。
    func test_fetchWeatherSnapshot_nearbyCoordinates_returnSameLocationKey() async {
        // 0.0001度 ≒ 11m。どちらも同一 4-decimal セルに丸め込まれる。
        let service1 = WeatherService(urlSession: makeNetworkErrorSession())
        let service2 = WeatherService(urlSession: makeNetworkErrorSession())
        let tz = tokyoTimeZone

        let result1 = await service1.fetchWeatherSnapshot(latitude: 35.676200, longitude: 139.650300, timeZone: tz)
        let result2 = await service2.fetchWeatherSnapshot(latitude: 35.676249, longitude: 139.650349, timeZone: tz)

        XCTAssertEqual(
            result1.locationKey,
            result2.locationKey,
            "同一の約11mセル内の座標は同一キーになるはず (%.4f 粒度)"
        )
    }

    /// 100m 単位で異なる検索地点は別の locationKey になること。
    func test_fetchWeatherSnapshot_nearbyDistinctCoordinates_returnDifferentLocationKeys() async {
        let service1 = WeatherService(urlSession: makeNetworkErrorSession())
        let service2 = WeatherService(urlSession: makeNetworkErrorSession())
        let tz = tokyoTimeZone

        let result1 = await service1.fetchWeatherSnapshot(latitude: 35.676200, longitude: 139.650300, timeZone: tz)
        let result2 = await service2.fetchWeatherSnapshot(latitude: 35.677400, longitude: 139.651500, timeZone: tz)

        XCTAssertNotEqual(
            result1.locationKey,
            result2.locationKey,
            "検索で選び直した近接地点は別キーとして扱うべき"
        )
    }

    /// 異なるセルに属する2座標が異なる locationKey を返すこと。
    func test_fetchWeatherSnapshot_distantCoordinates_returnDifferentLocationKeys() async {
        let service1 = WeatherService(urlSession: makeNetworkErrorSession())
        let service2 = WeatherService(urlSession: makeNetworkErrorSession())
        let tz = tokyoTimeZone

        // 4-decimal セルをまたぐ十分に離れた 2 点。
        let result1 = await service1.fetchWeatherSnapshot(latitude: 35.674, longitude: 139.651, timeZone: tz)
        let result2 = await service2.fetchWeatherSnapshot(latitude: 35.685, longitude: 139.661, timeZone: tz)

        XCTAssertNotEqual(result1.locationKey, result2.locationKey,
                          "異なるセルの座標は異なるキーになるはず")
    }

    /// 同一座標でもタイムゾーンが異なれば locationKey が異なること（日サマリーの区切り保護）。
    func test_fetchWeatherSnapshot_sameCoordinateDifferentTimeZone_returnDifferentLocationKeys() async {
        let service = WeatherService(urlSession: makeNetworkErrorSession())
        let tokyoTZ = tokyoTimeZone
        let utcTZ = TimeZone(identifier: "UTC")!
        let lat = 35.6762
        let lon = 139.6503

        let resultTokyo = await service.fetchWeatherSnapshot(latitude: lat, longitude: lon, timeZone: tokyoTZ)
        let resultUTC   = await service.fetchWeatherSnapshot(latitude: lat, longitude: lon, timeZone: utcTZ)

        XCTAssertNotEqual(resultTokyo.locationKey, resultUTC.locationKey,
                          "タイムゾーンが異なれば locationKey も異なるはず")
    }

    func test_fetchWeather_nearbyDistinctCoordinates_doNotReuseIfModifiedSince() async throws {
        let t21 = makeTimeString(year: 2024, month: 6, day: 15, hour: 21)
        var requestCount = 0
        let session = makeMockSession { request in
            requestCount += 1
            let url = try XCTUnwrap(request.url)

            if requestCount == 1 {
                XCTAssertNil(request.value(forHTTPHeaderField: "If-Modified-Since"))
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Last-Modified": "Wed, 01 Jan 2025 00:00:00 GMT"]
                )!
                return (response, self.makePayload(times: [t21], cloud: 15))
            }

            XCTAssertNil(request.value(forHTTPHeaderField: "If-Modified-Since"))
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Last-Modified": "Thu, 02 Jan 2025 00:00:00 GMT"]
            )!
            return (response, self.makePayload(times: [t21], cloud: 65))
        }

        let service = WeatherService(urlSession: session)
        await service.fetchWeather(latitude: 35.676200, longitude: 139.650300, timeZone: tokyoTimeZone)
        await service.fetchWeather(latitude: 35.677400, longitude: 139.651500, timeZone: tokyoTimeZone)

        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(service.weatherByDate["2024-06-15"]?.avgCloudCover ?? -1, 65, accuracy: 0.001)
    }

    /// 同一座標は常に同一 locationKey を返すこと。
    func test_fetchWeatherSnapshot_sameCoordinate_returnSameLocationKey() async {
        let service1 = WeatherService(urlSession: makeNetworkErrorSession())
        let service2 = WeatherService(urlSession: makeNetworkErrorSession())
        let tz = tokyoTimeZone

        let result1 = await service1.fetchWeatherSnapshot(latitude: 35.6762, longitude: 139.6503, timeZone: tz)
        let result2 = await service2.fetchWeatherSnapshot(latitude: 35.6762, longitude: 139.6503, timeZone: tz)

        XCTAssertEqual(result1.locationKey, result2.locationKey)
    }

    /// 境界値付近の座標でも locationKey が決定的（揺れない）こと。
    func test_fetchWeatherSnapshot_boundaryCoordinate_deterministicKey() async {
        let service1 = WeatherService(urlSession: makeNetworkErrorSession())
        let service2 = WeatherService(urlSession: makeNetworkErrorSession())
        let tz = tokyoTimeZone

        let result1 = await service1.fetchWeatherSnapshot(latitude: 35.005000, longitude: 139.005000, timeZone: tz)
        let result2 = await service2.fetchWeatherSnapshot(latitude: 35.005000, longitude: 139.005000, timeZone: tz)

        XCTAssertEqual(result1.locationKey, result2.locationKey,
                       "同一境界値座標は同一キーを返すはず")
    }

    /// makeNetworkErrorSession: ネットワーク呼び出しを即失敗させるセッション。
    /// FetchResult.locationKey はネットワーク結果に関わらず常に正しく設定される。
    private func makeNetworkErrorSession() -> URLSession {
        makeMockSession { _ in throw URLError(.notConnectedToInternet) }
    }

    private func makeMockSession(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        MockURLProtocol.requestHandler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makePayload(times: [String], cloud: Double = 0) -> Data {
        let entries = times.map { time in
            """
            {
              "time": "\(time)",
              "data": {
                "instant": {
                  "details": {
                    "air_temperature": 12,
                    "cloud_area_fraction": \(cloud),
                    "wind_speed": 1.5,
                    "relative_humidity": 40,
                    "dew_point_temperature": 5
                  }
                },
                "next_1_hours": {
                  "summary": { "symbol_code": "clearsky_night" },
                  "details": { "precipitation_amount": 0 }
                }
              }
            }
            """
        }.joined(separator: ",")

        return Data("""
        {
          "properties": {
            "timeseries": [\(entries)]
          }
        }
        """.utf8)
    }
}

final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
