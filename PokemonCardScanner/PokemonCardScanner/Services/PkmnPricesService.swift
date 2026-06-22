import Foundation

enum PkmnPricesServiceError: LocalizedError {
  case missingAPIKey
  case cardNotFound
  case networkError(Error)
  case decodingError

  var errorDescription: String? {
    switch self {
    case .missingAPIKey:
      return "Add your PkmnPrices API key in APIConfiguration.swift for graded prices."
    case .cardNotFound:
      return "Card not found in PkmnPrices database."
    case .networkError(let error):
      return error.localizedDescription
    case .decodingError:
      return "Could not read graded price data."
    }
  }
}

actor PkmnPricesService {
  static let shared = PkmnPricesService()

  private let baseURL = "https://api.pkmnprices.com/v1"
  private let session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
  }

  func resolveCardID(for card: PokemonCard) async throws -> Int {
    guard APIConfiguration.hasValidPkmnPricesKey else {
      throw PkmnPricesServiceError.missingAPIKey
    }

    guard var components = URLComponents(string: "\(baseURL)/cards") else {
      throw PkmnPricesServiceError.networkError(URLError(.badURL))
    }

    components.queryItems = [
      URLQueryItem(name: "name", value: card.name),
      URLQueryItem(name: "number", value: card.number),
      URLQueryItem(name: "per_page", value: "5"),
    ]

    let response: PkmnPricesListResponse<PkmnPricesCardSummary> = try await get(components.url!)
    guard let match = response.data.first else {
      throw PkmnPricesServiceError.cardNotFound
    }
    return match.id
  }

  func fetchGradedPrices(for card: PokemonCard) async throws -> [GradedPriceTier] {
    let cardID = try await resolveCardID(for: card)

    return await withTaskGroup(of: GradedPriceTier?.self) { group in
      for tier in GradedTierQuery.allCases {
        group.addTask {
          await self.fetchTier(cardID: cardID, tier: tier)
        }
      }

      var tiers: [GradedPriceTier] = []
      for await tier in group {
        if let tier, tier.saleCount > 0 { tiers.append(tier) }
      }
      return tiers.sorted { ($0.averagePrice ?? 0) > ($1.averagePrice ?? 0) }
    }
  }

  func fetchPriceHistory(for card: PokemonCard, period: String = "90d") async throws -> [PriceHistoryPoint] {
    let cardID = try await resolveCardID(for: card)

    guard var components = URLComponents(string: "\(baseURL)/cards/\(cardID)/prices/history")
    else {
      throw PkmnPricesServiceError.networkError(URLError(.badURL))
    }
    components.queryItems = [
      URLQueryItem(name: "currency", value: "usd"),
      URLQueryItem(name: "period", value: period),
      URLQueryItem(name: "limit", value: "90"),
    ]

    let response: PkmnPricesListResponse<PkmnPricesHistoryPoint> = try await get(components.url!)

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")

    return response.data.compactMap { point in
      guard let date = formatter.date(from: point.date) else { return nil }
      return PriceHistoryPoint(
        id: point.date,
        date: date,
        average: point.avg,
        low: point.low,
        high: point.high,
        saleCount: point.sale_count
      )
    }
    .sorted { $0.date < $1.date }
  }

  private func fetchTier(cardID: Int, tier: GradedTierQuery) async -> GradedPriceTier? {
    guard var components = URLComponents(string: "\(baseURL)/cards/\(cardID)/listings/ebay")
    else { return nil }

    components.queryItems = [
      URLQueryItem(name: "grader", value: tier.grader),
      URLQueryItem(name: "grade", value: tier.grade),
      URLQueryItem(name: "limit", value: "10"),
      URLQueryItem(name: "sort", value: "date_desc"),
    ]

    guard let url = components.url else { return nil }

    do {
      let response: PkmnPricesCursorResponse<PkmnPricesEbayListing> = try await get(url)
      let sales = response.data.map {
        GradedSale(
          id: $0.id,
          title: $0.title,
          price: $0.price,
          grader: $0.grader,
          grade: $0.grade,
          soldAt: $0.sold_at,
          listingURL: $0.listing_url
        )
      }
      guard !sales.isEmpty else { return nil }

      let prices = sales.map(\.price).sorted()
      let average = prices.reduce(0, +) / Double(prices.count)
      let median = prices[prices.count / 2]

      return GradedPriceTier(
        id: "\(tier.grader)-\(tier.grade)",
        grader: tier.grader,
        grade: tier.grade,
        averagePrice: average,
        medianPrice: median,
        saleCount: sales.count,
        recentSales: sales
      )
    } catch {
      return nil
    }
  }

  private func get<T: Decodable>(_ url: URL) async throws -> T {
    var request = URLRequest(url: url)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(APIConfiguration.pkmnPricesAPIKey, forHTTPHeaderField: "X-API-Key")

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      throw PkmnPricesServiceError.networkError(error)
    }

    guard let http = response as? HTTPURLResponse else {
      throw PkmnPricesServiceError.networkError(URLError(.badServerResponse))
    }

    if http.statusCode == 401 || http.statusCode == 403 {
      throw PkmnPricesServiceError.missingAPIKey
    }

    guard (200...299).contains(http.statusCode) else {
      throw PkmnPricesServiceError.networkError(URLError(.badServerResponse))
    }

    do {
      return try JSONDecoder().decode(T.self, from: data)
    } catch {
      throw PkmnPricesServiceError.decodingError
    }
  }
}

// MARK: - API response types

private struct PkmnPricesListResponse<T: Decodable>: Decodable {
  let data: [T]
}

private struct PkmnPricesCursorResponse<T: Decodable>: Decodable {
  let data: [T]
}

private struct PkmnPricesCardSummary: Decodable {
  let id: Int
  let name: String
  let number: String?
}

private struct PkmnPricesEbayListing: Decodable {
  let id: Int
  let title: String
  let price: Double
  let grader: String?
  let grade: String?
  let sold_at: String?
  let listing_url: String?
}

private struct PkmnPricesHistoryPoint: Decodable {
  let date: String
  let avg: Double
  let low: Double?
  let high: Double?
  let sale_count: Int?
}
