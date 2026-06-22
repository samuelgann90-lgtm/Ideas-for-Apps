import SwiftUI
import SwiftData

struct CollectionView: View {
  @Environment(\.modelContext) private var modelContext
  @Query(sort: \CollectedCard.addedAt, order: .reverse) private var cards: [CollectedCard]

  @State private var selectedCard: PokemonCard?
  @State private var showCardDetail = false

  private var totalValue: Double {
    cards.reduce(0) { $0 + $1.lineValue }
  }

  private var totalCards: Int {
    cards.reduce(0) { $0 + $1.quantity }
  }

  var body: some View {
    NavigationStack {
      Group {
        if cards.isEmpty {
          ContentUnavailableView {
            Label("No Cards Yet", systemImage: "square.stack.3d.up.slash")
          } description: {
            Text("Scan a card and tap \"Add to Collection\" to start tracking your portfolio.")
          }
        } else {
          List {
            Section {
              portfolioHeader
            }

            Section("Your Cards") {
              ForEach(cards) { entry in
                collectionRow(entry)
              }
              .onDelete(perform: deleteCards)
            }
          }
        }
      }
      .navigationTitle("Collection")
      .sheet(isPresented: $showCardDetail) {
        if let card = selectedCard {
          CardResultView(card: card, matchSimilarity: nil) {
            showCardDetail = false
          }
        }
      }
    }
  }

  private var portfolioHeader: some View {
    VStack(spacing: 12) {
      Text("Portfolio Value")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      Text(String(format: "$%.2f", totalValue))
        .font(.system(size: 40, weight: .bold, design: .rounded))
        .foregroundStyle(.green)

      HStack(spacing: 24) {
        statItem(value: "\(totalCards)", label: "Cards")
        statItem(value: "\(cards.count)", label: "Unique")
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 8)
  }

  private func statItem(value: String, label: String) -> some View {
    VStack(spacing: 2) {
      Text(value)
        .font(.title3.weight(.semibold))
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private func collectionRow(_ entry: CollectedCard) -> some View {
    HStack(spacing: 12) {
      AsyncImage(url: URL(string: entry.imageURL)) { image in
        image.resizable().scaledToFit()
      } placeholder: {
        Color.gray.opacity(0.2)
      }
      .frame(width: 44, height: 62)
      .clipShape(RoundedRectangle(cornerRadius: 4))

      VStack(alignment: .leading, spacing: 4) {
        Text(entry.name)
          .font(.headline)
          .lineLimit(1)
        Text("\(entry.setName) · #\(entry.cardNumber)")
          .font(.caption)
          .foregroundStyle(.secondary)
        Text("Added \(entry.addedAt.formatted(date: .abbreviated, time: .omitted))")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }

      Spacer()

      VStack(alignment: .trailing, spacing: 6) {
        Text(entry.formattedLineValue)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.green)

        Stepper(value: binding(for: entry), in: 1...99) {
          Text("×\(entry.quantity)")
            .font(.caption)
            .monospacedDigit()
        }
        .labelsHidden()
      }
    }
    .contentShape(Rectangle())
    .onTapGesture {
      openDetail(for: entry)
    }
  }

  private func binding(for entry: CollectedCard) -> Binding<Int> {
    Binding(
      get: { entry.quantity },
      set: { entry.quantity = $0 }
    )
  }

  private func openDetail(for entry: CollectedCard) {
    selectedCard = PokemonCard(
      id: entry.pokemonCardId,
      name: entry.name,
      number: entry.cardNumber,
      rarity: entry.rarity,
      set: .init(id: "", name: entry.setName, series: nil, releaseDate: nil),
      images: .init(small: entry.imageURL, large: entry.imageURL),
      tcgplayer: .init(
        url: nil,
        updatedAt: nil,
        prices: ["normal": .init(
          low: nil,
          mid: nil,
          high: nil,
          market: entry.priceAtCollection,
          directLow: nil
        )]
      )
    )
    showCardDetail = true
  }

  private func deleteCards(at offsets: IndexSet) {
    for index in offsets {
      modelContext.delete(cards[index])
    }
  }
}

#Preview {
  CollectionView()
    .modelContainer(for: CollectedCard.self, inMemory: true)
}
