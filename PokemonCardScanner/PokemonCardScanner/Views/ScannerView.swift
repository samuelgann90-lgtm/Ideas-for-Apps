import SwiftUI

struct ScannerView: View {
  @StateObject private var camera = CameraManager()

  @State private var isScanning = false
  @State private var statusMessage = "Point your camera at a Pokémon card"
  @State private var showManualSearch = false

  @State private var resultCard: PokemonCard?
  @State private var resultSimilarity: Float?
  @State private var showCardResult = false

  @State private var pickerMatches: [RankedCardMatch] = []
  @State private var showCardPicker = false

  @State private var lastScanDate: Date?

  private let scanCooldown: TimeInterval = 2.5

  var body: some View {
    NavigationStack {
      ZStack {
        if camera.permissionDenied {
          permissionDeniedView
        } else {
          cameraContent
        }
      }
      .navigationTitle("Scan")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Search") { showManualSearch = true }
        }
      }
      .onAppear { camera.requestPermissionAndStart() }
      .onDisappear { camera.stopSession() }
      .fullScreenCover(isPresented: $showCardResult) {
        if let card = resultCard {
          CardResultView(card: card, matchSimilarity: resultSimilarity) {
            showCardResult = false
            resultCard = nil
            statusMessage = "Point your camera at a Pokémon card"
          }
        }
      }
      .fullScreenCover(isPresented: $showCardPicker) {
        cardPickerSheet(matches: pickerMatches)
      }
      .sheet(isPresented: $showManualSearch) {
        ManualSearchView(isPresented: $showManualSearch) { query in
          Task { await searchManually(query: query) }
        }
      }
    }
  }

  private var cameraContent: some View {
    ZStack {
      CameraPreviewView(session: camera.session)
        .ignoresSafeArea()

      LinearGradient(
        colors: [.black.opacity(0.55), .clear, .black.opacity(0.65)],
        startPoint: .top,
        endPoint: .bottom
      )
      .ignoresSafeArea()

      VStack {
        Text(statusMessage)
          .font(.subheadline.weight(.medium))
          .foregroundStyle(.white)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 16)
          .padding(.vertical, 10)
          .background(.black.opacity(0.45), in: Capsule())
          .padding(.top, 12)

        Spacer()

        RoundedRectangle(cornerRadius: 16)
          .strokeBorder(.white.opacity(0.9), lineWidth: 2)
          .frame(width: 260, height: 360)
          .overlay(alignment: .topLeading) {
            Text("Fill frame with card")
              .font(.caption2)
              .foregroundStyle(.white.opacity(0.8))
              .padding(8)
          }

        Spacer()

        Button(action: scanCard) {
          ZStack {
            Circle()
              .fill(.white)
              .frame(width: 76, height: 76)
            if isScanning {
              ProgressView()
            } else {
              Image(systemName: "camera.viewfinder")
                .font(.title2)
                .foregroundStyle(.black)
            }
          }
        }
        .disabled(isScanning)
        .padding(.bottom, 36)
      }
    }
  }

  private var permissionDeniedView: some View {
    ContentUnavailableView {
      Label("Camera Access Needed", systemImage: "camera.fill")
    } description: {
      Text("Enable camera access in Settings to scan Pokémon cards.")
    } actions: {
      if let url = URL(string: UIApplication.openSettingsURLString) {
        Link("Open Settings", destination: url)
      }
    }
  }

  private func cardPickerSheet(matches: [RankedCardMatch]) -> some View {
    NavigationStack {
      List(matches) { match in
        Button {
          openCardResult(match.card, similarity: match.similarity)
        } label: {
          HStack(spacing: 12) {
            AsyncImage(url: URL(string: match.card.images.small)) { image in
              image.resizable().scaledToFit()
            } placeholder: {
              Color.gray.opacity(0.2)
            }
            .frame(width: 44, height: 62)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 4) {
              Text(match.card.name).font(.headline)
              Text("\(match.card.set.name) · #\(match.card.number)")
                .font(.caption)
                .foregroundStyle(.secondary)
              HStack {
                Text(match.card.formattedPrice)
                  .font(.subheadline.weight(.semibold))
                  .foregroundStyle(.green)
                Spacer()
                if match.similarity > 0 {
                  Text(match.similarityLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.blue)
                }
              }
            }
          }
        }
      }
      .navigationTitle("Pick Your Card")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Cancel") {
            showCardPicker = false
            statusMessage = "Point your camera at a Pokémon card"
          }
        }
      }
    }
  }

  private func scanCard() {
    guard !isScanning else { return }
    if let lastScanDate, Date().timeIntervalSince(lastScanDate) < scanCooldown {
      statusMessage = "Hold steady — scanning again soon…"
      return
    }

    isScanning = true
    statusMessage = "Hold still — capturing…"
    lastScanDate = Date()

    Task {
      defer { isScanning = false }

      guard let frame = await camera.capturePhoto() else {
        statusMessage = "Camera not ready. Try again."
        return
      }

      statusMessage = "Reading card text…"

      let ocrCandidates = await CardRecognitionService.recognizeCardCandidates(from: frame)

      guard !ocrCandidates.isEmpty else {
        statusMessage = "Couldn't read the card name. Add light, fill the frame, or use Search."
        return
      }

      let best = ocrCandidates[0]
      statusMessage = "Found \"\(best.candidateName)\" — searching…"

      do {
        let cards = try await PokemonTCGService.shared.searchWithFallbacks(candidates: ocrCandidates)
        await presentScanResults(cards: cards, scannedImage: frame, ocrName: best.candidateName)
      } catch {
        let triedNames = ocrCandidates.prefix(3).map(\.candidateName).joined(separator: ", ")
        statusMessage = "No match for: \(triedNames). Try Search instead."
      }
    }
  }

  private func searchManually(query: String) async {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    isScanning = true
    statusMessage = "Searching for \"\(trimmed)\"…"
    defer { isScanning = false }

    do {
      let cards = try await PokemonTCGService.shared.searchCards(name: trimmed)
      let ranked = cards.map { RankedCardMatch(card: $0, similarity: 0, visualDistance: .infinity) }
      await presentMatches(ranked, ocrName: trimmed)
    } catch {
      statusMessage = error.localizedDescription
    }
  }

  @MainActor
  private func presentScanResults(cards: [PokemonCard], scannedImage: CGImage, ocrName: String) async {
    if cards.count == 1 {
      openCardResult(cards[0], similarity: nil)
      statusMessage = "Showing \(cards[0].name)"
      return
    }

    statusMessage = "Found \(cards.count) matches — ranking…"
    let topCandidates = Array(cards.prefix(6))
    let ranked = await VisualMatchingService.rank(candidates: topCandidates, scannedImage: scannedImage)
    await presentMatches(ranked, ocrName: ocrName)
  }

  @MainActor
  private func presentMatches(_ matches: [RankedCardMatch], ocrName: String?) {
    guard !matches.isEmpty else {
      statusMessage = "No matches found."
      return
    }

    if matches.count == 1 {
      openCardResult(matches[0].card, similarity: matches[0].similarity)
      statusMessage = "Showing \(matches[0].card.name)"
      return
    }

    pickerMatches = matches
    showCardPicker = true
    if let ocrName {
      statusMessage = "Pick the right \"\(ocrName)\" card"
    } else {
      statusMessage = "Pick the card that matches yours"
    }
  }

  @MainActor
  private func openCardResult(_ card: PokemonCard, similarity: Float?) {
    showCardPicker = false
    resultCard = card
    resultSimilarity = similarity
    showCardResult = true
    statusMessage = "Showing \(card.name)"
  }
}

#Preview {
  ScannerView()
}
