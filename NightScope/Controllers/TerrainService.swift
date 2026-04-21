import Foundation
import zlib

// MARK: - Elevation Grid Data

/// バンドルされた標高データを読み込む構造体。
///
/// バイナリフォーマット:
///
///   Version 1（全球）:
///   - Magic:     4 bytes  = 0x45 0x4C 0x45 0x56 ("ELEV")
///   - Version:   UInt32 LE = 1
///   - Lat cells: Int32  LE (南から北: -90 → +90)
///   - Lon cells: Int32  LE (西から東: -180 → +180)
///   - Data:      Int16[] LE, row-major, 標高 (メートル、海面上)
///
///   Version 2（領域限定）:
///   - Magic:     4 bytes  = 0x45 0x4C 0x45 0x56 ("ELEV")
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
///   圧縮フォーマット (ELVZ):
///   - Magic:     4 bytes  = 0x45 0x4C 0x56 0x5A ("ELVZ")
///   - Payload:   上記 Version 1/2 全体を zlib.compress(..., 9) で圧縮したデータ
///
/// 生成: Tools/prepare_srtm.py (Copernicus DEM GLO-30: CC BY 4.0)
struct ElevationGridData {
    private let latCells: Int
    private let lonCells: Int
    private let data: [Int16]
    private let latMin: Double
    private let latMax: Double
    private let lonMin: Double
    private let lonMax: Double

    private static let magic: [UInt8] = [0x45, 0x4C, 0x45, 0x56]  // "ELEV"
    private static let compressedMagic: [UInt8] = [0x45, 0x4C, 0x56, 0x5A]  // "ELVZ"

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
        let normalizedLongitude = normalizedLongitudeIfNeeded(longitude)
        guard latitude >= latMin, latitude <= latMax,
              normalizedLongitude >= lonMin, normalizedLongitude <= lonMax else { return 0.0 }
        let latIdx = Int((latitude - latMin) / (latMax - latMin) * Double(latCells))
            .clamped(to: 0..<latCells)
        let lonIdx = Int((normalizedLongitude - lonMin) / (lonMax - lonMin) * Double(lonCells))
            .clamped(to: 0..<lonCells)
        return Double(data[latIdx * lonCells + lonIdx])
    }

    /// 指定座標がこのグリッドの範囲内かどうかを返す。
    func contains(latitude: Double, longitude: Double) -> Bool {
        let normalizedLon = (lonMax - lonMin) >= 359 ? Self.normalizedLongitude(longitude) : longitude
        return latitude >= latMin && latitude <= latMax && normalizedLon >= lonMin && normalizedLon <= lonMax
    }

    private func normalizedLongitudeIfNeeded(_ longitude: Double) -> Double {
        guard (lonMax - lonMin) >= 359 else { return longitude }
        return Self.normalizedLongitude(longitude)
    }

    private static func normalizedLongitude(_ longitude: Double) -> Double {
        var normalized = longitude.truncatingRemainder(dividingBy: 360.0)
        if normalized <= -180.0 {
            normalized += 360.0
        } else if normalized > 180.0 {
            normalized -= 360.0
        }
        return normalized
    }

    /// バンドルファイル（非圧縮 ELEV または圧縮 ELVZ）から読み込む。
    static func load(from url: URL) -> ElevationGridData? {
        guard let fileData = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        guard fileData.count >= 4 else { return nil }
        // ELVZ マジック (0x45 0x4C 0x56 0x5A) → zlib 展開
        if fileData[0..<4].elementsEqual(compressedMagic) {
            guard let decompressed = decompressZlib(Data(fileData.dropFirst(4))) else { return nil }
            return ElevationGridData(data: decompressed)
        }
        return ElevationGridData(data: fileData)
    }

    private static func decompressZlib(_ data: Data) -> Data? {
        var stream = z_stream()
        let initStatus = inflateInit_(&stream, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initStatus == Z_OK else { return nil }
        defer { inflateEnd(&stream) }

        return data.withUnsafeBytes { srcRaw -> Data? in
            guard let srcBase = srcRaw.bindMemory(to: Bytef.self).baseAddress else { return nil }

            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: srcBase)
            stream.avail_in = uInt(data.count)

            var output = Data()
            let chunkSize = 256 * 1024
            let outBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
            defer { outBuffer.deallocate() }

            while true {
                stream.next_out = outBuffer
                stream.avail_out = uInt(chunkSize)

                let status = inflate(&stream, Z_NO_FLUSH)
                let produced = chunkSize - Int(stream.avail_out)
                if produced > 0 {
                    output.append(outBuffer, count: produced)
                }

                if status == Z_STREAM_END {
                    return output
                }
                if status != Z_OK {
                    return nil
                }
            }
        }
    }
}

