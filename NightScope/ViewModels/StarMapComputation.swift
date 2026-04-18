import SwiftUI

enum StarMapComputation {
    struct Snapshot: Sendable {
        let lat: Double
        let lst: Double
        let starPositions: [StarPosition]
        let sunAltitude: Double
        let moonAltitude: Double
        let moonAzimuth: Double
        let moonPhase: Double
        let galacticCenterAltitude: Double
        let galacticCenterAzimuth: Double
        let constellationLines: [ConstellationLineAltAz]
        let constellationLabels: [ConstellationLabelAltAz]
        let planetPositions: [PlanetPosition]
        let meteorShowerRadiants: [(shower: MeteorShower, altitude: Double, azimuth: Double)]
        let milkyWayBandPoints: [MilkyWayBandPoint]
    }

    private static let cachedStarColors: [Color] = {
        StarCatalog.stars.map { _starColorForBV($0.colorIndex) }
    }()

    static func compute(
        latitude: Double,
        longitude: Double,
        julianDate: Double,
        localSiderealTime: Double,
        activeMeteorShowers: [MeteorShower],
        starDisplayDensity: StarDisplayDensity
    ) -> Snapshot {
        let latRad = latitude * .pi / 180.0
        let cosLat = cos(latRad)
        let sinLat = sin(latRad)

        let catalog = StarCatalog.stars
        let magnitudeLimit = starDisplayDensity.maxMagnitude
        var stars = [StarPosition]()
        stars.reserveCapacity(catalog.count / 2)

        for index in catalog.indices {
            let star = catalog[index]
            guard star.magnitude <= magnitudeLimit else { continue }
            let (altitude, azimuth) = MilkyWayCalculator.altAzFast(
                ra: star.ra,
                dec: star.dec,
                cosLat: cosLat,
                sinLat: sinLat,
                lst: localSiderealTime
            )
            guard altitude > -3 else { continue }
            stars.append(
                StarPosition(
                    star: star,
                    altitude: altitude,
                    azimuth: azimuth,
                    precomputedColor: cachedStarColors[index]
                )
            )
        }

        let sun = MilkyWayCalculator.sunRaDec(jd: julianDate)
        let (sunAltitude, _) = MilkyWayCalculator.altAzFast(
            ra: sun.ra,
            dec: sun.dec,
            cosLat: cosLat,
            sinLat: sinLat,
            lst: localSiderealTime
        )

        let moon = MilkyWayCalculator.moonRaDec(jd: julianDate)
        let (moonAltitude, moonAzimuth) = MilkyWayCalculator.altAzFast(
            ra: moon.ra,
            dec: moon.dec,
            cosLat: cosLat,
            sinLat: sinLat,
            lst: localSiderealTime
        )

        let (galacticCenterAltitude, galacticCenterAzimuth) = MilkyWayCalculator.altAzFast(
            ra: MilkyWayCalculator.gcRA,
            dec: MilkyWayCalculator.gcDec,
            cosLat: cosLat,
            sinLat: sinLat,
            lst: localSiderealTime
        )

        let constellationLines: [ConstellationLineAltAz] = ConstellationData.constellations.flatMap { entry in
            entry.segments.compactMap { segment in
                let (startAltitude, startAzimuth) = MilkyWayCalculator.altAzFast(
                    ra: segment.ra1,
                    dec: segment.dec1,
                    cosLat: cosLat,
                    sinLat: sinLat,
                    lst: localSiderealTime
                )
                let (endAltitude, endAzimuth) = MilkyWayCalculator.altAzFast(
                    ra: segment.ra2,
                    dec: segment.dec2,
                    cosLat: cosLat,
                    sinLat: sinLat,
                    lst: localSiderealTime
                )
                guard startAltitude > -15 || endAltitude > -15 else { return nil }
                return ConstellationLineAltAz(
                    startAlt: startAltitude,
                    startAz: startAzimuth,
                    endAlt: endAltitude,
                    endAz: endAzimuth
                )
            }
        }

        let constellationLabels: [ConstellationLabelAltAz] = ConstellationData.constellations.compactMap { entry in
            let (altitude, azimuth) = MilkyWayCalculator.altAzFast(
                ra: entry.centerRA,
                dec: entry.centerDec,
                cosLat: cosLat,
                sinLat: sinLat,
                lst: localSiderealTime
            )
            guard altitude > -5 else { return nil }
            return ConstellationLabelAltAz(alt: altitude, az: azimuth, name: entry.localizedName)
        }

        let meteorRadiants = activeMeteorShowers.map { shower in
            let (altitude, azimuth) = MilkyWayCalculator.altAzFast(
                ra: shower.radiantRA,
                dec: shower.radiantDec,
                cosLat: cosLat,
                sinLat: sinLat,
                lst: localSiderealTime
            )
            return (shower: shower, altitude: altitude, azimuth: azimuth)
        }

        return Snapshot(
            lat: latitude,
            lst: localSiderealTime,
            starPositions: stars,
            sunAltitude: sunAltitude,
            moonAltitude: moonAltitude,
            moonAzimuth: moonAzimuth,
            moonPhase: moon.phase,
            galacticCenterAltitude: galacticCenterAltitude,
            galacticCenterAzimuth: galacticCenterAzimuth,
            constellationLines: constellationLines,
            constellationLabels: constellationLabels,
            planetPositions: MilkyWayCalculator.planetPositions(
                jd: julianDate,
                latitude: latitude,
                lst: localSiderealTime
            ),
            meteorShowerRadiants: meteorRadiants,
            milkyWayBandPoints: computeMilkyWayBandPoints(
                cosLat: cosLat,
                sinLat: sinLat,
                lst: localSiderealTime
            )
        )
    }

    private static func computeMilkyWayBandPoints(
        cosLat: Double,
        sinLat: Double,
        lst: Double
    ) -> [MilkyWayBandPoint] {
        var result = [MilkyWayBandPoint]()
        let step: Double = 5

        for longitude in stride(from: 0.0, to: 360.0, by: step) {
            let equatorialCenter = MilkyWayCalculator.galacticToEquatorial(l: longitude, b: 0)
            let (altitudeCenter, azimuthCenter) = MilkyWayCalculator.altAzFast(
                ra: equatorialCenter.ra,
                dec: equatorialCenter.dec,
                cosLat: cosLat,
                sinLat: sinLat,
                lst: lst
            )
            guard altitudeCenter > -5 else { continue }

            let bandWidth: Double = longitude > 270 || longitude < 90 ? 12 : 8
            let upper = MilkyWayCalculator.galacticToEquatorial(l: longitude, b: bandWidth)
            let lower = MilkyWayCalculator.galacticToEquatorial(l: longitude, b: -bandWidth)
            let (upperAltitude, _) = MilkyWayCalculator.altAzFast(
                ra: upper.ra,
                dec: upper.dec,
                cosLat: cosLat,
                sinLat: sinLat,
                lst: lst
            )
            let (lowerAltitude, _) = MilkyWayCalculator.altAzFast(
                ra: lower.ra,
                dec: lower.dec,
                cosLat: cosLat,
                sinLat: sinLat,
                lst: lst
            )

            result.append(
                MilkyWayBandPoint(
                    az: azimuthCenter,
                    alt: altitudeCenter,
                    halfH: max(3.0, abs(upperAltitude - lowerAltitude) / 2),
                    li: longitude
                )
            )
        }

        return result
    }
}
