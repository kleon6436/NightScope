import SwiftUI

#if os(macOS)
import AppKit

enum StarMapCanvasMacSupport {
    static func installScrollWheelMonitor(for viewModel: StarMapViewModel) -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [viewModel] event in
            MainActor.assumeIsolated {
                let updatedFOV = StarMapCanvasProjection.zoomedFOV(
                    currentFOV: viewModel.fov,
                    scrollDeltaY: event.scrollingDeltaY,
                    preciseScrolling: event.hasPreciseScrollingDeltas
                )
                if updatedFOV != viewModel.fov {
                    viewModel.fov = updatedFOV
                }
            }
            return nil
        }
    }

    static func removeScrollWheelMonitor(_ scrollWheelMonitor: Any?) {
        guard let scrollWheelMonitor else { return }
        NSEvent.removeMonitor(scrollWheelMonitor)
    }
}
#endif
