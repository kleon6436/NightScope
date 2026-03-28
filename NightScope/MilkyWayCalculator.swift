import Foundation
import CoreLocation

// MARK: - Calculator

enum MilkyWayCalculator {
    // 銀河系中心の赤経・赤緯 (J2000.0)
    // RA: 17h 45m 40.04s = 266.41683°, Dec: -29° 00' 28.1" = -29.00781°
    static let gcRA: Double = 266.41683
    static let gcDec: Double = -29.00781

    // ユリウス日の計算
    static func julianDate(from date: Date) -> Double {
        return date.timeIntervalSince1970 / 86400.0 + 2440587.5
    }

    // グリニッジ恒星時 (度)
    static func greenwichSiderealTime(jd: Double) -> Double {
        let T = (jd - 2451545.0) / 36525.0
        var gst = 280.46061837
            + 360.98564736629 * (jd - 2451545.0)
            + 0.000387933 * T * T
            - T * T * T / 38710000.0
        gst = gst.truncatingRemainder(dividingBy: 360.0)
        return gst < 0 ? gst + 360.0 : gst
    }

    // 地方恒星時 (度)
    static func localSiderealTime(jd: Double, longitude: Double) -> Double {
        var lst = greenwichSiderealTime(jd: jd) + longitude
        lst = lst.truncatingRemainder(dividingBy: 360.0)
        return lst < 0 ? lst + 360.0 : lst
    }

    // 赤経・赤緯から高度を計算 (度)
    static func altitude(ra: Double, dec: Double, latitude: Double, lst: Double) -> Double {
        var ha = lst - ra
        ha = ha.truncatingRemainder(dividingBy: 360.0)

        let haRad = ha * .pi / 180.0
        let decRad = dec * .pi / 180.0
        let latRad = latitude * .pi / 180.0

        let sinAlt = sin(latRad) * sin(decRad) + cos(latRad) * cos(decRad) * cos(haRad)
        return asin(max(-1, min(1, sinAlt))) * 180.0 / .pi
    }

    // 赤経・赤緯から方位角を計算 (北=0°, 時計回り)
    static func azimuth(ra: Double, dec: Double, latitude: Double, lst: Double) -> Double {
        var ha = lst - ra
        ha = ha.truncatingRemainder(dividingBy: 360.0)

        let haRad = ha * .pi / 180.0
        let decRad = dec * .pi / 180.0
        let latRad = latitude * .pi / 180.0

        let sinAlt = sin(latRad) * sin(decRad) + cos(latRad) * cos(decRad) * cos(haRad)
        let altRad = asin(max(-1, min(1, sinAlt)))

        let cosAlt = cos(altRad)
        guard cosAlt > 1e-10 else { return 0.0 }

        let sinA = -sin(haRad) * cos(decRad) / cosAlt
        let cosA = (sin(decRad) - sin(latRad) * sin(altRad)) / (cos(latRad) * cosAlt)
        var az = atan2(sinA, cosA) * 180.0 / .pi
        if az < 0 { az += 360.0 }
        return az
    }

    // 太陽の赤経・赤緯 (簡易計算)
    static func sunRaDec(jd: Double) -> (ra: Double, dec: Double) {
        let n = jd - 2451545.0
        var L = 280.460 + 0.9856474 * n
        let g = (357.528 + 0.9856003 * n) * .pi / 180.0
        L = L.truncatingRemainder(dividingBy: 360.0)

        let lambdaRad = (L + 1.915 * sin(g) + 0.020 * sin(2 * g)) * .pi / 180.0
        let epsilonRad = 23.439 * .pi / 180.0

        let dec = asin(sin(epsilonRad) * sin(lambdaRad)) * 180.0 / .pi
        var ra = atan2(cos(epsilonRad) * sin(lambdaRad), cos(lambdaRad)) * 180.0 / .pi
        if ra < 0 { ra += 360.0 }
        return (ra, dec)
    }

    // 月の赤経・赤緯・位相 (簡易計算)
    static func moonRaDec(jd: Double) -> (ra: Double, dec: Double, phase: Double) {
        let d = jd - 2451545.0

        // 月の平均要素
        let L = (218.316 + 13.176396 * d).truncatingRemainder(dividingBy: 360.0)
        let M = (134.963 + 13.064993 * d) * .pi / 180.0
        let F = (93.272 + 13.229350 * d) * .pi / 180.0

        let lambdaRad = (L + 6.289 * sin(M)) * .pi / 180.0
        let betaRad = (5.128 * sin(F)) * .pi / 180.0

        let epsilonRad = 23.439 * .pi / 180.0

        let decRad = asin(max(-1, min(1, sin(betaRad) * cos(epsilonRad) + cos(betaRad) * sin(epsilonRad) * sin(lambdaRad))))
        let dec = decRad * 180.0 / .pi
        var ra = atan2(sin(lambdaRad) * cos(epsilonRad) - tan(betaRad) * sin(epsilonRad), cos(lambdaRad)) * 180.0 / .pi
        if ra < 0 { ra += 360.0 }

        // 太陽の黄経 (近似)
        let n = jd - 2451545.0
        let sunLambdaRad = (280.460 + 0.9856474 * n + 1.915 * sin((357.528 + 0.9856003 * n) * .pi / 180.0)) * .pi / 180.0
        var elongation = lambdaRad * 180 / .pi - sunLambdaRad * 180 / .pi
        elongation = elongation.truncatingRemainder(dividingBy: 360.0)
        if elongation < 0 { elongation += 360.0 }
        let phase = elongation / 360.0

        return (ra, dec, phase)
    }

