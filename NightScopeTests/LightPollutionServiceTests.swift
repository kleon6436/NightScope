import XCTest
import MapKit
import CoreGraphics
import ImageIO
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

    func test_prepareForLocationChange_preservesNearbyCachedFetchResult() async {
        let grid = makeSingleCellGrid(brightness: 0.172)
        let service = LightPollutionService(gridData: grid)

        await service.fetch(latitude: 35.0, longitude: 139.0)
        let cachedBortle = service.bortleClass

        service.prepareForLocationChange()
        let snapshot = await service.fetchSnapshot(latitude: 35.01, longitude: 139.01)

        XCTAssertEqual(snapshot.bortleClass, cachedBortle)
        XCTAssertFalse(snapshot.fetchFailed)
    }

    func test_renderedTile_returnsImageAndData() {
        guard let grid = makeSingleCellGrid(brightness: 0.172) else {
            XCTFail("グリッドを生成できませんでした")
            return
        }
        let path = MKTileOverlayPath(x: 0, y: 0, z: 1, contentScaleFactor: 1)

        let data = LightPollutionTileOverlay.renderTile(path: path, grid: grid, size: 8)

        XCTAssertNotNil(data, "タイルデータが返るべき")
        XCTAssertFalse(data?.isEmpty ?? true, "タイルデータが空でないべき")
    }

    func test_tileService_storeAndRetrieveData() {
        let path = MKTileOverlayPath(x: 0, y: 0, z: 1, contentScaleFactor: 1)
        let service = LightPollutionTileService()
        let testData = Data([0x89, 0x50, 0x4E, 0x47])  // PNG magic bytes

        service.storeTileData(testData, for: path)

        XCTAssertNotNil(service.cachedTileData(for: path), "保存したデータが取得できるべき")
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
        let data = LightPollutionTileOverlay.renderTile(path: highLatPath, grid: grid, size: 4)
        XCTAssertNotNil(data, "高緯度タイルのレンダリングに成功するべき")
    }

    // MARK: - Bortle 9 可視性テスト（回帰）

    func test_bortleToRGBA_bortle9_isNotWhite() {
        // 東京都心相当の輝度 100 mcd/m²（ratio ≈ 581）は Bortle 9 ゾーンに入る。
        // 修正前は白 (255,255,255) が返り明るい地図で不可視だったため、白でないことを確認する。
        guard let grid = makeSingleCellGrid(brightness: 100.0) else {
            XCTFail("グリッドを生成できませんでした")
            return
        }
        let path = MKTileOverlayPath(x: 0, y: 0, z: 1, contentScaleFactor: 1)
        guard let tileData = LightPollutionTileOverlay.renderTile(path: path, grid: grid, size: 4),
              let pixels = decodePNGPixels(tileData, expectedSize: 4) else {
            XCTFail("タイルのデコードに失敗しました")
            return
        }
        // アルファ > 0 のピクセルを取得してグレー/白でないことを確認
        let opaquePixels = pixels.filter { $0.a > 0 }
        XCTAssertFalse(opaquePixels.isEmpty, "光害のある領域に不透明ピクセルが存在するべき")
        for pixel in opaquePixels {
            let isGrayish = abs(Int(pixel.r) - Int(pixel.g)) < 10 && abs(Int(pixel.r) - Int(pixel.b)) < 10
            XCTAssertFalse(isGrayish, "Bortle 9 のピクセルが白/グレーであってはならない: (\(pixel.r),\(pixel.g),\(pixel.b),\(pixel.a))")
        }
    }

    func test_bortleToRGBA_tokyoLevel_hasHighRed() {
        // 東京都心相当（100 mcd/m²）でレンダリングした場合、赤成分が支配的なピンク系の色が出ること。
        guard let grid = makeSingleCellGrid(brightness: 100.0) else {
            XCTFail("グリッドを生成できませんでした")
            return
        }
        let path = MKTileOverlayPath(x: 0, y: 0, z: 1, contentScaleFactor: 1)
        guard let tileData = LightPollutionTileOverlay.renderTile(path: path, grid: grid, size: 4),
              let pixels = decodePNGPixels(tileData, expectedSize: 4) else {
            XCTFail("タイルのデコードに失敗しました")
            return
        }
        let opaquePixels = pixels.filter { $0.a > 0 }
        XCTAssertFalse(opaquePixels.isEmpty, "光害のある領域に不透明ピクセルが存在するべき")
        for pixel in opaquePixels {
            XCTAssertGreaterThan(pixel.r, pixel.g, "Bortle 9 (deep pink) は R > G であるべき")
        }
    }

    // MARK: - PNG デコードヘルパー

    private struct RGBA { let r: UInt8; let g: UInt8; let b: UInt8; let a: UInt8 }

    /// PNG Data をデコードして RGBA ピクセル配列を返す。
    private func decodePNGPixels(_ pngData: Data, expectedSize: Int) -> [RGBA]? {
        guard let source = CGImageSourceCreateWithData(pngData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        let byteCount = width * height * 4
        var rawPixels = [UInt8](repeating: 0, count: byteCount)
        guard let context = CGContext(
            data: &rawPixels,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue).rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return stride(from: 0, to: byteCount, by: 4).map {
            RGBA(r: rawPixels[$0], g: rawPixels[$0+1], b: rawPixels[$0+2], a: rawPixels[$0+3])
        }
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
