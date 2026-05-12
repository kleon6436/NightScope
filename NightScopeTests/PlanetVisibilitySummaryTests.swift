import XCTest
import CoreLocation
@testable import NightScope

final class PlanetVisibilitySummaryTests: XCTestCase {

    // MARK: - Helpers

    private let tokyo = CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)
    private let tokyoTZ = TimeZone(identifier: "Asia/Tokyo")!

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0,
        minute: Int = 0,
        timeZoneIdentifier: String
    ) -> Date {
        var components = DateComponents()
        components.year  = year
        components.month = month
        components.day   = day
        components.hour  = hour
        components.minute = minute
        components.timeZone = TimeZone(identifier: timeZoneIdentifier)
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    // MARK: - planetNightSummaries returns 5 entries

    /// 結果は 5 惑星すべてを含む。
    func test_planetNightSummaries_returnsFivePlanets() {
        let date = makeDate(year: 2025, month: 6, day: 21, timeZoneIdentifier: "Asia/Tokyo")
        let summaries = MilkyWayCalculator.planetNightSummaries(
            date: date,
            location: tokyo,
            timeZone: tokyoTZ
        )
        XCTAssertEqual(summaries.count, 5)
    }

    // MARK: - Result is sorted in canonical order

    /// 返り値が 水星/金星/火星/木星/土星 の順に並ぶ。
    func test_planetNightSummaries_sortedInCanonicalOrder() {
        let expected = ["水星", "金星", "火星", "木星", "土星"]
        let date = makeDate(year: 2025, month: 6, day: 21, timeZoneIdentifier: "Asia/Tokyo")
        let names = MilkyWayCalculator.planetNightSummaries(
            date: date,
            location: tokyo,
            timeZone: tokyoTZ
        ).map(\.name)
        XCTAssertEqual(names, expected)
    }

    // MARK: - Rise/set times fall within the night window

    /// riseTime・setTime が取得できる場合、夜間窓（18:00〜翌 06:00）に収まる。
    func test_planetNightSummaries_riseSetTimesWithinNightWindow() {
        let date = makeDate(year: 2025, month: 6, day: 21, timeZoneIdentifier: "Asia/Tokyo")
        let cal = ObservationTimeZone.gregorianCalendar(timeZone: tokyoTZ)
        let startOfDay = cal.startOfDay(for: date)
        let nightStart = cal.date(byAdding: .hour, value: 18, to: startOfDay)!
        let nextDay    = cal.date(byAdding: .day,  value: 1,  to: startOfDay)!
        let nightEnd   = cal.date(byAdding: .hour, value: 6,  to: nextDay)!

        let summaries = MilkyWayCalculator.planetNightSummaries(
            date: date,
            location: tokyo,
            timeZone: tokyoTZ
        )
        for s in summaries {
            if let rise = s.riseTime {
                XCTAssertGreaterThanOrEqual(rise, nightStart - 60,
                    "\(s.name) riseTime \(rise) is before nightStart")
                XCTAssertLessThanOrEqual(rise, nightEnd + 60,
                    "\(s.name) riseTime \(rise) is after nightEnd")
            }
            if let set = s.setTime {
                XCTAssertGreaterThanOrEqual(set, nightStart - 60,
                    "\(s.name) setTime \(set) is before nightStart")
                XCTAssertLessThanOrEqual(set, nightEnd + 60,
                    "\(s.name) setTime \(set) is after nightEnd")
            }
        }
    }

    // MARK: - isVisibleTonight reflects altitude correctly

    /// peakAltitude >= 5 の惑星は isVisibleTonight == true。
    func test_isVisibleTonight_trueWhenAboveHorizon() {
        let date = makeDate(year: 2025, month: 6, day: 21, timeZoneIdentifier: "Asia/Tokyo")
        let summaries = MilkyWayCalculator.planetNightSummaries(
            date: date,
            location: tokyo,
            timeZone: tokyoTZ
        )
        for s in summaries {
            if s.peakAltitude > 10.0 {
                XCTAssertTrue(s.isVisibleTonight,
                    "\(s.name) should be visible (peakAlt=\(s.peakAltitude))")
            } else {
                XCTAssertFalse(s.isVisibleTonight,
                    "\(s.name) should not be visible (peakAlt=\(s.peakAltitude))")
            }
        }
    }

    // MARK: - Result changes with location

    /// 異なる緯度の地点では peakAltitude が変化する（同一日付）。
    func test_planetNightSummaries_differsWithLocation() {
        let date = makeDate(year: 2025, month: 6, day: 21, timeZoneIdentifier: "Asia/Tokyo")
        let tokyoResults = MilkyWayCalculator.planetNightSummaries(
            date: date,
            location: tokyo,
            timeZone: tokyoTZ
        )
        // 北緯 60 度の地点（ヘルシンキ付近）
        let helsinki = CLLocationCoordinate2D(latitude: 60.1699, longitude: 24.9384)
        let utcTZ    = TimeZone(identifier: "UTC")!
        let helsinkiResults = MilkyWayCalculator.planetNightSummaries(
            date: date,
            location: helsinki,
            timeZone: utcTZ
        )
        XCTAssertEqual(helsinkiResults.count, 5)
        // 両地点で全惑星の高度が同一になることはない
        let allSame = zip(tokyoResults, helsinkiResults).allSatisfy {
            $0.peakAltitude == $1.peakAltitude
        }
        XCTAssertFalse(allSame, "Peak altitudes should differ between Tokyo and Helsinki")
    }

    // MARK: - localizedName is non-empty for all planets

    /// すべての惑星の localizedName が空文字でない。
    func test_planetNightSummaries_localizedNameNonEmpty() {
        let date = makeDate(year: 2025, month: 9, day: 15, timeZoneIdentifier: "Asia/Tokyo")
        let summaries = MilkyWayCalculator.planetNightSummaries(
            date: date,
            location: tokyo,
            timeZone: tokyoTZ
        )
        for s in summaries {
            XCTAssertFalse(s.localizedName.isEmpty,
                "\(s.name) localizedName must not be empty")
        }
    }

    // MARK: - Azimuth range

    /// 方位角がすべて 0–360° の範囲内に収まる。
    func test_planetNightSummaries_azimuthInRange() {
        let date = makeDate(year: 2025, month: 6, day: 21, timeZoneIdentifier: "Asia/Tokyo")
        let summaries = MilkyWayCalculator.planetNightSummaries(
            date: date,
            location: tokyo,
            timeZone: tokyoTZ
        )
        for s in summaries {
            if let az = s.transitAzimuth {
                XCTAssertGreaterThanOrEqual(az, 0,   "\(s.name) transitAzimuth < 0")
                XCTAssertLessThan(az, 360,           "\(s.name) transitAzimuth >= 360")
            }
            if let az = s.riseAzimuth {
                XCTAssertGreaterThanOrEqual(az, 0,  "\(s.name) riseAzimuth < 0")
                XCTAssertLessThan(az, 360,          "\(s.name) riseAzimuth >= 360")
            }
            if let az = s.setAzimuth {
                XCTAssertGreaterThanOrEqual(az, 0,  "\(s.name) setAzimuth < 0")
                XCTAssertLessThan(az, 360,          "\(s.name) setAzimuth >= 360")
            }
        }
    }

    // MARK: - interpolateAzimuth

    /// 0°/360° 跨ぎの補間: 350° と 10° の中点 = 0° 付近。
    func test_interpolateAzimuth_crossingZero() {
        let result = MilkyWayCalculator.interpolateAzimuth(350, 10, frac: 0.5)
        // 短弧補間: delta = 10-350 = -340 → wrapped = 20 → midpoint = 350 + 10 = 360 → 0
        XCTAssertEqual(result, 0, accuracy: 1, "Expected ~0° for midpoint of 350° and 10°")
    }

    /// 通常ケース（跨ぎなし）: 10° と 50° の中点 = 30°。
    func test_interpolateAzimuth_normalCase() {
        let result = MilkyWayCalculator.interpolateAzimuth(10, 50, frac: 0.5)
        XCTAssertEqual(result, 30, accuracy: 1e-9)
    }

    // MARK: - altitudeSamples count

    /// altitudeSamples は 47–51 点（18:00–06:00 を 15 分刻みの 49 サンプル ± 2 許容）。
    func test_planetNightSummaries_altitudeSamplesCount() {
        let date = makeDate(year: 2025, month: 6, day: 21, timeZoneIdentifier: "Asia/Tokyo")
        let summaries = MilkyWayCalculator.planetNightSummaries(
            date: date,
            location: tokyo,
            timeZone: tokyoTZ
        )
        for s in summaries {
            XCTAssertGreaterThanOrEqual(s.altitudeSamples.count, 47,
                "\(s.name) altitudeSamples.count \(s.altitudeSamples.count) < 47")
            XCTAssertLessThanOrEqual(s.altitudeSamples.count, 51,
                "\(s.name) altitudeSamples.count \(s.altitudeSamples.count) > 51")
        }
    }

    // MARK: - Rise nil implies riseAzimuth nil

    /// riseTime が nil の惑星は riseAzimuth も nil。
    func test_planetNightSummaries_noRiseNilAzimuth() {
        // 全惑星を検査して「riseTime が nil なら riseAzimuth も nil」の不変条件を確認する
        let date = makeDate(year: 2025, month: 6, day: 21, timeZoneIdentifier: "Asia/Tokyo")
        let summaries = MilkyWayCalculator.planetNightSummaries(
            date: date,
            location: tokyo,
            timeZone: tokyoTZ
        )
        for s in summaries where s.riseTime == nil {
            XCTAssertNil(s.riseAzimuth, "\(s.name): riseTime is nil but riseAzimuth is not nil")
        }
        for s in summaries where s.setTime == nil {
            XCTAssertNil(s.setAzimuth, "\(s.name): setTime is nil but setAzimuth is not nil")
        }
    }

    // MARK: - Azimuth label formatting

    /// riseAzimuth / transitAzimuth / setAzimuth が nil のとき各ラベルは "—"。
    func test_riseAzimuthLabel_nilReturnsPlaceholder() {
        let s = PlanetNightSummary(
            name: "火星", riseTime: nil, transitTime: nil, setTime: nil,
            peakAltitude: 5.0, magnitude: 1.0,
            riseAzimuth: nil, transitAzimuth: nil, setAzimuth: nil
        )
        XCTAssertEqual(s.riseAzimuthLabel(), "—")
        XCTAssertEqual(s.transitAzimuthLabel(), "—")
        XCTAssertEqual(s.setAzimuthLabel(), "—")
    }

    /// riseAzimuth が非 nil のとき riseAzimuthLabel() は度数と方位名を含む。
    func test_riseAzimuthLabel_nonNilContainsDegrees() {
        let s = PlanetNightSummary(
            name: "木星", riseTime: nil, transitTime: nil, setTime: nil,
            peakAltitude: 30.0, magnitude: -2.0,
            riseAzimuth: 90.0, transitAzimuth: 180.0, setAzimuth: 270.0
        )
        // 90° = 東
        XCTAssertTrue(s.riseAzimuthLabel().contains("90"), "Label should contain degree value")
        XCTAssertFalse(s.riseAzimuthLabel() == "—", "Non-nil azimuth should not return placeholder")
        // 180° = 南
        XCTAssertTrue(s.transitAzimuthLabel().contains("180"))
        // 270° = 西
        XCTAssertTrue(s.setAzimuthLabel().contains("270"))
    }
}
