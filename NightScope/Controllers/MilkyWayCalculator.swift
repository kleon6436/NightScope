import Foundation
import CoreLocation

// MARK: - Calculator

enum MilkyWayCalculator {
    enum Constants {
        static let sampleIntervalMinutes = 15
        static let secondsPerDay: TimeInterval = 86400
        /// 近接ウィンドウをマージするギャップ許容値（秒）
        /// 根拠: 銀河系中心が高度10°以下に短時間沈むケースや一時的な雲の通過を
        ///       連続した観測ウィンドウとして扱うための許容値。AstroModels と共有。
        static let windowMergeGapSeconds: TimeInterval = 30 * 60
    }

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

    // 赤経・赤緯から高度と方位角をまとめて計算 (度)
    // altitude() / azimuth() を個別に呼ぶと中間値を2回計算してしまうため、
    // 1回の呼び出しで両方を返す統合関数。ホットループ (星9,000+ 件) で使用する。
    static func altAz(ra: Double, dec: Double, latitude: Double, lst: Double) -> (alt: Double, az: Double) {
        let latRad = latitude * .pi / 180.0
        return altAzFast(ra: ra, dec: dec, cosLat: cos(latRad), sinLat: sin(latRad), lst: lst)
    }

    /// lat の sin/cos を呼び出し元で事前計算してから渡すバッチ高速版。
    /// 多数の天体を同一緯度で一括変換するホットループ（星 25,000+ 件）で使用する。
    static func altAzFast(ra: Double, dec: Double,
                          cosLat: Double, sinLat: Double,
                          lst: Double) -> (alt: Double, az: Double) {
        var ha = lst - ra
        ha = ha.truncatingRemainder(dividingBy: 360.0)

        let haRad  = ha  * .pi / 180.0
        let decRad = dec * .pi / 180.0

        let cosDec = cos(decRad)
        let sinDec = sin(decRad)
        let cosHa  = cos(haRad)
        let sinHa  = sin(haRad)

        let sinAlt = sinLat * sinDec + cosLat * cosDec * cosHa
        let altRad = asin(max(-1, min(1, sinAlt)))
        let alt    = altRad * 180.0 / .pi

        let cosAlt = cos(altRad)
        guard cosAlt > 1e-10 else { return (alt, 0.0) }

        let sinA = -sinHa * cosDec / cosAlt
        let cosA = (sinDec - sinLat * sinAlt) / (cosLat * cosAlt)
        var az = atan2(sinA, cosA) * 180.0 / .pi
        if az < 0 { az += 360.0 }
        return (alt, az)
    }

    // 赤経・赤緯から高度を計算 (度)
    static func altitude(ra: Double, dec: Double, latitude: Double, lst: Double) -> Double {
        altAz(ra: ra, dec: dec, latitude: latitude, lst: lst).alt
    }

