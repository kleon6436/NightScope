import XCTest
import CoreLocation
@testable import NightScope

final class MilkyWayCalculatorTests: XCTestCase {
    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0,
        minute: Int = 0,
        timeZoneIdentifier: String
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.timeZone = TimeZone(identifier: timeZoneIdentifier)
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    // MARK: - julianDate

    /// J2000.0 エポック (2000-01-01 12:00:00 UTC) → JD = 2451545.0
    func test_julianDate_j2000Epoch() {
        var components = DateComponents()
        components.year = 2000
        components.month = 1
        components.day = 1
        components.hour = 12
        components.minute = 0
        components.second = 0
        components.timeZone = TimeZone(identifier: "UTC")
        let date = Calendar(identifier: .gregorian).date(from: components)!
        let jd = MilkyWayCalculator.julianDate(from: date)
        XCTAssertEqual(jd, 2451545.0, accuracy: 0.001)
    }

    // MARK: - greenwichSiderealTime

    /// J2000.0 では GST = 280.46061837° (式の定数項)
    func test_gst_j2000Epoch() {
        let gst = MilkyWayCalculator.greenwichSiderealTime(jd: 2451545.0)
        XCTAssertEqual(gst, 280.46061837, accuracy: 0.01)
    }

    // MARK: - localSiderealTime

    /// LST = (GST + 経度) mod 360
    func test_lst_tokyoLongitude() {
        let jd = 2451545.0
        let longitude = 139.6503 // 東京
        let lst = MilkyWayCalculator.localSiderealTime(jd: jd, longitude: longitude)
        let gst = MilkyWayCalculator.greenwichSiderealTime(jd: jd)
        var expected = (gst + longitude).truncatingRemainder(dividingBy: 360.0)
        if expected < 0 { expected += 360.0 }
        XCTAssertEqual(lst, expected, accuracy: 0.001)
    }

    // MARK: - altitude

    /// 天頂: HA=0°, dec=lat → altitude = 90°
    func test_altitude_zenith() {
        let latitude = 45.0
        let dec = 45.0
        let ra = 100.0
        let lst = ra // ha = lst - ra = 0
        let alt = MilkyWayCalculator.altitude(ra: ra, dec: dec, latitude: latitude, lst: lst)
        XCTAssertEqual(alt, 90.0, accuracy: 0.001)
    }

    /// 天底: HA=180°, dec=-lat → altitude = -90°
    func test_altitude_nadir() {
        let latitude = 45.0
        let dec = -45.0
        let ra = 0.0
        let lst = 180.0 // ha = 180°
        let alt = MilkyWayCalculator.altitude(ra: ra, dec: dec, latitude: latitude, lst: lst)
        XCTAssertEqual(alt, -90.0, accuracy: 0.001)
    }

    /// 赤道 (lat=0) で HA=90°, dec=0° → altitude = 0°（地平線上）
    func test_altitude_horizon_atEquator() {
        let latitude = 0.0
        let dec = 0.0
        let ra = 0.0
        let lst = 90.0 // ha = 90°
        let alt = MilkyWayCalculator.altitude(ra: ra, dec: dec, latitude: latitude, lst: lst)
        XCTAssertEqual(alt, 0.0, accuracy: 0.001)
    }

    // MARK: - viewingScore

    /// sunAltitude < -20 のとき darknessBonus = (|sunAlt| - 20) * 0.5
    func test_viewingScore_withDarknessBonus() {
        // sunAltitude=-30: darknessBonus = (30-20)*0.5 = 5
        let event = AstroEvent(
            date: Date(),
            galacticCenterAltitude: 20,
            galacticCenterAzimuth: 180,
            sunAltitude: -30,
            moonAltitude: -10,
            moonPhase: 0.1
        )
        let score = MilkyWayCalculator.viewingScore(event)
        XCTAssertEqual(score, 25.0, accuracy: 0.001)
    }

