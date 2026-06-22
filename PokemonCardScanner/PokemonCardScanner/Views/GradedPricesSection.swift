import SwiftUI
import SwiftData
import Charts

struct GradedPricesSection: View {
  let card: PokemonCard

  @State private var tiers: [GradedPriceTier] = []
  @State private var isLoading = true
  @State private var errorMessage: String?
  @State private var expandedTierID: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("Graded Card Prices", systemImage: "rosette")
        .font(.headline)
        .padding(.horizontal)

      if isLoading {
        HStack {
          Spacer()
          ProgressView("Loading graded sales…")
          Spacer()
        }
        .padding()
      } else if let errorMessage {
        VStack(spacing: 8) {
          Text(errorMessage)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
          if !APIConfiguration.hasValidPkmnPricesKey {
            Text("Get a free key at pkmnprices.com")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .frame(maxWidth: .infinity)
        .padding()
      } else if tiers.isEmpty {
        Text("No recent graded sales found for this card.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity)
          .padding()
      } else {
        VStack(spacing: 0) {
          ForEach(tiers) { tier in
            gradedTierRow(tier)
            if tier.id != tiers.last?.id {
              Divider().padding(.leading)
            }
          }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)

        Text("Based on recent eBay sold listings via PkmnPrices. Requires a free API key.")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .padding(.horizontal)
      }
    }
    .task(id: card.id) {
      await loadGradedPrices()
    }
  }

  private func gradedTierRow(_ tier: GradedPriceTier) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Button {
        withAnimation(.easeInOut(duration: 0.2)) {
          expandedTierID = expandedTierID == tier.id ? nil : tier.id
        }
      } label: {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text(tier.label)
              .font(.subheadline.weight(.semibold))
            Text("\(tier.saleCount) recent sale\(tier.saleCount == 1 ? "" : "s")")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Text(tier.formattedAverage)
            .font(.headline)
            .foregroundStyle(.orange)
          Image(systemName: expandedTierID == tier.id ? "chevron.up" : "chevron.down")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
      }
      .buttonStyle(.plain)

      if expandedTierID == tier.id {
        VStack(alignment: .leading, spacing: 6) {
          ForEach(tier.recentSales.prefix(5)) { sale in
            HStack(alignment: .top) {
              Text(String(format: "$%.0f", sale.price))
                .font(.caption.weight(.semibold))
                .frame(width: 56, alignment: .leading)
              VStack(alignment: .leading, spacing: 2) {
                Text(sale.title)
                  .font(.caption2)
                  .lineLimit(2)
                if let soldAt = sale.soldAt {
                  Text(soldAt)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
              }
            }
          }
        }
        .padding(.horizontal)
        .padding(.bottom, 10)
      }
    }
  }

  private func loadGradedPrices() async {
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }

    do {
      tiers = try await PkmnPricesService.shared.fetchGradedPrices(for: card)
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
