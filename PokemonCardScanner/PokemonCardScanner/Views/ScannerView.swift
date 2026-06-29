import SwiftUI

private struct CardPresentation: Identifiable {
  let id = UUID()
  let card: PokemonCard
  let similarity: Float?
}

struct ScannerView: View {
  @StateObject private var camera = CameraManager()

  @State private var isScanning = false
  @State private var statusMessage = "Point your camera at a Pokémon card"
  @State private var showManualSearch = false

  @State private var presentedCard: CardPresentation?
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
      .fullScreenCover(item: $presentedCard) { presentation in
        CardResultView(card: presentation.card, matchSimilarity: presentation.similarity) {
          presentedCard = nil
          statusMessage = "Point your camera at a Pokémon card"
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
              Text(match.card.formattedPrice)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
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

    Task { @MainActor in
      defer { isScanning = false }

      do {
        guard let frame = await camera.capturePhoto() else {
          statusMessage = "Camera not ready. Try again."
          return
        }

        statusMessage = "Reading card text…"

        let ocrCandidates = await CardRecognitionService.recognizeCardCandidates(from: frame)

        guard !ocrCandidates.isEmpty else {
          statusMessage = "Couldn't read the card name. Fill the frame with the card name at the top, or use Search."
          return
        }

        let best = ocrCandidates[0]
        statusMessage = "Read \"\(best.candidateName)\" — searching…"

        let cards = try await PokemonTCGService.shared.searchWithFallbacks(candidates: ocrCandidates)
        presentScanResults(cards: cards, ocrName: best.candidateName)
      } catch {
        statusMessage = "Search failed. Check your internet and API key, or use Search."
      }
    }
  }

  @MainActor
  private func searchManually(query: String) async {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    isScanning = true
    statusMessage = "Searching for \"\(trimmed)\"…"
    defer { isScanning = false }

    do {
      let cards = try await PokemonTCGService.shared.searchCards(name: trimmed)
      let ranked = cards.map { RankedCardMatch(card: $0, similarity: 0, visualDistance: .infinity) }
      presentMatches(ranked, ocrName: trimmed)
    } catch {
      statusMessage = error.localizedDescription
    }
  }

  @MainActor
  private func presentScanResults(cards: [PokemonCard], ocrName: String) {
    let ranked = cards.prefix(12).map {
      RankedCardMatch(card: $0, similarity: 0, visualDistance: .infinity)
    }
    presentMatches(Array(ranked), ocrName: ocrName)
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
    presentedCard = CardPresentation(card: card, similarity: similarity)
    statusMessage = "Showing \(card.name)"
  }
}
