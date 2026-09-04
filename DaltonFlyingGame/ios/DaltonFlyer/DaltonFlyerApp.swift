import SwiftUI

@main
struct DaltonFlyerApp: App {
  var body: some Scene {
    WindowGroup {
      ContentView()
        .statusBarHidden(true)
        .preferredColorScheme(.dark)
    }
  }
}
