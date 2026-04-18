import XCTest
@testable import NightScope

final class TerrainServiceTests: XCTestCase {

    func test_fetchProfile_noBundleData_returnsNil() async {
        let service = TerrainService(elevationData: nil)
        let profile = await service.fetchProfile(latitude: 35.0, longitude: 139.0)
        XCTAssertNil(profile, "バンドルデータなしでは nil を返すはず")
    }

    func test_fetchProfile_withBundleData_returns72Angles() async {
        let grid = makeUniformGrid(elevation: 100)
        let service = TerrainService(elevationData: grid)
        let profile = await service.fetchProfile(latitude: 35.0, longitude: 139.0)
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.horizonAngles.count, 72)
    }

    func test_fetchProfile_uniformTerrain_allAnglesNearZero() async {
        let grid = makeUniformGrid(elevation: 500)
        let service = TerrainService(elevationData: grid)
        let profile = await service.fetchProfile(latitude: 0, longitude: 0)
        for angle in profile?.horizonAngles ?? [] {
            XCTAssertEqual(angle, 0, accuracy: 0.001, "一様地形では地平仰角はほぼ 0 のはず")
        }
    }

    func test_fetchProfile_cachesSameRoundedCoordinate() async {
        var computeCount = 0
        let grid = makeCountingGrid(counter: &computeCount, elevation: 0)
        let service = TerrainService(elevationData: grid)

        _ = await service.fetchProfile(latitude: 35.1234, longitude: 139.5678)
        let countAfterFirst = computeCount

        _ = await service.fetchProfile(latitude: 35.1239, longitude: 139.5671)
        let countAfterSecond = computeCount

        XCTAssertEqual(countAfterFirst, countAfterSecond, "キャッシュがヒットすれば再計算されないはず")
    }

    func test_fetchProfile_wrapsLongitudeAcrossDateLine() async {
        let grid = makeSRTMGrid(
            latCells: 2,
            lonCells: 4,
            elevations: [
                0, 0, 0, 0,
                600, 0, 0, 100
            ]
        )
        let service = TerrainService(elevationData: grid)

        let profile = await service.fetchProfile(latitude: 0, longitude: 179.95)

        guard let eastAngle = profile?.horizonAngles.first else {
            return XCTFail("地平プロファイルを取得できませんでした")
        }
        XCTAssertGreaterThan(eastAngle, 0.0, "日付変更線を跨いでも東方向の地形を拾うはず")
    }

    private func makeUniformGrid(elevation: Int16) -> ElevationGridData? {
        makeSRTMGrid(latCells: 2, lonCells: 4, elevation: elevation)
    }

    private func makeCountingGrid(counter: inout Int, elevation: Int16) -> ElevationGridData? {
        defer { counter += 1 }
        return makeSRTMGrid(latCells: 2, lonCells: 4, elevation: elevation)
    }

    private func makeSRTMGrid(latCells: Int, lonCells: Int, elevation: Int16) -> ElevationGridData? {
        var data = Data()
        data.append(contentsOf: [0x53, 0x52, 0x54, 0x4D])

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

        return ElevationGridData(data: data)
    }

    private func makeSRTMGrid(latCells: Int, lonCells: Int, elevations: [Int16]) -> ElevationGridData? {
        XCTAssertEqual(elevations.count, latCells * lonCells)

        var data = Data()
        data.append(contentsOf: [0x53, 0x52, 0x54, 0x4D])

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
}
