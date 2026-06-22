import Foundation

enum APIConfiguration {
  /// Free API key from https://dev.pokemontcg.io
  /// Replace with your key for higher rate limits in production.
  static let pokemonTCGAPIKey = "YOUR_API_KEY_HERE"

  static var hasValidAPIKey: Bool {
    !pokemonTCGAPIKey.isEmpty && pokemonTCGAPIKey != "YOUR_API_KEY_HERE"
  }
}
