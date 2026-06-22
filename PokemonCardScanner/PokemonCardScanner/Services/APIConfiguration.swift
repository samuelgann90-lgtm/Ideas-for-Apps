import Foundation

enum APIConfiguration {
  /// Free API key from https://dev.pokemontcg.io
  static let pokemonTCGAPIKey = "YOUR_API_KEY_HERE"

  /// Free API key from https://pkmnprices.com (100 credits/day — graded prices & history)
  static let pkmnPricesAPIKey = "YOUR_PKMNPRICES_KEY_HERE"

  static var hasValidAPIKey: Bool {
    !pokemonTCGAPIKey.isEmpty && pokemonTCGAPIKey != "YOUR_API_KEY_HERE"
  }

  static var hasValidPkmnPricesKey: Bool {
    !pkmnPricesAPIKey.isEmpty && pkmnPricesAPIKey != "YOUR_PKMNPRICES_KEY_HERE"
  }
}
