import SwiftUI
import CoreLocation
import MapKit

enum IOSPreviewDetailState {
    case loading
    case empty
    case content
}

enum IOSPreviewLocationState {
    case loading
    case empty
    case content
}

@MainActor
enum IOSPreviewFactory {
    static func detailViewModel(for state: IOSPreviewDetailState) -> DetailViewModel {
        let appController = AppController()
        let date = previewDate
        appController.selectedDate = date
        appController.locationController.locationName = "富士山五合目"
        appController.locationController.selectedLocation = previewCoordinate

        switch state {
        case .loading:
            appController.isCalculating = true
            appController.nightSummary = nil
            appController.starGazingIndex = nil
            appController.upcomingNights = []
            appController.upcomingIndexes = [:]
            appController.weatherService.weatherByDate = [:]

        case .empty:
            appController.isCalculating = false
            appController.nightSummary = nil
            appController.starGazingIndex = nil
            appController.upcomingNights = []
            appController.upcomingIndexes = [:]
            appController.weatherService.weatherByDate = [:]

        case .content:
            appController.isCalculating = false
            appController.lightPollutionService.bortleClass = 3.5

            let tonightSummary = makeNightSummary(date: date, hasViewingWindow: true)
            let tonightWeather = makeWeatherSummary(date: date, avgCloudCover: 22, weatherCode: 1)

            appController.nightSummary = tonightSummary
            appController.weatherService.weatherByDate = [
                dateKey(for: date): tonightWeather
            ]
            appController.starGazingIndex = StarGazingIndex.compute(
                nightSummary: tonightSummary,
                weather: tonightWeather,
                bortleClass: appController.lightPollutionService.bortleClass
            )

            let upcomingNights = makeUpcomingNights(from: date)
            appController.upcomingNights = upcomingNights

            var upcomingIndexes: [Date: StarGazingIndex] = [:]
            for (offset, night) in upcomingNights.enumerated() {
                let weather = makeWeatherSummary(
                    date: night.date,
                    avgCloudCover: Double(18 + offset * 10),
                    weatherCode: offset == 2 ? 3 : 1
                )
                appController.weatherService.weatherByDate[dateKey(for: night.date)] = weather
                upcomingIndexes[Calendar.current.startOfDay(for: night.date)] = StarGazingIndex.compute(
                    nightSummary: night,
                    weather: weather,
                    bortleClass: appController.lightPollutionService.bortleClass
                )
            }
            appController.upcomingIndexes = upcomingIndexes
        }

        return DetailViewModel(appController: appController)
    }

    static func sidebarViewModel(for state: IOSPreviewLocationState) -> SidebarViewModel {
        let locationController = LocationController()
        let lightPollutionService = LightPollutionService()
        let sidebarViewModel = SidebarViewModel(
            locationController: locationController,
            lightPollutionService: lightPollutionService
        )

        switch state {
        case .loading:
            locationController.isLocating = true
            locationController.locationName = ""
            locationController.searchResults = []

        case .empty:
            locationController.isLocating = false
            locationController.locationName = ""
            locationController.searchResults = []

        case .content:
            locationController.isLocating = false
            locationController.selectedLocation = previewCoordinate
            locationController.locationName = "富士山五合目"
            sidebarViewModel.searchText = "富士山"
            locationController.searchResults = [
                makeMapItem(name: "富士山五合目", latitude: 35.3606, longitude: 138.7274),
                makeMapItem(name: "河口湖", latitude: 35.4983, longitude: 138.7681)
            ]
            lightPollutionService.bortleClass = 3
        }

        return sidebarViewModel
    }

    private static var previewDate: Date {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .hour, value: 21, to: startOfDay) ?? Date()
    }

    private static var previewCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: 35.3606, longitude: 138.7274)
    }

    private static func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    private static func makeMapItem(name: String, latitude: Double, longitude: Double) -> MKMapItem {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let mapItem = MKMapItem(location: location, address: nil)
        mapItem.name = name
        return mapItem
    }

    private static func makeUpcomingNights(from baseDate: Date) -> [NightSummary] {
        let calendar = Calendar.current
        return (0..<5).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: baseDate) else {
                return nil
            }
            return makeNightSummary(date: date, hasViewingWindow: true)
        }
    }

    private static func makeNightSummary(date: Date, hasViewingWindow: Bool) -> NightSummary {
        let calendar = Calendar.current
        let eventDate = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: date) ?? date

        let event = AstroEvent(
            date: eventDate,
            galacticCenterAltitude: 32,
            galacticCenterAzimuth: 188,
            sunAltitude: -22,
            moonAltitude: -6,
            moonPhase: 0.18
        )

        let windows: [ViewingWindow] = hasViewingWindow ? [
            ViewingWindow(
                start: eventDate,
                end: eventDate.addingTimeInterval(2 * 3600),
                peakTime: eventDate.addingTimeInterval(3600),
                peakAltitude: 38,
                peakAzimuth: 190
            )
        ] : []

        return NightSummary(
            date: date,
            location: previewCoordinate,
            events: [event],
            viewingWindows: windows,
            moonPhaseAtMidnight: 0.18
        )
    }

    private static func makeWeatherSummary(date: Date, avgCloudCover: Double, weatherCode: Int) -> DayWeatherSummary {
        let calendar = Calendar.current
        let hour21 = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: date) ?? date
        let hour23 = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: date) ?? date

        let nighttimeHours = [
            HourlyWeather(
                date: hour21,
                temperatureCelsius: 9,
                cloudCoverPercent: avgCloudCover,
                precipitationMM: 0,
                windSpeedKmh: 8,
                humidityPercent: 55,
                dewpointCelsius: 2,
                weatherCode: weatherCode,
                visibilityMeters: 22000,
                windGustsKmh: 15,
                windSpeedKmh500hpa: 28
            ),
            HourlyWeather(
                date: hour23,
                temperatureCelsius: 7,
                cloudCoverPercent: avgCloudCover,
                precipitationMM: 0,
                windSpeedKmh: 7,
                humidityPercent: 58,
                dewpointCelsius: 1,
                weatherCode: weatherCode,
                visibilityMeters: 24000,
                windGustsKmh: 14,
                windSpeedKmh500hpa: 26
            )
        ]

        return DayWeatherSummary(date: date, nighttimeHours: nighttimeHours)
    }
}
