import SwiftUI
import SwiftData

@main
struct PokemonCardScannerApp: App {
  var body: some Scene {
    WindowGroup {
      ContentView()
    }
    .modelContainer(for: CollectedCard.self)
  }
}
