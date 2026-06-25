import Foundation

enum PokemonTCGServiceError: LocalizedError {
  case invalidURL
  case noResults
  case networkError(Error)
  case decodingError(Error)

  var errorDescription: String? {
    switch self {
    case .invalidURL:
      return "Could not build search URL."
    case .noResults:
      return "No matching cards found. Try holding the card steadier or improving lighting."
    case .networkError(let error):
      return "Network error: \(error.localizedDescription)"
    case .decodingError:
      return "Could not read card data from the server."
    }
  }
}

actor PokemonTCGService {
  static let shared = PokemonTCGService()

  private let baseURL = "https://api.pokemontcg.io/v2"
  private let session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
  }

  func searchCards(name: String, collectorNumber: String? = nil) async throws -> [PokemonCard] {
    try await searchWithFallbacks(
      candidates: [
        RecognizedCardText(
          candidateName: name,
          collectorNumber: collectorNumber,
          confidence: 1
        )
      ]
    )
  }

  /// Tries exact, wildcard, and partial name searches until something matches.
  func searchWithFallbacks(candidates: [RecognizedCardText]) async throws -> [PokemonCard] {
    var tried = Set<String>()

    for candidate in candidates {
      let name = sanitizeQuery(candidate.candidateName)
      guard !name.isEmpty else { continue }

      let strategies = searchQueries(for: name, collectorNumber: candidate.collectorNumber)

      for query in strategies {
        guard !tried.contains(query) else { continue }
        tried.insert(query)

        if let cards = try? await fetchCards(query: query), !cards.isEmpty {
          return cards
        }
      }
    }

    throw PokemonTCGServiceError.noResults
  }

  private func searchQueries(for name: String, collectorNumber: String?) -> [String] {
    let words = name.split(separator: " ").map(String.init)
    let firstWord = words.first ?? name
    let wildcard = firstWord.count >= 3 ? String(firstWord.prefix(3)) : firstWord

    var queries: [String] = []

    if let collectorNumber, let number = extractCardNumber(from: collectorNumber) {
      queries.append("name:\"\(name)\" number:\(number)")
      queries.append("name:\(wildcard)* number:\(number)")
      queries.append("number:\(number)")
    }

    queries.append("name:\"\(name)\"")
    queries.append("name:\(wildcard)*")

    if words.count > 1 {
      queries.append("name:\"\(words.prefix(2).joined(separator: " "))\"")
    }

    return queries
  }

  private func fetchCards(query: String) async throws -> [PokemonCard] {
    guard var components = URLComponents(string: "\(baseURL)/cards") else {
      throw PokemonTCGServiceError.invalidURL
    }

    components.queryItems = [
      URLQueryItem(name: "q", value: query),
      URLQueryItem(name: "pageSize", value: "15"),
      URLQueryItem(name: "orderBy", value: "-set.releaseDate"),
    ]

    guard let url = components.url else {
      throw PokemonTCGServiceError.invalidURL
    }

    var request = URLRequest(url: url)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if APIConfiguration.hasValidAPIKey {
      request.setValue(APIConfiguration.pokemonTCGAPIKey, forHTTPHeaderField: "X-Api-Key")
    }

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      throw PokemonTCGServiceError.networkError(error)
    }

    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
      throw PokemonTCGServiceError.networkError(URLError(.badServerResponse))
    }

    let decoded: CardsSearchResponse
    do {
      decoded = try JSONDecoder().decode(CardsSearchResponse.self, from: data)
    } catch {
      throw PokemonTCGServiceError.decodingError(error)
    }

    return decoded.data
  }

  private func sanitizeQuery(_ text: String) -> String {
    text
      .replacingOccurrences(of: "\"", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func extractCardNumber(from text: String) -> String? {
    let pattern = #"(\d{1,4})"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
      let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
      let range = Range(match.range(at: 1), in: text)
    else { return nil }
    return String(text[range])
  }
}
