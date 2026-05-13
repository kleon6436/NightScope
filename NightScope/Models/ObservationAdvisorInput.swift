import Foundation

struct ObservationAdvisorInput: Sendable, Equatable {
    let language: String
    let isUnfavorable: Bool
    let dateString: String
    let locationName: String
    let tierLabel: String
    let viewingWindowSummary: String
    let moonSummary: String
    let weatherSummary: String
    let lightPollutionSummary: String
}
