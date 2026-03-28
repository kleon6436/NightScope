import Foundation
import CoreLocation

/// 天文計算をバックグラウンドで実行するサービス。
/// MilkyWayCalculator の static 呼び出しをラップし、
/// AppController がメインスレッドをブロックせずに await できるようにする。
final class NightCalculationService {

    func calculateNightSummary(date: Date, location: CLLocationCoordinate2D) async -> NightSummary {
        await Task.detached(priority: .userInitiated) {
            MilkyWayCalculator.calculateNightSummary(date: date, location: location)
        }.value
    }

    func calculateUpcomingNights(from date: Date, location: CLLocationCoordinate2D, days: Int = 14) async -> [NightSummary] {
        await Task.detached(priority: .background) {
            MilkyWayCalculator.calculateUpcomingNights(from: date, location: location, days: days)
        }.value
    }
}
