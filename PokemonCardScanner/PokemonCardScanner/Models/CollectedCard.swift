import Foundation
import SwiftData

@Model
final class CollectedCard {
  @Attribute(.unique) var persistentId: UUID
  var pokemonCardId: String
  var name: String
  var setName: String
  var cardNumber: String
  var imageURL: String
  var rarity: String?
  var priceAtCollection: Double
  var quantity: Int
  var addedAt: Date

  init(from card: PokemonCard, quantity: Int = 1) {
    self.persistentId = UUID()
    self.pokemonCardId = card.id
    self.name = card.name
    self.setName = card.set.name
    self.cardNumber = card.number
    self.imageURL = card.images.small
    self.rarity = card.rarity
    self.priceAtCollection = card.bestMarketPrice ?? 0
    self.quantity = quantity
    self.addedAt = Date()
  }

  var lineValue: Double {
    priceAtCollection * Double(quantity)
  }

  var formattedLineValue: String {
    String(format: "$%.2f", lineValue)
  }
}
