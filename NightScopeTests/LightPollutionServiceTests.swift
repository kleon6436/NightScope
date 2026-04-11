import XCTest
import MapKit
@testable import NightScope

@MainActor
final class LightPollutionServiceTests: XCTestCase {

    func test_wa2015ToBortle_veryDarkSky_returnsBortle1() {
        let service = LightPollutionService(gridData: nil)
        XCTAssertEqual(service.wa2015ToBortle(0.001), 1.0, accuracy: 0.001)
    }

    func test_wa2015ToBortle_brightest_returnsBortle9() {
        let service = LightPollutionService(gridData: nil)
        XCTAssertEqual(service.wa2015ToBortle(5.0), 9.0, accuracy: 0.001)
    }

    func test_wa2015ToBortle_interpolation() {
        let service = LightPollutionService(gridData: nil)
        XCTAssertEqual(service.wa2015ToBortle(0.172), 6.0, accuracy: 0.01)
    }

    func test_fetch_noBundleData_setsFetchFailed() async {
        let service = LightPollutionService(gridData: nil)

        await service.fetch(latitude: 35.6762, longitude: 139.6503)

        XCTAssertTrue(service.fetchFailed)
        XCTAssertNil(service.bortleClass)
    }

    func test_fetch_withBundleData_returnsBortleValue() async {
        let grid = makeSingleCellGrid(brightness: 0.172)
        let service = LightPollutionService(gridData: grid)

        await service.fetch(latitude: 0, longitude: 0)

        XCTAssertFalse(service.fetchFailed)
        XCTAssertEqual(service.bortleClass ?? -1, 6.0, accuracy: 0.1)
    }

    func test_fetch_sameCoordinate_doesNotRefetch() async {
        let grid = makeSingleCellGrid(brightness: 0.172)
        let service = LightPollutionService(gridData: grid)

        await service.fetch(latitude: 35.0, longitude: 139.0)
        let bortle1 = service.bortleClass

        await service.fetch(latitude: 35.01, longitude: 139.01)
        let bortle2 = service.bortleClass

        XCTAssertEqual(bortle1, bortle2, "同じ座標では値が変わらないはず")
    }

    func test_renderedTile_returnsImageAndData() {
        guard let grid = makeSingleCellGrid(brightness: 0.172) else {
            XCTFail("グリッドを生成できませんでした")
            return
        }
        let path = MKTileOverlayPath(x: 0, y: 0, z: 1, contentScaleFactor: 1)

        let renderedTile = LightPollutionTileOverlay.renderedTile(path: path, grid: grid, size: 8)

        XCTAssertNotNil(renderedTile)
        XCTAssertEqual(renderedTile?.image.width, 8)
        XCTAssertEqual(renderedTile?.image.height, 8)
        XCTAssertFalse(renderedTile?.data.isEmpty ?? true)
    }

    func test_storeRenderedTile_cachesImageAndData() {
        guard let grid = makeSingleCellGrid(brightness: 0.172) else {
            XCTFail("グリッドを生成できませんでした")
            return
        }
        let path = MKTileOverlayPath(x: 0, y: 0, z: 1, contentScaleFactor: 1)
        let service = LightPollutionTileService()
        guard let renderedTile = LightPollutionTileOverlay.renderedTile(path: path, grid: grid, size: 4) else {
            XCTFail("タイルを生成できませんでした")
            return
        }

        service.storeRenderedTile(renderedTile, for: path)

        XCTAssertNotNil(service.cachedTileData(for: path))
        XCTAssertNotNil(service.cachedImage(for: path))
    }

    private func makeSingleCellGrid(brightness: Double) -> BortleGridData? {
        var data = Data()
        data.append(contentsOf: [0x42, 0x4F, 0x52, 0x54])

        var version = Int32(1).littleEndian
        data.append(contentsOf: withUnsafeBytes(of: &version) { Array($0) })

        var latCells = Int32(1).littleEndian
        data.append(contentsOf: withUnsafeBytes(of: &latCells) { Array($0) })

        var lonCells = Int32(1).littleEndian
        data.append(contentsOf: withUnsafeBytes(of: &lonCells) { Array($0) })

        var value = Float(brightness).bitPattern.littleEndian
        data.append(contentsOf: withUnsafeBytes(of: &value) { Array($0) })

        return BortleGridData(data: data)
    }

    // MARK: - v2 (zlib compressed) Format Tests

    func test_v2CompressedGrid_returnsSameValue() {
        let brightness = 0.172
        guard let v1Grid = makeSingleCellGrid(brightness: brightness) else {
            XCTFail("v1 グリッドを生成できませんでした")
            return
        }
        guard let v2Grid = makeSingleCellGridV2(brightness: brightness) else {
            XCTFail("v2 グリッドを生成できませんでした")
            return
        }

        let v1Value = v1Grid.brightness(latitude: 0, longitude: 0)
        let v2Value = v2Grid.brightness(latitude: 0, longitude: 0)

        XCTAssertEqual(v1Value, v2Value, accuracy: 1e-6, "v1 と v2 で同じ値を返すべき")
    }

    func test_v2CompressedGrid_invalidVersion_returnsNil() {
        var data = Data()
        data.append(contentsOf: [0x42, 0x4F, 0x52, 0x54])  // Magic

        var version = UInt32(99).littleEndian
        data.append(contentsOf: withUnsafeBytes(of: &version) { Array($0) })

        var latCells = Int32(1).littleEndian
        data.append(contentsOf: withUnsafeBytes(of: &latCells) { Array($0) })

        var lonCells = Int32(1).littleEndian
        data.append(contentsOf: withUnsafeBytes(of: &lonCells) { Array($0) })

        XCTAssertNil(BortleGridData(data: data))
    }

    func test_renderedTile_mercatorProjection_differsByLatitude() {
        // 高緯度タイルでメルカトル投影が正しく適用されていることを検証
        guard let grid = makeSingleCellGrid(brightness: 0.5) else {
            XCTFail("グリッドを生成できませんでした")
            return
        }
        // z=2, y=0 は北極付近のタイル
        let highLatPath = MKTileOverlayPath(x: 0, y: 0, z: 2, contentScaleFactor: 1)
        let tile = LightPollutionTileOverlay.renderedTile(path: highLatPath, grid: grid, size: 4)
        XCTAssertNotNil(tile, "高緯度タイルのレンダリングに成功するべき")
    }

    private func makeSingleCellGridV2(brightness: Double) -> BortleGridData? {
        // Float32 の生データを zlib 圧縮して v2 フォーマットで構築
        var rawFloat = Float(brightness)
        let rawBytes = withUnsafeBytes(of: &rawFloat) { Data($0) }

        guard let compressed = try? (rawBytes as NSData).compressed(using: .zlib) as Data else {
            return nil
        }

        var data = Data()
        data.append(contentsOf: [0x42, 0x4F, 0x52, 0x54])  // Magic

        var version = UInt32(2).littleEndian
        data.append(contentsOf: withUnsafeBytes(of: &version) { Array($0) })

        var latCells = Int32(1).littleEndian
        data.append(contentsOf: withUnsafeBytes(of: &latCells) { Array($0) })

        var lonCells = Int32(1).littleEndian
        data.append(contentsOf: withUnsafeBytes(of: &lonCells) { Array($0) })

        var rawSize = UInt32(rawBytes.count).littleEndian
        data.append(contentsOf: withUnsafeBytes(of: &rawSize) { Array($0) })

        data.append(compressed)

        return BortleGridData(data: data)
    }
}
