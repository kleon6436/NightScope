import XCTest
@testable import NightScope
import Compression

final class TerrainServiceTests: XCTestCase {

    func test_fetchProfile_noBundleData_returnsNil() async {
        let service = TerrainService(globalData: nil, highResData: nil)
        let profile = await service.fetchProfile(latitude: 35.0, longitude: 139.0)
        XCTAssertNil(profile, "バンドルデータなしでは nil を返すはず")
    }

    func test_fetchProfile_withBundleData_returns72Angles() async {
        let grid = makeUniformGrid(elevation: 100)
        let service = TerrainService(globalData: grid)
        let profile = await service.fetchProfile(latitude: 35.0, longitude: 139.0)
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.horizonAngles.count, 72)
    }

    func test_fetchProfile_uniformTerrain_allAnglesSlightlyNegative() async {
        let grid = makeUniformGrid(elevation: 500)
        let service = TerrainService(globalData: grid)
        let profile = await service.fetchProfile(latitude: 0, longitude: 0)
        for angle in profile?.horizonAngles ?? [] {
            // 目の高さ 1.7m + 地球曲率でわずかに負になる
            XCTAssertLessThan(angle, 0, "一様地形では目の高さ分だけ負になるはず")
            XCTAssertGreaterThan(angle, -1.0, "一様地形では大きく負にはならないはず")
        }
    }

    func test_fetchProfile_cachesSameRoundedCoordinate() async {
        var computeCount = 0
        let grid = makeCountingGrid(counter: &computeCount, elevation: 0)
        let service = TerrainService(globalData: grid)

        _ = await service.fetchProfile(latitude: 35.1234, longitude: 139.5678)
        let countAfterFirst = computeCount

        _ = await service.fetchProfile(latitude: 35.1239, longitude: 139.5671)
        let countAfterSecond = computeCount

        XCTAssertEqual(countAfterFirst, countAfterSecond, "キャッシュがヒットすれば再計算されないはず")
    }

    func test_fetchProfile_wrapsLongitudeAcrossDateLine() async {
        let grid = makeElevationGrid(
            latCells: 2,
            lonCells: 4,
            elevations: [
                0, 0, 0, 0,
                600, 0, 0, 100
            ]
        )
        let service = TerrainService(globalData: grid)

        let profile = await service.fetchProfile(latitude: 0, longitude: 179.95)

        guard let eastAngle = profile?.horizonAngles.first else {
            return XCTFail("地平プロファイルを取得できませんでした")
        }
        XCTAssertGreaterThan(eastAngle, 0.0, "日付変更線を跨いでも東方向の地形を拾うはず")
    }

    // MARK: - Max Useful Distance & Adaptive Sampling

    func test_maxUsefulDistance_seaLevel() {
        // 海拜 0m: sqrt(2R*1.7) + sqrt(2R*4500) ≈ 4.65km + 7.57km ≈ 12.2km
        let dist = TerrainService.maxUsefulDistance(observerElevation: 0)
        XCTAssertGreaterThan(dist, 10_000, "海拜 0m でも 10km 以上はサンプルすべき")
        XCTAssertLessThanOrEqual(dist, 100_000, "100km キャップを超えないはず")
    }

    func test_maxUsefulDistance_highElevation() {
        // 標高 1000m: sqrt(2R*1001.7) + sqrt(2R*4500) ≈ 113km + 7.57km => 100kmキャップ
        let dist = TerrainService.maxUsefulDistance(observerElevation: 1000)
        XCTAssertEqual(dist, 100_000, accuracy: 1, "高標高では 100km キャップに到達するはず")
    }

    func test_adaptiveSampleDistances_filtersWithinMax() {
        let distances = TerrainService.adaptiveSampleDistances(maxDistance: 10_000)
        XCTAssertTrue(distances.allSatisfy { $0 <= 10_000 })
        XCTAssertEqual(distances.count, 5)  // 500, 1000, 2000, 4000, 8000
    }

    func test_adaptiveSampleDistances_fullRange() {
        let distances = TerrainService.adaptiveSampleDistances(maxDistance: 100_000)
        XCTAssertEqual(distances.count, 11)
    }

    func test_fetchProfile_highResFallsBackToGlobal() async {
        // 高解像度グリッド（Version 2, 日本付近: lat 30–45, lon 130–145）
        let highResGrid = makeVersion2Grid(
            latMin: 30.0, latMax: 45.0, lonMin: 130.0, lonMax: 145.0,
            latCells: 2, lonCells: 2, elevation: 1000
        )
        // 全球グリッド（Version 1, -90〜90 / -180〜180）
        let globalGrid = makeUniformGrid(elevation: 200)

        let service = TerrainService(globalData: globalGrid, highResData: highResGrid)

        // 高解像度範囲外（ヨーロッパ付近）→ 全球グリッドから取得できる
        let profile = await service.fetchProfile(latitude: 48.0, longitude: 2.0)
        XCTAssertNotNil(profile, "\u9ad8\u89e3\u50cf\u5ea6\u7bc4\u56f2\u5916\u3067\u3082\u5168\u7403\u30b0\u30ea\u30c3\u30c9\u304b\u3089\u30d7\u30ed\u30d5\u30a1\u30a4\u30eb\u3092\u53d6\u5f97\u3067\u304d\u308b\u306f\u305a")
        XCTAssertEqual(profile?.horizonAngles.count, 72)
    }

    func test_elevationGridData_load_compressedELVZ() throws {
        let raw = makeElevationVersion1Data(latCells: 2, lonCells: 2, elevation: 123)
        let compressedPayload = try (raw as NSData).compressed(using: .zlib) as Data

        var fileData = Data([0x45, 0x4C, 0x56, 0x5A]) // "ELVZ"
        fileData.append(compressedPayload)

        let fileURL = try writeTemporaryFile(data: fileData)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let grid = ElevationGridData.load(from: fileURL)
        XCTAssertNotNil(grid)
        XCTAssertEqual(grid?.elevation(latitude: 0, longitude: 0), 123, accuracy: 0.1)
    }

    func test_fetchProfile_realYamanakakoData_hasPositiveTerrainAngles() async throws {
        let modelsURL = repositoryRootURL().appendingPathComponent("NightScope/Models", isDirectory: true)
        let globalURL = modelsURL.appendingPathComponent("elevation_global.bin.z")
        let japanURL = modelsURL.appendingPathComponent("elevation_japan.bin.z")

        let globalGrid = ElevationGridData.load(from: globalURL)
        let highResGrid = ElevationGridData.load(from: japanURL)

        guard let globalGrid, let highResGrid else {
            throw XCTSkip("実データが ELEV/ELVZ 形式で未生成のためスキップ: \(globalURL.lastPathComponent), \(japanURL.lastPathComponent)")
        }

        let service = TerrainService(globalData: globalGrid, highResData: highResGrid)
        let profile = await service.fetchProfile(latitude: 35.4175, longitude: 138.8628)

        guard let profile else {
            return XCTFail("山中湖座標で地形プロファイルを取得できませんでした")
        }

        let maxAngle = profile.horizonAngles.max() ?? -.infinity
        XCTAssertGreaterThan(maxAngle, 1.0, "山中湖では周囲地形により遮蔽仰角が正になるはず")
    }

    // MARK: - Helpers

    private func makeUniformGrid(elevation: Int16) -> ElevationGridData? {
        makeElevationGrid(latCells: 2, lonCells: 4, elevation: elevation)
    }

    private func repositoryRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func writeTemporaryFile(data: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("terrain.bin.z")
        try data.write(to: fileURL)
        return fileURL
    }

    private func makeElevationVersion1Data(latCells: Int, lonCells: Int, elevation: Int16) -> Data {
        var data = Data()
        data.append(contentsOf: [0x45, 0x4C, 0x45, 0x56])

        var version = Int32(1).littleEndian
        data.append(contentsOf: withUnsafeBytes(of: &version) { Array($0) })

        var latitude = Int32(latCells).littleEndian
        data.append(contentsOf: withUnsafeBytes(of: &latitude) { Array($0) })

        var longitude = Int32(lonCells).littleEndian
        data.append(contentsOf: withUnsafeBytes(of: &longitude) { Array($0) })

        var elevationValue = elevation.littleEndian
        let cellBytes = withUnsafeBytes(of: &elevationValue) { Array($0) }
        for _ in 0..<(latCells * lonCells) {
            data.append(contentsOf: cellBytes)
        }

        return data
    }

    private func makeCountingGrid(counter: inout Int, elevation: Int16) -> ElevationGridData? {
        defer { counter += 1 }
        return makeElevationGrid(latCells: 2, lonCells: 4, elevation: elevation)
    }

    private func makeElevationGrid(latCells: Int, lonCells: Int, elevation: Int16) -> ElevationGridData? {
        ElevationGridData(data: makeElevationVersion1Data(latCells: latCells, lonCells: lonCells, elevation: elevation))
    }

    private func makeElevationGrid(latCells: Int, lonCells: Int, elevations: [Int16]) -> ElevationGridData? {
        XCTAssertEqual(elevations.count, latCells * lonCells)

        var data = Data()
        data.append(contentsOf: [0x45, 0x4C, 0x45, 0x56])

        var version = Int32(1).littleEndian
        data.append(contentsOf: withUnsafeBytes(of: &version) { Array($0) })

        var latitude = Int32(latCells).littleEndian
        data.append(contentsOf: withUnsafeBytes(of: &latitude) { Array($0) })

        var longitude = Int32(lonCells).littleEndian
        data.append(contentsOf: withUnsafeBytes(of: &longitude) { Array($0) })

        for elevation in elevations {
            var elevationValue = elevation.littleEndian
            data.append(contentsOf: withUnsafeBytes(of: &elevationValue) { Array($0) })
        }

        return ElevationGridData(data: data)
    }

    /// Version 2 (領域限定) 標高グリッドを生成するヘルパー。
    private func makeVersion2Grid(
        latMin: Float, latMax: Float, lonMin: Float, lonMax: Float,
        latCells: Int, lonCells: Int, elevation: Int16
    ) -> ElevationGridData? {
        var data = Data()
        data.append(contentsOf: [0x45, 0x4C, 0x45, 0x56])  // "ELEV"

        var version = UInt32(2).littleEndian
        data.append(contentsOf: withUnsafeBytes(of: &version) { Array($0) })

        var latC = Int32(latCells).littleEndian
        data.append(contentsOf: withUnsafeBytes(of: &latC) { Array($0) })

        var lonC = Int32(lonCells).littleEndian
        data.append(contentsOf: withUnsafeBytes(of: &lonC) { Array($0) })

        var latMinVal = latMin
        data.append(contentsOf: withUnsafeBytes(of: &latMinVal) { Array($0) })
        var latMaxVal = latMax
        data.append(contentsOf: withUnsafeBytes(of: &latMaxVal) { Array($0) })
        var lonMinVal = lonMin
        data.append(contentsOf: withUnsafeBytes(of: &lonMinVal) { Array($0) })
        var lonMaxVal = lonMax
        data.append(contentsOf: withUnsafeBytes(of: &lonMaxVal) { Array($0) })

        var elevationValue = elevation.littleEndian
        let cellBytes = withUnsafeBytes(of: &elevationValue) { Array($0) }
        for _ in 0..<(latCells * lonCells) {
            data.append(contentsOf: cellBytes)
        }

        return ElevationGridData(data: data)
    }
}