private extension Int {
    func clamped(to range: Range<Int>) -> Int {
        Swift.max(range.lowerBound, Swift.min(self, range.upperBound - 1))
    }
}

// MARK: - Service

/// 観測地周辺の地形データを提供する Actor。
/// Copernicus DEM バンドルデータから各方位の標高を読み込み、地球曲率と
/// 観測者の目の高さを考慮した地平仰角プロファイルを構築する。
/// 高解像度グリッド（日本等）があれば優先的に使い、範囲外は全球グリッドにフォールバックする。
/// バンドルデータが存在しない場合は nil を返す（平坦地扱い）。
actor TerrainService {
    private enum Constants {
        static let sampleCount = 72
        static let cachePrecisionDegrees = 0.001
        static let eyeHeightMeters = 1.7
        static let earthRadiusMeters = 6_371_000.0
        /// サンプリング距離候補 (m)。近距離は密に、遠距離は粗くなる。
        static let sampleDistanceCandidates: [Double] = [
            500, 1_000, 2_000, 4_000, 8_000,
            15_000, 25_000, 40_000, 60_000, 80_000, 100_000
        ]
        /// 想定最高峰 (m)。最大サンプリング距離の計算に使用。
        static let maxPeakElevationMeters = 4_500.0
        /// 100km を超えると仰角 < 2° となり星空遮蔽への影響が小さいためキャップ。
        static let maxSamplingDistanceMeters = 100_000.0
    }

    static let shared = TerrainService()

    private let cache = NSCache<NSString, NSArray>()
    private let globalData: ElevationGridData?
    private let highResData: ElevationGridData?

    init(globalData: ElevationGridData? = TerrainService.loadGlobalData(),
         highResData: ElevationGridData? = TerrainService.loadHighResData()) {
        self.globalData = globalData
        self.highResData = highResData
    }

    /// elevation_global (.bin.z / .bin) を読み込む。
    private static func loadGlobalData() -> ElevationGridData? {
        loadFile(name: "elevation_global")
    }

    /// elevation_japan (.bin.z / .bin) を読み込む。
    private static func loadHighResData() -> ElevationGridData? {
        loadFile(name: "elevation_japan")
    }

    /// name.bin.z（圧縮）→ name.bin（非圧縮）の順で Bundle.main を検索して読み込む。
    private static func loadFile(name: String) -> ElevationGridData? {
        let candidates: [(resource: String, ext: String)] = [
            (name, "bin.z"),
            ("\(name).bin", "z"),
            (name, "bin")
        ]

        for candidate in candidates {
            guard let url = Bundle.main.url(forResource: candidate.resource, withExtension: candidate.ext) else {
                continue
            }
            if let data = ElevationGridData.load(from: url) {
                return data
            }
        }

        let expectedCompressedName = "\(name).bin.z"
        if let compressedURLs = Bundle.main.urls(forResourcesWithExtension: "z", subdirectory: nil) {
            for url in compressedURLs where url.lastPathComponent == expectedCompressedName {
                if let data = ElevationGridData.load(from: url) {
                    return data
                }
            }
        }

        let expectedPlainName = "\(name).bin"
        if let plainURLs = Bundle.main.urls(forResourcesWithExtension: "bin", subdirectory: nil) {
            for url in plainURLs where url.lastPathComponent == expectedPlainName {
                if let data = ElevationGridData.load(from: url) {
                    return data
                }
            }
        }

        return nil
    }

    /// 観測地座標に対するプロファイルを返す。キャッシュがあればそれを使う。
    /// バンドルデータが存在しない場合は nil を返す（呼び出し元は平坦地として扱う）。
    func fetchProfile(latitude: Double, longitude: Double) async -> TerrainProfile? {
        let key = Self.cacheKey(latitude: latitude, longitude: longitude) as NSString
        if let cached = cache.object(forKey: key) as? [Double] {
            return TerrainProfile(horizonAngles: cached)
        }
        guard globalData != nil || highResData != nil else { return nil }

        let angles = computeAngles(latitude: latitude, longitude: longitude)
        cache.setObject(angles as NSArray, forKey: key)
        return TerrainProfile(horizonAngles: angles)
    }

    // MARK: - Private

    nonisolated static func cacheKey(latitude: Double, longitude: Double) -> String {
        let rLat = roundedCoordinateComponent(latitude)
        let rLon = roundedCoordinateComponent(normalizedLongitude(longitude))
        return "\(rLat),\(rLon)"
    }

    /// 観測者標高に基づき、地形が空を遮る可能性がある最大距離 (m) を返す。
    /// 幾何学的水平線距離: d_max = √(2R·h_obs) + √(2R·H_peak)
    nonisolated static func maxUsefulDistance(observerElevation: Double) -> Double {
        let R = Constants.earthRadiusMeters
        let hObs = max(observerElevation + Constants.eyeHeightMeters, 0)
        let dObs = (2 * R * hObs).squareRoot()
        let dPeak = (2 * R * Constants.maxPeakElevationMeters).squareRoot()
        return min(dObs + dPeak, Constants.maxSamplingDistanceMeters)
    }

    /// maxDistance 以内のサンプリング距離を返す。
    nonisolated static func adaptiveSampleDistances(maxDistance: Double) -> [Double] {
        Constants.sampleDistanceCandidates.filter { $0 <= maxDistance }
    }

    /// 高解像度グリッドを優先し、範囲外なら全球にフォールバック。両方 nil の場合は 0.0 を返す。
    private func elevation(latitude: Double, longitude: Double) -> Double {
        if let hires = highResData {
            let val = hires.elevation(latitude: latitude, longitude: longitude)
            if val != 0.0 { return val }
            // 0.0 は範囲外の可能性があるので、座標がグリッド範囲内か確認
            if hires.contains(latitude: latitude, longitude: longitude) {
                return val
            }
        }
        return globalData?.elevation(latitude: latitude, longitude: longitude) ?? 0.0
    }

    /// バンドルデータから 72 方位の地平仰角を計算する。
    /// 地球曲率と観測者の目の高さ (1.7m) を考慮する。
    private func computeAngles(latitude: Double, longitude: Double) -> [Double] {
        let obsElev = elevation(latitude: latitude, longitude: longitude)
        let maxDist = Self.maxUsefulDistance(observerElevation: obsElev)
        let distances = Self.adaptiveSampleDistances(maxDistance: maxDist)
        let viewerHeight = obsElev + Constants.eyeHeightMeters

        return (0..<Constants.sampleCount).map { index in
            let bearing = Double(index) * 5.0
            return distances.reduce(-90.0) { highestAngle, sampleDistance in
                let (lat2, lon2) = destinationPoint(
                    lat: latitude,
                    lon: longitude,
                    bearing: bearing,
                    distanceM: sampleDistance
                )
                let targetElev = self.elevation(latitude: lat2, longitude: lon2)
                let curvatureDrop = sampleDistance * sampleDistance
                    / (2.0 * Constants.earthRadiusMeters)
                let apparentHeight = targetElev - viewerHeight - curvatureDrop
                let angle = atan2(apparentHeight, sampleDistance) * 180.0 / .pi
                return max(highestAngle, angle)
            }
        }
    }

    private nonisolated static func roundedCoordinateComponent(_ value: Double) -> Double {
        (value / Constants.cachePrecisionDegrees).rounded() * Constants.cachePrecisionDegrees
    }

    private nonisolated static func normalizedLongitude(_ longitude: Double) -> Double {
        var normalized = longitude.truncatingRemainder(dividingBy: 360.0)
        if normalized <= -180.0 {
            normalized += 360.0
        } else if normalized > 180.0 {
            normalized -= 360.0
        }
        return normalized
    }

    /// Haversine 公式: 距離 distanceM 先の方位 bearing にある座標を返す。
    private func destinationPoint(lat: Double, lon: Double,
                                  bearing: Double, distanceM: Double) -> (Double, Double) {
        let R    = Constants.earthRadiusMeters
        let d    = distanceM / R
        let lat1 = lat * .pi / 180
        let lon1 = lon * .pi / 180
        let brng = bearing * .pi / 180
        let lat2 = asin(sin(lat1) * cos(d) + cos(lat1) * sin(d) * cos(brng))
        let lon2 = lon1 + atan2(sin(brng) * sin(d) * cos(lat1),
                                cos(d) - sin(lat1) * sin(lat2))
        return (lat2 * 180 / .pi, Self.normalizedLongitude(lon2 * 180 / .pi))
    }
}
