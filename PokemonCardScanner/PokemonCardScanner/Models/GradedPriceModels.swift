import Foundation

struct GradedPriceTier: Identifiable, Hashable {
  let id: String
  let grader: String
  let grade: String
  let averagePrice: Double?
  let medianPrice: Double?
  let saleCount: Int
  let recentSales: [GradedSale]

  var label: String { "\(grader) \(grade)" }

  var formattedAverage: String {
    guard let averagePrice else { return "—" }
    return String(format: "$%.0f", averagePrice)
  }
}

struct GradedSale: Identifiable, Hashable {
  let id: Int
  let title: String
  let price: Double
  let grader: String?
  let grade: String?
  let soldAt: String?
  let listingURL: String?
}

struct PriceHistoryPoint: Identifiable, Hashable {
  let id: String
  let date: Date
  let average: Double
  let low: Double?
  let high: Double?
  let saleCount: Int?
}

/// Common graded tiers to look up via eBay sold listings.
enum GradedTierQuery: CaseIterable {
  case psa10, psa9, psa8, bgs10, bgs95, cgc10

  var grader: String {
    switch self {
    case .psa10, .psa9, .psa8: return "PSA"
    case .bgs10, .bgs95: return "BGS"
    case .cgc10: return "CGC"
    }
  }

  var grade: String {
    switch self {
    case .psa10, .bgs10, .cgc10: return "10"
    case .psa9: return "9"
    case .psa8: return "8"
    case .bgs95: return "9.5"
    }
  }

  var displayName: String {
    "\(grader) \(grade)"
  }
}