    // 赤経・赤緯から方位角を計算 (北=0°, 時計回り)
    static func azimuth(ra: Double, dec: Double, latitude: Double, lst: Double) -> Double {
        altAz(ra: ra, dec: dec, latitude: latitude, lst: lst).az
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

    // MARK: - 市民薄明の計算

    /// 指定日・場所の市民薄明 (太陽高度 -6°) の開始/終了時刻を分単位で返す。
    /// 正午 (12:00) を起点に探索し、日没側 → 翌朝側の順に見つける。
    /// 白夜・極夜などで夜がない場合は nil を返す。
    static func findCivilTwilightMinutes(date: Date, location: CLLocationCoordinate2D)
        -> (eveningMinutes: Double, morningMinutes: Double)? {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: date)
        let latRad = location.latitude * .pi / 180.0
        let cosLat = cos(latRad)
        let sinLat = sin(latRad)
        let threshold = -6.0  // 市民薄明

        // 正午 (720分) から翌日正午 (2160分) まで1分刻みで太陽高度を評価
        var eveningMinutes: Double?
        var morningMinutes: Double?
        var prevAlt: Double?

        for m in 720...2160 {
            let sampleDate = startOfDay.addingTimeInterval(Double(m) * 60)
            let jd = julianDate(from: sampleDate)
            let lst = localSiderealTime(jd: jd, longitude: location.longitude)
            let sun = sunRaDec(jd: jd)
            let (sunAlt, _) = altAzFast(ra: sun.ra, dec: sun.dec,
                                         cosLat: cosLat, sinLat: sinLat, lst: lst)

            if let prev = prevAlt {
                if eveningMinutes == nil && prev >= threshold && sunAlt < threshold {
                    // 太陽が閾値を下回った (夕方の薄明終了)
                    eveningMinutes = Double(m)
                } else if eveningMinutes != nil && morningMinutes == nil && prev < threshold && sunAlt >= threshold {
                    // 太陽が閾値を上回った (朝方の薄明開始)
                    morningMinutes = Double(m)
                    break
                }
            }
            prevAlt = sunAlt
        }

        guard let evening = eveningMinutes, let morning = morningMinutes else {
            return nil  // 白夜または極夜
        }
        // 1440 を超えた分は翌日扱い→ mod 1440 で 0:00〜23:59 に変換
        return (eveningMinutes: evening.truncatingRemainder(dividingBy: 1440),
                morningMinutes: morning.truncatingRemainder(dividingBy: 1440))
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

        for minutes in stride(from: 0, to: 24 * 60, by: Constants.sampleIntervalMinutes) {
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
                if let window = makeViewingWindow(start: start, samples: windowSamples) {
                    windows.append(window)
                }
                windowStart = nil
                windowSamples = []
            }
        }

        if let start = windowStart,
           let window = makeViewingWindow(start: start, samples: windowSamples) {
            windows.append(window)
        }