    /// sunAltitude >= -20 のとき darknessBonus = 0
    func test_viewingScore_noBonusWhenNotFullyDark() {
        // sunAltitude=-15: darknessBonus = max(0, -5)*0.5 = 0
        let event = AstroEvent(
            date: Date(),
            galacticCenterAltitude: 20,
            galacticCenterAzimuth: 180,
            sunAltitude: -15,
            moonAltitude: -10,
            moonPhase: 0.1
        )
        let score = MilkyWayCalculator.viewingScore(event)
        XCTAssertEqual(score, 20.0, accuracy: 0.001)
    }

    // MARK: - mergeNearbyWindows

    /// ウィンドウが1つなら変化しない
    func test_mergeNearbyWindows_single_unchanged() {
        let t0 = Date(timeIntervalSince1970: 0)
        let t1 = Date(timeIntervalSince1970: 3600)
        let w = ViewingWindow(start: t0, end: t1, peakTime: t0, peakAltitude: 30, peakAzimuth: 180)
        let result = MilkyWayCalculator.mergeNearbyWindows([w])
        XCTAssertEqual(result.count, 1)
    }

    /// ギャップが閾値以内 (< 30分) ならマージ
    func test_mergeNearbyWindows_gapWithinThreshold_merged() {
        let t0 = Date(timeIntervalSince1970: 0)
        let t1 = Date(timeIntervalSince1970: 3600)
        let t2 = Date(timeIntervalSince1970: 3600 + 1799) // gap = 29分59秒
        let t3 = Date(timeIntervalSince1970: 7200)
        let w1 = ViewingWindow(start: t0, end: t1, peakTime: t0, peakAltitude: 30, peakAzimuth: 180)
        let w2 = ViewingWindow(start: t2, end: t3, peakTime: t2, peakAltitude: 20, peakAzimuth: 190)
        let result = MilkyWayCalculator.mergeNearbyWindows([w1, w2])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].start, t0)
        XCTAssertEqual(result[0].end, t3)
        XCTAssertEqual(result[0].peakAltitude, 30.0) // より高い高度が採用される
    }

    /// ギャップが閾値超 (> 30分) ならマージしない
    func test_mergeNearbyWindows_gapExceedsThreshold_notMerged() {
        let t0 = Date(timeIntervalSince1970: 0)
        let t1 = Date(timeIntervalSince1970: 3600)
        let t2 = Date(timeIntervalSince1970: 3600 + 1801) // gap = 30分1秒
        let t3 = Date(timeIntervalSince1970: 7200)
        let w1 = ViewingWindow(start: t0, end: t1, peakTime: t0, peakAltitude: 30, peakAzimuth: 180)
        let w2 = ViewingWindow(start: t2, end: t3, peakTime: t2, peakAltitude: 20, peakAzimuth: 190)
        let result = MilkyWayCalculator.mergeNearbyWindows([w1, w2])
        XCTAssertEqual(result.count, 2)
    }

    /// ギャップがちょうど30分ならマージ (gapThreshold = 30 * 60 は `<=` 比較)
    func test_mergeNearbyWindows_exactThresholdGap_merged() {
        let t0 = Date(timeIntervalSince1970: 0)
        let t1 = Date(timeIntervalSince1970: 3600)
        let t2 = Date(timeIntervalSince1970: 3600 + 1800) // gap = ちょうど30分
        let t3 = Date(timeIntervalSince1970: 7200)
        let w1 = ViewingWindow(start: t0, end: t1, peakTime: t0, peakAltitude: 30, peakAzimuth: 180)
        let w2 = ViewingWindow(start: t2, end: t3, peakTime: t2, peakAltitude: 20, peakAzimuth: 190)
        let result = MilkyWayCalculator.mergeNearbyWindows([w1, w2])
        XCTAssertEqual(result.count, 1)
    }

    // MARK: - findViewingWindows

    /// galacticCenterVisible が連続するイベントは1つのウィンドウにまとまる
    func test_findViewingWindows_continuousVisible_singleWindow() {
        let base = Date(timeIntervalSince1970: 0)
        // galacticCenterVisible: altitude > 10° && isDark (sunAlt < -18°)
        // 高度15°を使用 (大気差・地物遮蔽を考慮した実用最低高度10°を上回る)
        let events = (0..<4).map { i in
            AstroEvent(
                date: base.addingTimeInterval(Double(i) * 900),
                galacticCenterAltitude: 15.0,
                galacticCenterAzimuth: 180.0,
                sunAltitude: -20.0,
                moonAltitude: -5.0,
                moonPhase: 0.1
            )
        }
        let windows = MilkyWayCalculator.findViewingWindows(events: events)
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].start, base)
        XCTAssertEqual(
            windows[0].end,
            base.addingTimeInterval(4 * MilkyWayCalculator.Constants.sampleIntervalSeconds)
        )
        XCTAssertEqual(
            windows[0].duration,
            4 * MilkyWayCalculator.Constants.sampleIntervalSeconds,
            accuracy: 0.001
        )
    }

    /// galacticCenterVisible なイベントが0件なら空リスト
    func test_findViewingWindows_noVisible_empty() {
        let base = Date(timeIntervalSince1970: 0)
        // sunAlt = -10 → isDark = false → galacticCenterVisible = false
        let events = (0..<4).map { i in
            AstroEvent(
                date: base.addingTimeInterval(Double(i) * 900),
                galacticCenterAltitude: 10.0,
                galacticCenterAzimuth: 180.0,
                sunAltitude: -10.0,
                moonAltitude: -5.0,
                moonPhase: 0.1
            )
        }
        let windows = MilkyWayCalculator.findViewingWindows(events: events)
        XCTAssertTrue(windows.isEmpty)
    }

    /// 連続する N サンプルのウィンドウ duration は N × sampleInterval になる
    func test_findViewingWindows_windowDurationEqualsNTimesSampleInterval() {
        let base = Date(timeIntervalSince1970: 0)
        let interval = Double(MilkyWayCalculator.Constants.sampleIntervalMinutes) * 60  // 900s
        // 4 サンプル (t=0, 900, 1800, 2700) が可視
        let events = (0..<4).map { i in
            AstroEvent(
                date: base.addingTimeInterval(Double(i) * interval),
                galacticCenterAltitude: 15.0,
                galacticCenterAzimuth: 180.0,
                sunAltitude: -20.0,
                moonAltitude: -5.0,
                moonPhase: 0.1
            )
        }
        let windows = MilkyWayCalculator.findViewingWindows(events: events)
        XCTAssertEqual(windows.count, 1)
        // start = t=0, end = t=2700 + 900 = 3600
        XCTAssertEqual(windows[0].start, base)
        XCTAssertEqual(windows[0].end,   base.addingTimeInterval(interval * 4))
        XCTAssertEqual(windows[0].duration, interval * 4, accuracy: 0.001)
    }

    /// 単一サンプルのウィンドウ duration は sampleInterval と等しい
    func test_findViewingWindows_singleSampleWindow_durationEqualsSampleInterval() {
        let base = Date(timeIntervalSince1970: 0)
        let interval = Double(MilkyWayCalculator.Constants.sampleIntervalMinutes) * 60
        let events = [
            AstroEvent(
                date: base,
                galacticCenterAltitude: 15.0,
                galacticCenterAzimuth: 180.0,
                sunAltitude: -20.0,
                moonAltitude: -5.0,
                moonPhase: 0.1
            )
        ]
        let windows = MilkyWayCalculator.findViewingWindows(events: events)
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].duration, interval, accuracy: 0.001)
    }

    func test_calculateNightSummary_usesNextLocalMidnightAcrossDstBoundary() {
        let timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let date = makeDate(year: 2024, month: 11, day: 3, timeZoneIdentifier: timeZone.identifier)
        let location = CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437)
        let calendar = ObservationTimeZone.gregorianCalendar(timeZone: timeZone)
        let nextMidnight = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: date)
        )!
        let expectedPhase = MilkyWayCalculator.moonRaDec(
            jd: MilkyWayCalculator.julianDate(from: nextMidnight)
        ).phase

        let summary = MilkyWayCalculator.calculateNightSummary(
            date: date,
            location: location,
            timeZone: timeZone
        )

        XCTAssertEqual(summary.moonPhaseAtMidnight, expectedPhase, accuracy: 1e-9)
    }

    func test_calculateNightSummary_eventsCoverNextMorningForObservationNight() {
        let timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let date = makeDate(year: 2026, month: 4, day: 2, timeZoneIdentifier: timeZone.identifier)
        let location = CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)
        let calendar = ObservationTimeZone.gregorianCalendar(timeZone: timeZone)

        let summary = MilkyWayCalculator.calculateNightSummary(
            date: date,
            location: location,
            timeZone: timeZone
        )

        XCTAssertEqual(calendar.component(.hour, from: summary.events.first?.date ?? date), 12)
        XCTAssertEqual(calendar.component(.day, from: summary.events.last?.date ?? date), 3)
        XCTAssertEqual(calendar.component(.hour, from: summary.events.last?.date ?? date), 11)
    }

    func test_civilDarknessInterval_returnsFullObservationWindowDuringPolarNight() throws {
        let timeZone = TimeZone(identifier: "Europe/Oslo")!
        let date = makeDate(year: 2026, month: 12, day: 21, timeZoneIdentifier: timeZone.identifier)
        let location = CLLocationCoordinate2D(latitude: 78.2232, longitude: 15.6469)

        let interval = try XCTUnwrap(
            MilkyWayCalculator.civilDarknessInterval(
                date: date,
                location: location,
                timeZone: timeZone
            )
        )
        let calendar = ObservationTimeZone.gregorianCalendar(timeZone: timeZone)
        let components = calendar.dateComponents([.hour, .minute], from: interval.start)

        XCTAssertEqual(components.hour, 12)
        XCTAssertEqual(components.minute, 0)
        XCTAssertEqual(interval.duration, 86_400, accuracy: 60)
    }

    func test_civilDarknessInterval_returnsNilDuringMidnightSun() {
        let timeZone = TimeZone(identifier: "Europe/Oslo")!
        let date = makeDate(year: 2026, month: 6, day: 21, timeZoneIdentifier: timeZone.identifier)
        let location = CLLocationCoordinate2D(latitude: 78.2232, longitude: 15.6469)

        let interval = MilkyWayCalculator.civilDarknessInterval(
            date: date,
            location: location,
            timeZone: timeZone
        )

        XCTAssertNil(interval)
    }

    // MARK: - galacticToEquatorial

    /// 銀河中心 (l=0, b=0) → RA≈266.4°, Dec≈-29.0° に近似一致する
    func test_galacticToEquatorial_galacticCenter() {
        let result = MilkyWayCalculator.galacticToEquatorial(l: 0, b: 0)
        XCTAssertEqual(result.ra,  266.4, accuracy: 3.0, "銀河中心 RA")
        XCTAssertEqual(result.dec, -29.0, accuracy: 3.0, "銀河中心 Dec")
    }

    /// 北銀極 (l=任意, b=90) → Dec ≈ 27.1° (銀河北極の赤緯)
    func test_galacticToEquatorial_northGalacticPole() {
        let result = MilkyWayCalculator.galacticToEquatorial(l: 0, b: 90)
        XCTAssertEqual(result.dec, 27.1, accuracy: 3.0, "北銀極 Dec")
    }

    /// 出力 RA が常に [0, 360) 範囲に収まる
    func test_galacticToEquatorial_raInRange() {
        for l in stride(from: 0.0, through: 360.0, by: 30.0) {
            for b in [-30.0, 0.0, 30.0] {
                let result = MilkyWayCalculator.galacticToEquatorial(l: l, b: b)
                XCTAssertGreaterThanOrEqual(result.ra, 0.0,   "l=\(l) b=\(b): RA < 0")
                XCTAssertLessThan(          result.ra, 360.0, "l=\(l) b=\(b): RA >= 360")
                XCTAssertGreaterThanOrEqual(result.dec, -90.0, "l=\(l) b=\(b): Dec < -90")
                XCTAssertLessThanOrEqual(   result.dec,  90.0, "l=\(l) b=\(b): Dec > 90")
            }
        }
    }
}
