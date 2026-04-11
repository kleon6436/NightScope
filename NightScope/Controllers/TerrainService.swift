import Foundation

// MARK: - SRTM Elevation Grid Data

/// バンドルされた SRTM 標高データを読み込む構造体。
///
/// バイナリフォーマット:
///
///   Version 1（全球）:
///   - Magic:     4 bytes  = 0x53 0x52 0x54 0x4D ("SRTM")
///   - Version:   UInt32 LE = 1
///   - Lat cells: Int32  LE (南から北: -90 → +90)
///   - Lon cells: Int32  LE (西から東: -180 → +180)
///   - Data:      Int16[] LE, row-major, 標高 (メートル、海面上)
///
///   Version 2（領域限定）:
///   - Magic:     4 bytes  = 0x53 0x52 0x54 0x4D ("SRTM")
///   - Version:   UInt32 LE = 2
///   - Lat cells: Int32  LE
///   - Lon cells: Int32  LE
///   - Lat min:   Float32 LE  (南端)
///   - Lat max:   Float32 LE  (北端)
///   - Lon min:   Float32 LE  (西端)
///   - Lon max:   Float32 LE  (東端)
///   - Data:      Int16[] LE, row-major, 標高 (メートル、海面上)
///
///   範囲外座標は 0m（平坦地）を返す。
///
/// 生成: Tools/prepare_srtm.py (NASA SRTM, パブリックドメイン)
struct ElevationGridData {
    private let latCells: Int
    private let lonCells: Int
    private let data: [Int16]
    private let latMin: Double
    private let latMax: Double
    private let lonMin: Double
    private let lonMax: Double

    private static let magic: [UInt8] = [0x53, 0x52, 0x54, 0x4D]  // "SRTM"

    init?(data fileData: Data) {
        guard fileData.count >= 16 else { return nil }
        guard fileData[0..<4].elementsEqual(Self.magic) else { return nil }

        let version = fileData[4..<8].withUnsafeBytes {
            $0.loadUnaligned(as: UInt32.self).littleEndian
        }
        let latCells = Int(fileData[8..<12].withUnsafeBytes {
            $0.loadUnaligned(as: Int32.self).littleEndian
        })
        let lonCells = Int(fileData[12..<16].withUnsafeBytes {
            $0.loadUnaligned(as: Int32.self).littleEndian
        })

        let headerSize: Int
        let latMin: Double
        let latMax: Double
        let lonMin: Double
        let lonMax: Double

        switch version {
        case 1:
            headerSize = 16
            latMin = -90.0; latMax = 90.0
            lonMin = -180.0; lonMax = 180.0
        case 2:
            guard fileData.count >= 32 else { return nil }
            latMin  = Double(fileData[16..<20].withUnsafeBytes { $0.loadUnaligned(as: Float32.self) })
            latMax  = Double(fileData[20..<24].withUnsafeBytes { $0.loadUnaligned(as: Float32.self) })
            lonMin  = Double(fileData[24..<28].withUnsafeBytes { $0.loadUnaligned(as: Float32.self) })
            lonMax  = Double(fileData[28..<32].withUnsafeBytes { $0.loadUnaligned(as: Float32.self) })
            headerSize = 32
        default:
            return nil
        }

        let expectedSize = headerSize + latCells * lonCells * 2
        guard fileData.count == expectedSize, latCells > 0, lonCells > 0 else { return nil }

        var elevations = [Int16](repeating: 0, count: latCells * lonCells)
        fileData[headerSize...].withUnsafeBytes { src in
            elevations.withUnsafeMutableBytes { dst in
                dst.copyMemory(from: src)
            }
        }
        self.latCells = latCells
        self.lonCells = lonCells
        self.data = elevations
        self.latMin = latMin
        self.latMax = latMax
        self.lonMin = lonMin
        self.lonMax = lonMax
    }

    /// 指定座標の標高 (m) を返す。データ範囲外の場合は 0m を返す。
    func elevation(latitude: Double, longitude: Double) -> Double {
        guard latitude >= latMin, latitude <= latMax,
              longitude >= lonMin, longitude <= lonMax else { return 0.0 }
        let latIdx = Int((latitude - latMin) / (latMax - latMin) * Double(latCells))
            .clamped(to: 0..<latCells)
        let lonIdx = Int((longitude - lonMin) / (lonMax - lonMin) * Double(lonCells))
            .clamped(to: 0..<lonCells)
        return Double(data[latIdx * lonCells + lonIdx])
    }
}

