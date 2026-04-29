import Foundation
import os

#if os(macOS)
import AppKit
import MapKit

@MainActor
final class MapSnapshotCache {
    private let cache = NSCache<NSString, NSImage>()
    private var pendingTasks: [String: Task<NSImage?, Never>] = [:]
    private let logger = Logger(subsystem: "com.nightscope", category: "MapSnapshotCache")

    init() {
        cache.countLimit = 64
    }

    func snapshot(
        latitude: Double,
        longitude: Double,
        sizePoints: CGSize,
        spanDegrees: Double
    ) async -> NSImage? {
        let key = cacheKey(
            latitude: latitude,
            longitude: longitude,
            sizePoints: sizePoints,
            spanDegrees: spanDegrees
        )

        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }

        if let task = pendingTasks[key] {
            return await task.value
        }

        let task = Task<NSImage?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.generateSnapshot(
                latitude: latitude,
                longitude: longitude,
                sizePoints: sizePoints,
                spanDegrees: spanDegrees
            )
        }

        pendingTasks[key] = task
        defer { pendingTasks[key] = nil }

        let image = await task.value
        if let image {
            cache.setObject(image, forKey: key as NSString)
        }
        return image
    }

    private func generateSnapshot(
        latitude: Double,
        longitude: Double,
        sizePoints: CGSize,
        spanDegrees: Double
    ) async -> NSImage? {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            span: MKCoordinateSpan(latitudeDelta: spanDegrees, longitudeDelta: spanDegrees)
        )
        options.size = sizePoints
        options.mapType = .standard
        options.pointOfInterestFilter = .excludingAll

        let snapshotter = MKMapSnapshotter(options: options)
        return await withTaskCancellationHandler(
            operation: {
                await withCheckedContinuation { continuation in
                    snapshotter.start { snapshot, error in
                        if let snapshot {
                            continuation.resume(returning: snapshot.image)
                            return
                        }

                        if let error {
                            self.logger.error("Map snapshot generation failed: \(error.localizedDescription, privacy: .public)")
                        } else {
                            self.logger.error("Map snapshot generation failed")
                        }
                        continuation.resume(returning: nil)
                    }
                }
            },
            onCancel: {
                snapshotter.cancel()
            }
        )
    }

    private func cacheKey(
        latitude: Double,
        longitude: Double,
        sizePoints: CGSize,
        spanDegrees: Double
    ) -> String {
        "\(latitude.bitPattern)_\(longitude.bitPattern)_\(Int(sizePoints.width))x\(Int(sizePoints.height))_\(spanDegrees.bitPattern)"
    }
}
#endif
