import SwiftUI
import SwiftData

enum CollectionSortOption: String, CaseIterable, Identifiable {
  case dateAddedNewest = "Date Added (Newest)"
  case dateAddedOldest = "Date Added (Oldest)"
  case priceHighToLow = "Price: High to Low"
  case priceLowToHigh = "Price: Low to High"
  case nameAZ = "Name: A–Z"
  case nameZA = "Name: Z–A"
  case setName = "Set Name"

  var id: String { rawValue }
}

struct CollectionView: View {
  @Environment(\.modelContext) private var modelContext
  @Query(sort: \CollectedCard.addedAt, order: .reverse) private var allCards: [CollectedCard]

  @State private var sortOption: CollectionSortOption = .dateAddedNewest
  @State private var selectedCard: PokemonCard?
  @State private var showCardDetail = false

  private var cards: [CollectedCard] {
    switch sortOption {
    case .dateAddedNewest:
      return allCards.sorted { $0.addedAt > $1.addedAt }
    case .dateAddedOldest:
      return allCards.sorted { $0.addedAt < $1.addedAt }
    case .priceHighToLow:
      return allCards.sorted { $0.lineValue > $1.lineValue }
    case .priceLowToHigh:
      return allCards.sorted { $0.lineValue < $1.lineValue }
    case .nameAZ:
      return allCards.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    case .nameZA:
      return allCards.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
    case .setName:
      return allCards.sorted {
        if $0.setName == $1.setName {
          return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return $0.setName.localizedCaseInsensitiveCompare($1.setName) == .orderedAscending
      }
    }
  }

  private var totalValue: Double {
    allCards.reduce(0) { $0 + $1.lineValue }
  }

  private var totalCards: Int {
    allCards.reduce(0) { $0 + $1.quantity }
  }

  var body: some View {
    NavigationStack {
      Group {
        if allCards.isEmpty {
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

            Section {
              ForEach(cards, id: \.persistentId) { entry in
                collectionRow(entry)
              }
              .onDelete(perform: deleteCards)
            } header: {
              HStack {
                Text("Your Cards")
                Spacer()
                Menu {
                  Picker("Sort by", selection: $sortOption) {
                    ForEach(CollectionSortOption.allCases) { option in
                      Text(option.rawValue).tag(option)
                    }
                  }
                } label: {
                  Label(sortOption.rawValue, systemImage: "arrow.up.arrow.down")
                    .font(.caption)
                    .labelStyle(.titleAndIcon)
                }
              }
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
        statItem(value: "\(allCards.count)", label: "Unique")
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
    let sorted = cards
    for index in offsets {
      modelContext.delete(sorted[index])
    }
  }
}

#Preview {
  CollectionView()
    .modelContainer(for: CollectedCard.self, inMemory: true)
}