private extension Int {
    func clamped(to range: Range<Int>) -> Int {
        Swift.max(range.lowerBound, Swift.min(self, range.upperBound - 1))
    }
}

enum TerrainBundleDataSource {
    static let sharedElevationData: ElevationGridData? = loadBundledElevationData()

    private static func loadBundledElevationData() -> ElevationGridData? {
        guard let url = Bundle.main.url(forResource: "srtm_elevation", withExtension: "bin"),
              let data = try? Data(contentsOf: url, options: .mappedIfSafe)
        else { return nil }
        return ElevationGridData(data: data)
    }
}

struct TerrainProfileComputer {
    private enum Constants {
        static let sampleDistanceMeters = 10_000.0
        static let sampleCount = 72
    }

    func cacheKey(latitude: Double, longitude: Double) -> String {
        let roundedLatitude = (latitude * 100).rounded() / 100
        let roundedLongitude = (longitude * 100).rounded() / 100
        return "\(roundedLatitude),\(roundedLongitude)"
    }

    func horizonAngles(latitude: Double, longitude: Double, grid: ElevationGridData) -> [Double] {
        let observerElevation = grid.elevation(latitude: latitude, longitude: longitude)
        return (0..<Constants.sampleCount).map { index in
            let bearing = Double(index) * 5.0
            let destination = destinationPoint(
                latitude: latitude,
                longitude: longitude,
                bearing: bearing,
                distanceMeters: Constants.sampleDistanceMeters
            )
            let sampledElevation = grid.elevation(
                latitude: destination.latitude,
                longitude: destination.longitude
            )
            return atan2(sampledElevation - observerElevation, Constants.sampleDistanceMeters) * 180.0 / .pi
        }
    }

    private func destinationPoint(
        latitude: Double,
        longitude: Double,
        bearing: Double,
        distanceMeters: Double
    ) -> (latitude: Double, longitude: Double) {
        let earthRadius = 6_371_000.0
        let angularDistance = distanceMeters / earthRadius
        let latitudeRadians = latitude * .pi / 180
        let longitudeRadians = longitude * .pi / 180
        let bearingRadians = bearing * .pi / 180

        let destinationLatitude = asin(
            sin(latitudeRadians) * cos(angularDistance)
            + cos(latitudeRadians) * sin(angularDistance) * cos(bearingRadians)
        )
        let destinationLongitude = longitudeRadians + atan2(
            sin(bearingRadians) * sin(angularDistance) * cos(latitudeRadians),
            cos(angularDistance) - sin(latitudeRadians) * sin(destinationLatitude)
        )

        return (
            destinationLatitude * 180 / .pi,
            destinationLongitude * 180 / .pi
        )
    }
}

// MARK: - Service

/// 観測地周辺の地形データを提供する Actor。
/// NASA SRTM バンドルデータから各方位 10km 先の標高を読み込み、
/// 地平仰角プロファイルを構築する。バンドルデータが存在しない場合は nil を返す（平坦地扱い）。
actor TerrainService {
    static let shared = TerrainService()

    private let cache = NSCache<NSString, NSArray>()
    private let elevationData: ElevationGridData?
    private let profileComputer: TerrainProfileComputer

    init(
        elevationData: ElevationGridData? = TerrainBundleDataSource.sharedElevationData,
        profileComputer: TerrainProfileComputer = TerrainProfileComputer()
    ) {
        self.elevationData = elevationData
        self.profileComputer = profileComputer
    }

    /// 観測地座標に対するプロファイルを返す。キャッシュがあればそれを使う。
    /// バンドルデータが存在しない場合は nil を返す（呼び出し元は平坦地として扱う）。
    func fetchProfile(latitude: Double, longitude: Double) async -> TerrainProfile? {
        let key = profileComputer.cacheKey(latitude: latitude, longitude: longitude) as NSString
        if let cached = cache.object(forKey: key) as? [Double] {
            return TerrainProfile(horizonAngles: cached)
        }
        guard let grid = elevationData else { return nil }

        let angles = profileComputer.horizonAngles(latitude: latitude, longitude: longitude, grid: grid)
        cache.setObject(angles as NSArray, forKey: key)
        return TerrainProfile(horizonAngles: angles)
    }
}