        return mergeNearbyWindows(windows)
    }

    private static func makeViewingWindow(start: Date, samples: [AstroEvent]) -> ViewingWindow? {
        guard !samples.isEmpty,
              let bestAlt = samples.max(by: { $0.galacticCenterAltitude < $1.galacticCenterAltitude }),
              let bestViewing = samples.max(by: { viewingScore($0) < viewingScore($1) }),
              let lastSample = samples.last else {
            return nil
        }

        return ViewingWindow(
            start: start,
            end: lastSample.date,
            peakTime: bestViewing.date,
            peakAltitude: bestAlt.galacticCenterAltitude,
            peakAzimuth: bestViewing.galacticCenterAzimuth
        )
    }

    // 近接ウィンドウをマージ (ギャップ ≤ 30分を統合)
    static func mergeNearbyWindows(_ windows: [ViewingWindow], gapThreshold: TimeInterval = Constants.windowMergeGapSeconds) -> [ViewingWindow] {
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
        let midnight = Calendar(identifier: .gregorian).startOfDay(for: date).addingTimeInterval(Constants.secondsPerDay)
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
            let date = startDate.addingTimeInterval(Double(offset) * Constants.secondsPerDay)
            return calculateNightSummary(date: date, location: location)
        }
    }

    // MARK: - Galactic coordinate conversion (Phase 5)

    /// 銀河座標 (l, b) を赤道座標 (RA, Dec) に変換する (J2000.0)。
    /// IAU 1958 定義: 北銀極 RA=192.85948°, Dec=27.12825°,
    /// 銀河赤道の昇交点銀経 l_Ω = 32.93192°
    /// - Parameters:
    ///   - l: 銀経 (度)
    ///   - b: 銀緯 (度)
    /// - Returns: (ra: 度, dec: 度)
    static func galacticToEquatorial(l: Double, b: Double) -> (ra: Double, dec: Double) {
        let lRad   = l * .pi / 180
        let bRad   = b * .pi / 180
        let raGP   = 192.85948 * .pi / 180  // 北銀極の赤経
        let decGP  =  27.12825 * .pi / 180  // 北銀極の赤緯
        let lOmega =  32.93192 * .pi / 180  // 銀河赤道の昇交点銀経

        let theta = lRad - lOmega

        let sinDec = cos(bRad) * cos(decGP) * sin(theta) + sin(bRad) * sin(decGP)
        let dec = asin(max(-1.0, min(1.0, sinDec)))

        let y =  cos(bRad) * cos(theta)
        let x = -cos(bRad) * sin(decGP) * sin(theta) + sin(bRad) * cos(decGP)
        var ra = (raGP + atan2(y, x)) * 180 / .pi
        ra = ra.truncatingRemainder(dividingBy: 360)
        if ra < 0 { ra += 360 }
        return (ra: ra, dec: dec * 180 / .pi)
    }

    // MARK: - Planet Positions (Meeus "Astronomical Algorithms", Table 31.a)

    private struct PlanetOrbit {
        let name: String
        let a: Double         // semi-major axis (AU)
        let e0, eRate: Double // eccentricity = e0 + eRate·T
        let i0, iRate: Double // inclination (deg)
        let Ω0, ΩRate: Double // longitude of ascending node (deg)
        let ω0, ωRate: Double // longitude of perihelion (deg)
        let L0, LRate: Double // mean longitude (deg)
        let H: Double         // absolute magnitude (simplified)
    }

    private static let planetOrbits: [PlanetOrbit] = [
        PlanetOrbit(name: "水星",
            a: 0.38709927, e0: 0.20563593, eRate:  0.00001906,
            i0: 7.00497902, iRate: -0.00594749,
            Ω0: 48.33076593, ΩRate: -0.12534081,
            ω0: 77.45779628, ωRate:  0.16047689,
            L0: 252.25032350, LRate: 149472.67411175, H: -0.42),
        PlanetOrbit(name: "金星",
            a: 0.72333566, e0: 0.00677672, eRate: -0.00004107,
            i0: 3.39467605, iRate: -0.00078890,
            Ω0: 76.67984255, ΩRate: -0.27769418,
            ω0: 131.60246718, ωRate: 0.00268329,
            L0: 181.97909950, LRate: 58517.81538729, H: -4.40),
        PlanetOrbit(name: "火星",
            a: 1.52371034, e0: 0.09339410, eRate:  0.00007882,
            i0: 1.84969142, iRate: -0.00813131,
            Ω0: 49.55953891, ΩRate: -0.29257343,
            ω0: -23.94362959, ωRate: 0.44441088,
            L0: -4.55343205, LRate: 19140.30268499, H: -1.52),
        PlanetOrbit(name: "木星",
            a: 5.20288700, e0: 0.04838624, eRate: -0.00013244,
            i0: 1.30439695, iRate: -0.00183714,
            Ω0: 100.47390909, ΩRate: 0.20469106,
            ω0: 14.72847983, ωRate: 0.21252668,
            L0: 34.39644051, LRate: 3034.74612775, H: -9.40),
        PlanetOrbit(name: "土星",
            a: 9.53667594, e0: 0.05386179, eRate: -0.00013117,
            i0: 2.48599187, iRate:  0.00193609,
            Ω0: 113.66242448, ΩRate: -0.28867794,
            ω0: 92.59887831, ωRate: -0.41897216,
            L0: 49.95424423, LRate: 1222.49362201, H: -8.88),
    ]

    private static func normDeg(_ x: Double) -> Double {
        var r = x.truncatingRemainder(dividingBy: 360.0)
        if r < 0 { r += 360.0 }
        return r
    }

    /// ケプラー方程式を Newton 法で反復解する (M: 平均近点角 rad, e: 離心率)
    private static func solveKepler(M: Double, e: Double) -> Double {
        var E = M
        for _ in 0..<50 {
            let dE = (M - E + e * sin(E)) / (1.0 - e * cos(E))
            E += dE
            if abs(dE) < 1e-10 { break }
        }
        return E
    }

    /// 地球の日心黄道座標 (AU, 黄道面 = xy 平面)
    private static func earthHelioXY(T: Double) -> (x: Double, y: Double) {
        let e  = 0.01671123 - 0.00004392 * T
        let ωD = normDeg(102.93768193 + 0.32327364 * T)
        let LD = normDeg(100.46457166 + 35999.37244981 * T)
        let M  = normDeg(LD - ωD) * .pi / 180.0
        let ω  = ωD * .pi / 180.0
        let E  = solveKepler(M: M, e: e)
        let r  = 1.00000261 * (1.0 - e * cos(E))
        let nu = atan2(sqrt(max(0, 1.0 - e * e)) * sin(E), cos(E) - e)
        let lambda = nu + ω  // 日心黄道経度 (rad)
        return (r * cos(lambda), r * sin(lambda))
    }

    /// 観測地と観測時刻における 5 惑星の地平座標を返す。
    /// - Parameters:
    ///   - jd: ユリウス日
    ///   - latitude: 観測地緯度 (度)
    ///   - lst: 地方恒星時 (度)
    static func planetPositions(jd: Double, latitude: Double, lst: Double) -> [PlanetPosition] {
        let T     = (jd - 2451545.0) / 36525.0
        let earth = earthHelioXY(T: T)
        let ε     = (23.439291 - 0.013004 * T) * .pi / 180.0

        return planetOrbits.compactMap { orbit in
            let e    = orbit.e0 + orbit.eRate * T
            let i    = (orbit.i0 + orbit.iRate * T) * .pi / 180.0
            let Ω    = normDeg(orbit.Ω0 + orbit.ΩRate * T) * .pi / 180.0
            let ω    = normDeg(orbit.ω0 + orbit.ωRate * T) * .pi / 180.0
            let M    = normDeg((orbit.L0 + orbit.LRate * T) - (orbit.ω0 + orbit.ωRate * T)) * .pi / 180.0
            let E    = solveKepler(M: M, e: e)
            let r    = orbit.a * (1.0 - e * cos(E))
            let nu   = atan2(sqrt(max(0, 1.0 - e * e)) * sin(E), cos(E) - e)

            // 日心黄道 3D 座標 (Meeus Eq. 33.7)
            let u = nu + (ω - Ω)  // 真近点離角 → 近点黄緯引数
            let X = r * (cos(Ω) * cos(u) - sin(Ω) * sin(u) * cos(i))
            let Y = r * (sin(Ω) * cos(u) + cos(Ω) * sin(u) * cos(i))
            let Z = r * sin(u) * sin(i)

            // 地心黄道座標
            let dx = X - earth.x, dy = Y - earth.y, dz = Z
            let Δ  = sqrt(dx*dx + dy*dy + dz*dz)
            guard Δ > 1e-6 else { return nil }

            let λGeo = atan2(dy, dx)
            let βGeo = atan2(dz, sqrt(dx*dx + dy*dy))

            // 黄道 → 赤道変換
            var ra = atan2(sin(λGeo)*cos(ε) - tan(βGeo)*sin(ε), cos(λGeo)) * 180.0 / .pi
            if ra < 0 { ra += 360.0 }
            let dec = asin(max(-1.0, min(1.0, sin(βGeo)*cos(ε) + cos(βGeo)*sin(ε)*sin(λGeo)))) * 180.0 / .pi

            let alt = altitude(ra: ra, dec: dec, latitude: latitude, lst: lst)
            let az  = azimuth( ra: ra, dec: dec, latitude: latitude, lst: lst)

            // 簡易等級 (位相角補正なし。内惑星は過大評価になるが実視に支障はない)
            let mag = min(orbit.H + 5.0 * log10(max(1e-6, r * Δ)), 5.0)
            return PlanetPosition(name: orbit.name, altitude: alt, azimuth: az,
                                  magnitude: mag, geocentricDistAU: Δ)
        }
    }
}
