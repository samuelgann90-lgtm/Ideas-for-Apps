import Foundation

struct PokemonCard: Identifiable, Decodable, Hashable {
  let id: String
  let name: String
  let number: String
  let rarity: String?
  let set: CardSet
  let images: CardImages
  let tcgplayer: TCGPlayerInfo?

  struct CardSet: Decodable, Hashable {
    let id: String
    let name: String
    let series: String?
    let releaseDate: String?
  }

  struct CardImages: Decodable, Hashable {
    let small: String
    let large: String
  }

  struct TCGPlayerInfo: Decodable, Hashable {
    let url: String?
    let updatedAt: String?
    let prices: [String: PriceVariant]?
  }

  struct PriceVariant: Decodable, Hashable {
    let low: Double?
    let mid: Double?
    let high: Double?
    let market: Double?
    let directLow: Double?
  }

  var bestMarketPrice: Double? {
    guard let prices = tcgplayer?.prices else { return nil }
    return prices.values.compactMap(\.market).max()
      ?? prices.values.compactMap(\.mid).max()
  }

  var formattedPrice: String {
    guard let price = bestMarketPrice else { return "Price unavailable" }
    return String(format: "$%.2f", price)
  }

  var priceBreakdown: [(label: String, market: Double?)] {
    guard let prices = tcgplayer?.prices else { return [] }
    return prices
      .sorted { $0.key < $1.key }
      .map { (label: $0.key.capitalized, market: $0.value.market) }
  }
}

struct CardsSearchResponse: Decodable {
  let data: [PokemonCard]
  let totalCount: Int
}
