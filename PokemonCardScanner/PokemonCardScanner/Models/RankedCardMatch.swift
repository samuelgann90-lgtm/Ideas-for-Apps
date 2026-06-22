import Foundation

struct RankedCardMatch: Identifiable, Hashable {
  let card: PokemonCard
  /// Visual similarity score from 0–100 (higher = better match).
  let similarity: Float
  let visualDistance: Float

  var id: String { card.id }

  var similarityLabel: String {
    String(format: "%.0f%% match", similarity)
  }
}
