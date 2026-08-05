import SwiftUI

@MainActor
@Observable
class RecommendationsStore {
    static let shared = RecommendationsStore()

    var recommendations: [RecommendationsView.Recommendation] = []
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var lastGenerated: Date? = nil
}
