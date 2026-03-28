import XCTest
@testable import NightScope

final class MilkyWayCalculatorTests: XCTestCase {

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
        // galacticCenterVisible: altitude > 5° && isDark (sunAlt < -18°)
        let events = (0..<4).map { i in
            AstroEvent(
                date: base.addingTimeInterval(Double(i) * 900),
                galacticCenterAltitude: 10.0,
                galacticCenterAzimuth: 180.0,
                sunAltitude: -20.0,
                moonAltitude: -5.0,
                moonPhase: 0.1
            )
        }
        let windows = MilkyWayCalculator.findViewingWindows(events: events)
        XCTAssertEqual(windows.count, 1)
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
}
