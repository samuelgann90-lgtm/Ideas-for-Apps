import SwiftUI
import Charts

struct PriceHistoryChartView: View {
  let card: PokemonCard

  @State private var points: [PriceHistoryPoint] = []
  @State private var isLoading = true
  @State private var errorMessage: String?
  @State private var period = "90d"

  private let periods = [
    ("30d", "30 days"),
    ("90d", "90 days"),
    ("365d", "1 year"),
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label("Price History", systemImage: "chart.line.uptrend.xyaxis")
          .font(.headline)
        Spacer()
        Picker("Period", selection: $period) {
          ForEach(periods, id: \.0) { value, label in
            Text(label).tag(value)
          }
        }
        .pickerStyle(.menu)
        .labelsHidden()
      }
      .padding(.horizontal)

      if isLoading {
        ProgressView()
          .frame(maxWidth: .infinity)
          .frame(height: 160)
      } else if let errorMessage {
        Text(errorMessage)
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity)
          .frame(height: 80)
      } else if points.count < 2 {
        Text("Not enough history data for this card.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity)
          .frame(height: 80)
      } else {
        Chart(points) { point in
          LineMark(
            x: .value("Date", point.date),
            y: .value("Price", point.average)
          )
          .foregroundStyle(.green)
          .interpolationMethod(.catmullRom)

          AreaMark(
            x: .value("Date", point.date),
            y: .value("Price", point.average)
          )
          .foregroundStyle(
            LinearGradient(
              colors: [.green.opacity(0.25), .green.opacity(0.02)],
              startPoint: .top,
              endPoint: .bottom
            )
          )
          .interpolationMethod(.catmullRom)
        }
        .chartYAxis {
          AxisMarks(position: .leading) { value in
            AxisGridLine()
            AxisValueLabel {
              if let price = value.as(Double.self) {
                Text("$\(Int(price))")
                  .font(.caption2)
              }
            }
          }
        }
        .chartXAxis {
          AxisMarks(values: .automatic(desiredCount: 4)) { _ in
            AxisGridLine()
            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
          }
        }
        .frame(height: 180)
        .padding(.horizontal)
      }
    }
    .task(id: "\(card.id)-\(period)") {
      await loadHistory()
    }
  }

  private func loadHistory() async {
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }

    do {
      points = try await PkmnPricesService.shared.fetchPriceHistory(for: card, period: period)
    } catch {
      errorMessage = error.localizedDescription
      points = []
    }
  }
}
