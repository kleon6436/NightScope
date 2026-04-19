import Foundation
import CoreLocation

protocol NightCalculating: Sendable {
    func calculateNightSummary(
        date: Date,
        location: CLLocationCoordinate2D,
        timeZone: TimeZone
    ) async -> NightSummary
    func calculateUpcomingNights(
        from date: Date,
        location: CLLocationCoordinate2D,
        timeZone: TimeZone,
        days: Int
    ) async -> [NightSummary]
}

/// 天文計算をバックグラウンドで実行するサービス。
/// MilkyWayCalculator の static 呼び出しをラップし、
/// AppController がメインスレッドをブロックせずに await できるようにする。
final class NightCalculationService: NightCalculating, Sendable {
    private let summaryCalculator: @Sendable (Date, CLLocationCoordinate2D, TimeZone) -> NightSummary

    init(
        summaryCalculator: @escaping @Sendable (Date, CLLocationCoordinate2D, TimeZone) -> NightSummary = {
            MilkyWayCalculator.calculateNightSummary(date: $0, location: $1, timeZone: $2)
        }
    ) {
        self.summaryCalculator = summaryCalculator
    }

    func calculateNightSummary(
        date: Date,
        location: CLLocationCoordinate2D,
        timeZone: TimeZone
    ) async -> NightSummary {
        let calculator = summaryCalculator
        return await Task(priority: .userInitiated) {
            calculator(date, location, timeZone)
        }.value
    }

    func calculateUpcomingNights(
        from date: Date,
        location: CLLocationCoordinate2D,
        timeZone: TimeZone,
        days: Int = 7
    ) async -> [NightSummary] {
        await withTaskGroup(of: [NightSummary].self) { group in
            group.addTask(priority: .background) { [summaryCalculator] in
                var summaries: [NightSummary] = []
                summaries.reserveCapacity(days)
                let calendar = ObservationTimeZone.gregorianCalendar(timeZone: timeZone)
                let observationDate = calendar.startOfDay(for: date)

                for offset in 0..<days {
                    guard !Task.isCancelled else { break }
                    let targetDate = calendar.date(byAdding: .day, value: offset, to: observationDate) ?? observationDate
                    summaries.append(summaryCalculator(targetDate, location, timeZone))
                }

                return summaries
            }
            return await group.next() ?? []
        }
    }
}
