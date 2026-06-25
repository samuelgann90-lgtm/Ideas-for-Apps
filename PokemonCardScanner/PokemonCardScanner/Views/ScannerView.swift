import SwiftUI

struct ScannerView: View {
  @StateObject private var camera = CameraManager()

  @State private var isScanning = false
  @State private var statusMessage = "Point your camera at a Pokémon card"
  @State private var sheetContent: ScannerSheetContent?
  @State private var showManualSearch = false
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
      .sheet(item: $sheetContent) { content in
        switch content {
        case .result(let card, let similarity):
          CardResultView(card: card, matchSimilarity: similarity) {
            sheetContent = nil
          }
        case .picker(let matches):
          cardPickerSheet(matches: matches)
        }
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
          sheetContent = .result(match.card, match.similarity)
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
                Text(match.similarityLabel)
                  .font(.caption.weight(.medium))
                  .foregroundStyle(.blue)
              }
            }
          }
        }
      }
      .navigationTitle("Pick a Match")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Cancel") { sheetContent = nil }
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

      let candidates = await CardRecognitionService.recognizeCardCandidates(from: frame)

      guard !candidates.isEmpty else {
        statusMessage = "Couldn't read the card name. Center the card, add light, and try again — or use Search."
        return
      }

      let best = candidates[0]
      statusMessage = "Found \"\(best.candidateName)\" — looking up card…"

      do {
        let cards = try await PokemonTCGService.shared.searchWithFallbacks(candidates: candidates)
        statusMessage = "Matching artwork…"
        let ranked = await VisualMatchingService.rank(candidates: cards, scannedImage: frame)
        await presentResults(ranked, ocrName: best.candidateName)
      } catch {
        let triedNames = candidates.prefix(3).map(\.candidateName).joined(separator: ", ")
        statusMessage = "No match for: \(triedNames). Try Search or rescan with better light."
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
      await presentResults(ranked)
    } catch {
      statusMessage = error.localizedDescription
    }
  }

  @MainActor
  private func presentResults(_ matches: [RankedCardMatch], ocrName: String? = nil) {
    guard let top = matches.first else {
      statusMessage = "No matches found."
      return
    }

    if matches.count == 1 || VisualMatchingService.shouldAutoSelect(matches) {
      sheetContent = .result(top.card, top.similarity)
      statusMessage = "Tap the shutter to scan another card"
    } else {
      sheetContent = .picker(matches)
      if let ocrName {
        statusMessage = "Several \"\(ocrName)\" cards — pick the best match"
      } else {
        statusMessage = "Multiple matches — pick the best visual match"
      }
    }
  }
}

private enum ScannerSheetContent: Identifiable {
  case result(PokemonCard, Float?)
  case picker([RankedCardMatch])

  var id: String {
    switch self {
    case .result(let card, _): return "result-\(card.id)"
    case .picker(let matches): return "picker-\(matches.map(\.id).joined())"
    }
  }
}

#Preview {
  ScannerView()
}
