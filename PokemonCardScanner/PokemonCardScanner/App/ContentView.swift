import SwiftUI

struct ContentView: View {
  var body: some View {
    TabView {
      ScannerView()
        .tabItem {
          Label("Scan", systemImage: "camera.viewfinder")
        }

      CollectionView()
        .tabItem {
          Label("Collection", systemImage: "square.stack.3d.up.fill")
        }
    }
  }
}
