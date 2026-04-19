import XCTest
import Combine
import CoreLocation
import MapKit
@testable import NightScope

func makeHourlyWeather(
    cloudCover: Double = 10,
    weatherCode: Int = 0,
    windSpeed: Double = 5
) -> HourlyWeather {
    HourlyWeather(
        date: Date(),
        temperatureCelsius: 15,
        cloudCoverPercent: cloudCover,
        precipitationMM: 0,
        windSpeedKmh: windSpeed,
        humidityPercent: 40,
        dewpointCelsius: 2,
        weatherCode: weatherCode,
        visibilityMeters: 20_000,
        windGustsKmh: nil,
        windSpeedKmh500hpa: nil
    )
}

func makeDayWeatherSummary(
    cloudCover: Double = 10,
    weatherCode: Int = 0,
    windSpeed: Double = 5
) -> DayWeatherSummary {
    let hour = makeHourlyWeather(cloudCover: cloudCover, weatherCode: weatherCode, windSpeed: windSpeed)
    return DayWeatherSummary(date: Date(), nighttimeHours: [hour])
}

func makeNightSummary(
    date: Date = Date(),
    withWindow: Bool = true,
    moonPhase: Double = 0.12
) -> NightSummary {
    let location = CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)
    let eventDate = Calendar.current.date(byAdding: .hour, value: 21, to: date) ?? date
    let event = AstroEvent(
        date: eventDate,
        galacticCenterAltitude: 28,
        galacticCenterAzimuth: 190,
        sunAltitude: -22,
        moonAltitude: -8,
        moonPhase: moonPhase
    )
    let windows: [ViewingWindow] = withWindow ? [
        ViewingWindow(
            start: eventDate,
            end: eventDate.addingTimeInterval(3600),
            peakTime: eventDate.addingTimeInterval(1800),
            peakAltitude: 32,
            peakAzimuth: 180
        )
    ] : []
    return NightSummary(
        date: date,
        location: location,
        events: [event],
        viewingWindows: windows,
        moonPhaseAtMidnight: moonPhase
    )
}

@MainActor
final class MockLocationController: LocationProviding {
    @Published var selectedLocation = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    @Published var locationName = ""
    @Published var searchState: LocationSearchState = .idle
    @Published var isLocating = false
    @Published var locationError: LocationController.LocationError?
    @Published var searchFocusTrigger = 0
    @Published var currentLocationCenterTrigger = 0
    @Published var selectedTimeZone: TimeZone = .current

    private(set) var locationUpdateID = UUID()

    private(set) var requestCurrentLocationCalled = false
    private(set) var prepareForSettingsRecoveryCalled = false
    private(set) var refreshAuthorizationStateCalled = false
    private(set) var searchQuery: String?
    private(set) var selectedMapItem: MKMapItem?
    private(set) var selectedCoordinateCalls: [CLLocationCoordinate2D] = []

    var searchResults: [MKMapItem] {
        get { searchState.results }
        set {
            let query = normalizedSearchQuery
            searchState = newValue.isEmpty ? (query.isEmpty ? .idle : .empty(query: query)) : .results(query: query, items: newValue)
        }
    }

    var isSearching: Bool {
        get { searchState.isSearching }
        set {
            if newValue {
                searchState = .loading(query: normalizedSearchQuery, previousResults: searchState.results)
            } else {
                let query = normalizedSearchQuery
                searchState = query.isEmpty ? .idle : .empty(query: query)
            }
        }
    }

    var selectedLocationPublisher: AnyPublisher<CLLocationCoordinate2D, Never> {
        $selectedLocation.eraseToAnyPublisher()
    }

    var locationNamePublisher: AnyPublisher<String, Never> {
        $locationName.eraseToAnyPublisher()
    }

    var searchStatePublisher: AnyPublisher<LocationSearchState, Never> {
        $searchState.eraseToAnyPublisher()
    }

    var searchResultsPublisher: AnyPublisher<[MKMapItem], Never> {
        $searchState.map(\.results).eraseToAnyPublisher()
    }

    var isSearchingPublisher: AnyPublisher<Bool, Never> {
        $searchState.map(\.isSearching).eraseToAnyPublisher()
    }

    var isLocatingPublisher: AnyPublisher<Bool, Never> {
        $isLocating.eraseToAnyPublisher()
    }

    var locationErrorPublisher: AnyPublisher<LocationController.LocationError?, Never> {
        $locationError.eraseToAnyPublisher()
    }

    var searchFocusTriggerPublisher: AnyPublisher<Int, Never> {
        $searchFocusTrigger.eraseToAnyPublisher()
    }

    var currentLocationCenterTriggerPublisher: AnyPublisher<Int, Never> {
        $currentLocationCenterTrigger.eraseToAnyPublisher()
    }

    var selectedTimeZonePublisher: AnyPublisher<TimeZone, Never> {
        $selectedTimeZone.eraseToAnyPublisher()
    }

    func requestCurrentLocation() {
        requestCurrentLocationCalled = true
    }

    func prepareForSettingsRecovery() {
        prepareForSettingsRecoveryCalled = true
    }

    func refreshAuthorizationState() {
        refreshAuthorizationStateCalled = true
    }

    func search(query: String) {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedQuery.isEmpty {
            searchQuery = query
            searchState = .idle
            return
        }
        searchQuery = query
        searchState = .loading(query: normalizedQuery, previousResults: searchState.results)
    }

    func clearSearch() {
        searchQuery = ""
        searchState = .idle
    }

    func select(_ mapItem: MKMapItem) {
        selectedMapItem = mapItem
        selectedLocation = mapItem.location.coordinate
        searchState = .idle
        currentLocationCenterTrigger += 1
        locationUpdateID = UUID()
    }

    func selectCoordinate(_ coordinate: CLLocationCoordinate2D) {
        selectedCoordinateCalls.append(coordinate)
        selectedLocation = coordinate
        searchState = .idle
        locationUpdateID = UUID()
    }

    private var normalizedSearchQuery: String {
        searchQuery?.trimmingCharacters(in: .whitespacesAndNewlines) ?? searchState.query
    }
}

@MainActor
final class MockLightPollutionService: LightPollutionProviding {
    @Published var bortleClass: Double?
    @Published var isLoading = false
    @Published var fetchFailed = false

    var bortleClassPublisher: Published<Double?>.Publisher { $bortleClass }
    var isLoadingPublisher: Published<Bool>.Publisher { $isLoading }
    var fetchFailedPublisher: Published<Bool>.Publisher { $fetchFailed }

    func fetch(latitude: Double, longitude: Double) async {
        isLoading = true
        try? await Task.sleep(nanoseconds: 1_000_000)
        isLoading = false
    }

    func fetchBortle(latitude: Double, longitude: Double) async throws -> Double {
        4.0
    }
}
