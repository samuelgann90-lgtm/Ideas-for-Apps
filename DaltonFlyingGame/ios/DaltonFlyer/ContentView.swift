import SwiftUI
import WebKit

struct ContentView: View {
  var body: some View {
    GameWebView()
      .ignoresSafeArea()
      .background(Color.black)
  }
}

struct GameWebView: UIViewRepresentable {
  func makeUIView(context: Context) -> WKWebView {
    let config = WKWebViewConfiguration()
    config.allowsInlineMediaPlayback = true
    config.mediaTypesRequiringUserActionForPlayback = []
    config.defaultWebpagePreferences.allowsContentJavaScript = true

    let webView = WKWebView(frame: .zero, configuration: config)
    webView.navigationDelegate = context.coordinator
    webView.scrollView.isScrollEnabled = false
    webView.scrollView.bounces = false
    webView.scrollView.contentInsetAdjustmentBehavior = .never
    webView.isOpaque = true
    webView.backgroundColor = .black
    webView.scrollView.backgroundColor = .black
    if #available(iOS 16.4, *) {
      webView.isInspectable = true
    }

    loadGame(into: webView)
    return webView
  }

  func updateUIView(_ uiView: WKWebView, context: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  private func loadGame(into webView: WKWebView) {
    let index =
      Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "web")
      ?? Bundle.main.url(forResource: "index", withExtension: "html")
    let root = Bundle.main.resourceURL
    if let index = index, let root = root {
      webView.loadFileURL(index, allowingReadAccessTo: root)
    }
  }

  final class Coordinator: NSObject, WKNavigationDelegate {
    func webView(
      _ webView: WKWebView,
      decidePolicyFor navigationAction: WKNavigationAction,
      decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
      decisionHandler(.allow)
    }
  }
}
