import SwiftUI
import WebKit

struct WebChallengeView: UIViewRepresentable {
    let url: URL
    let onHTMLRetrieved: (String) -> Void
    let onCancel: () -> Void

    func makeUIView(context: Context) -> WKWebView {
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences = prefs
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        context.coordinator.startTimeout()
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebChallengeView
        private var hasCompleted = false
        private var timeoutWorkItem: DispatchWorkItem?

        init(_ parent: WebChallengeView) {
            self.parent = parent
        }

        func startTimeout() {
            let workItem = DispatchWorkItem { [weak self] in
                self?.completeWithCancel()
            }
            timeoutWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: workItem)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.title") { [weak self] result, _ in
                guard let self = self, let title = result as? String else { return }

                if title.contains("Just a moment") || title.contains("Cloudflare") || title.contains("Attention Required") {
                    return
                }

                webView.evaluateJavaScript("document.documentElement.outerHTML") { htmlResult, _ in
                    if let html = htmlResult as? String {
                        self.completeWithHTML(html)
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            completeWithCancel()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            completeWithCancel()
        }

        private func completeWithHTML(_ html: String) {
            guard !hasCompleted else { return }
            hasCompleted = true
            timeoutWorkItem?.cancel()
            parent.onHTMLRetrieved(html)
        }

        private func completeWithCancel() {
            guard !hasCompleted else { return }
            hasCompleted = true
            timeoutWorkItem?.cancel()
            parent.onCancel()
        }
    }
}