    // 指定した日付・場所で15分おきにイベントを計算
    static func calculateEvents(date: Date, location: CLLocationCoordinate2D) -> [AstroEvent] {
        var events: [AstroEvent] = []
        let cal = Calendar(identifier: .gregorian)
        let startOfDay = cal.startOfDay(for: date)

        for minutes in stride(from: 0, to: 24 * 60, by: 15) {
            let sampleDate = startOfDay.addingTimeInterval(Double(minutes) * 60)
            let jd = julianDate(from: sampleDate)
            let lst = localSiderealTime(jd: jd, longitude: location.longitude)

            let gcAlt = altitude(ra: gcRA, dec: gcDec, latitude: location.latitude, lst: lst)
            let gcAz = azimuth(ra: gcRA, dec: gcDec, latitude: location.latitude, lst: lst)

            let sun = sunRaDec(jd: jd)
            let sunAlt = altitude(ra: sun.ra, dec: sun.dec, latitude: location.latitude, lst: lst)

            let moon = moonRaDec(jd: jd)
            let moonAlt = altitude(ra: moon.ra, dec: moon.dec, latitude: location.latitude, lst: lst)

            events.append(AstroEvent(
                date: sampleDate,
                galacticCenterAltitude: gcAlt,
                galacticCenterAzimuth: gcAz,
                sunAltitude: sunAlt,
                moonAltitude: moonAlt,
                moonPhase: moon.phase
            ))
        }
        return events
    }

    // 高度と空の暗さを組み合わせた観測スコア
    // 高度が高いほど・太陽が地平線から遠いほど高スコア
    static func viewingScore(_ event: AstroEvent) -> Double {
        let darknessBonus = max(0, -event.sunAltitude - 20.0) * 0.5
        return event.galacticCenterAltitude + darknessBonus
    }

    // 可視ウィンドウを検出
    static func findViewingWindows(events: [AstroEvent]) -> [ViewingWindow] {
        var windows: [ViewingWindow] = []
        var windowStart: Date? = nil
        var windowSamples: [AstroEvent] = []

        for event in events {
            if event.galacticCenterVisible {
                if windowStart == nil { windowStart = event.date }
                windowSamples.append(event)
            } else if let start = windowStart {
                if !windowSamples.isEmpty {
                    let bestAlt = windowSamples.max(by: { $0.galacticCenterAltitude < $1.galacticCenterAltitude })!
                    let bestViewing = windowSamples.max(by: { viewingScore($0) < viewingScore($1) })!
                    windows.append(ViewingWindow(
                        start: start,
                        end: windowSamples.last!.date,
                        peakTime: bestViewing.date,
                        peakAltitude: bestAlt.galacticCenterAltitude,
                        peakAzimuth: bestViewing.galacticCenterAzimuth
                    ))
                }
                windowStart = nil
                windowSamples = []
            }
        }

        if let start = windowStart, !windowSamples.isEmpty {
            let bestAlt = windowSamples.max(by: { $0.galacticCenterAltitude < $1.galacticCenterAltitude })!
            let bestViewing = windowSamples.max(by: { viewingScore($0) < viewingScore($1) })!
            windows.append(ViewingWindow(
                start: start,
                end: windowSamples.last!.date,
                peakTime: bestViewing.date,
                peakAltitude: bestAlt.galacticCenterAltitude,
                peakAzimuth: bestViewing.galacticCenterAzimuth
            ))
        }

        return mergeNearbyWindows(windows)
    }

    // 近接ウィンドウをマージ (ギャップ ≤ 30分を統合)
    static func mergeNearbyWindows(_ windows: [ViewingWindow], gapThreshold: TimeInterval = 30 * 60) -> [ViewingWindow] {
        guard windows.count > 1 else { return windows }
        var result: [ViewingWindow] = []
        var current = windows[0]
        for next in windows.dropFirst() {
            let gap = next.start.timeIntervalSince(current.end)
            if gap <= gapThreshold {
                let useCurrent = current.peakAltitude >= next.peakAltitude
                current = ViewingWindow(
                    start: current.start,
                    end: next.end,
                    peakTime: useCurrent ? current.peakTime : next.peakTime,
                    peakAltitude: useCurrent ? current.peakAltitude : next.peakAltitude,
                    peakAzimuth: useCurrent ? current.peakAzimuth : next.peakAzimuth
                )
            } else {
                result.append(current)
                current = next
            }
        }
        result.append(current)
        return result
    }

    // 指定した日付のナイトサマリーを計算
    static func calculateNightSummary(date: Date, location: CLLocationCoordinate2D) -> NightSummary {
        let events = calculateEvents(date: date, location: location)
        let windows = findViewingWindows(events: events)

        // 深夜0時の月の位相
        let midnight = Calendar(identifier: .gregorian).startOfDay(for: date).addingTimeInterval(86400)
        let moonAtMidnight = moonRaDec(jd: julianDate(from: midnight))

        return NightSummary(
            date: date,
            location: location,
            events: events,
            viewingWindows: windows,
            moonPhaseAtMidnight: moonAtMidnight.phase
        )
    }

    // 今後N日間の各夜のサマリーを計算
    static func calculateUpcomingNights(from startDate: Date, location: CLLocationCoordinate2D, days: Int = 14) -> [NightSummary] {
        (0..<days).map { offset in
            let date = startDate.addingTimeInterval(Double(offset) * 86400)
            return calculateNightSummary(date: date, location: location)
        }
    }
}
