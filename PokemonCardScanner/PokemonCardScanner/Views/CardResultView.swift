import SwiftUI

struct CardResultView: View {
  let card: PokemonCard
  let onDismiss: () -> Void

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 20) {
          AsyncImage(url: URL(string: card.images.large)) { phase in
            switch phase {
            case .success(let image):
              image
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 8)
            case .failure:
              placeholder
            default:
              ProgressView()
                .frame(height: 280)
            }
          }
          .frame(maxHeight: 360)
          .padding(.horizontal)

          VStack(spacing: 8) {
            Text(card.name)
              .font(.title2.bold())
              .multilineTextAlignment(.center)

            Text("\(card.set.name) · #\(card.number)")
              .font(.subheadline)
              .foregroundStyle(.secondary)

            if let rarity = card.rarity {
              Text(rarity)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
            }
          }

          priceSection

          if let urlString = card.tcgplayer?.url, let url = URL(string: urlString) {
            Link("View on TCGPlayer", destination: url)
              .font(.subheadline)
          }

          Text("Prices are market estimates from TCGPlayer and change frequently. Condition, grading, and language affect real sale value.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
        }
        .padding(.vertical)
      }
      .navigationTitle("Card Value")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done", action: onDismiss)
        }
      }
    }
  }

  private var placeholder: some View {
    RoundedRectangle(cornerRadius: 12)
      .fill(.quaternary)
      .frame(height: 280)
      .overlay {
        Image(systemName: "photo")
          .font(.largeTitle)
          .foregroundStyle(.secondary)
      }
  }

  @ViewBuilder
  private var priceSection: some View {
    if let market = card.bestMarketPrice {
      VStack(spacing: 12) {
        Text("Estimated Market Value")
          .font(.subheadline)
          .foregroundStyle(.secondary)

        Text(String(format: "$%.2f", market))
          .font(.system(size: 44, weight: .bold, design: .rounded))
          .foregroundStyle(.green)

        if !card.priceBreakdown.isEmpty {
          VStack(spacing: 6) {
            ForEach(card.priceBreakdown, id: \.label) { item in
              if let value = item.market {
                HStack {
                  Text(item.label)
                  Spacer()
                  Text(String(format: "$%.2f", value))
                    .monospacedDigit()
                }
                .font(.subheadline)
              }
            }
          }
          .padding()
          .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
          .padding(.horizontal)
        }
      }
    } else {
      Label("No pricing data available for this card", systemImage: "exclamationmark.triangle")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding()
    }
  }
}

#Preview {
  CardResultView(
    card: PokemonCard(
      id: "base1-4",
      name: "Charizard",
      number: "4",
      rarity: "Rare Holo",
      set: .init(id: "base1", name: "Base Set", series: "Base", releaseDate: "1999/01/09"),
      images: .init(
        small: "https://images.pokemontcg.io/base1/4.png",
        large: "https://images.pokemontcg.io/base1/4_hires.png"
      ),
      tcgplayer: .init(
        url: "https://prices.pokemontcg.io/tcgplayer/base1-4",
        updatedAt: "2024/01/01",
        prices: ["holofoil": .init(low: 250, mid: 350, high: 500, market: 320, directLow: nil)]
      )
    ),
    onDismiss: {}
  )
}
