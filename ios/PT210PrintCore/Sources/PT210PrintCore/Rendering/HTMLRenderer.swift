import CoreGraphics
import Foundation
import WebKit

@MainActor
public final class HTMLRenderer: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<CGImage, Error>?
    private var webView: WKWebView?

    public func render(html: String, css: String?, width: Int) async throws -> CGImage {
        guard html.utf8.count <= ContentDetector.maximumTextBytes else { throw PrintError.inputTooLarge }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: width, height: 1), configuration: configuration)
        webView.navigationDelegate = self
        self.webView = webView
        let document = Self.document(html: html, css: css, width: width)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                webView.loadHTMLString(document, baseURL: nil)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.webView?.stopLoading()
                self?.finish(with: .failure(PrintError.cancelled))
            }
        }
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            do {
                let rawHeight = try await webView.evaluateJavaScript("Math.ceil(document.documentElement.scrollHeight)")
                let height = min(max((rawHeight as? NSNumber)?.doubleValue ?? 1, 1), 30_000)
                webView.frame.size.height = height
                let image = try await webView.takeSnapshot(configuration: nil)
                guard let cgImage = image.cgImage else { throw PrintError.renderFailed }
                finish(with: .success(cgImage))
            } catch {
                finish(with: .failure(error))
            }
        }
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(with: .failure(error))
    }

    private func finish(with result: Result<CGImage, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        webView = nil
        continuation.resume(with: result)
    }

    private static func document(html: String, css: String?, width: Int) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data: blob:; style-src 'unsafe-inline'; font-src data:">
        <meta name="viewport" content="width=\(width), initial-scale=1">
        <style>html,body{margin:0;padding:0;width:\(width)px;background:#fff;color:#000;overflow-x:hidden;font:22px/1.35 -apple-system,BlinkMacSystemFont,sans-serif;overflow-wrap:anywhere}img{max-width:100%;height:auto}pre{white-space:pre-wrap;font:17px ui-monospace,monospace}table{width:100%;border-collapse:collapse}td,th{border:1px solid #000;padding:4px}\(css ?? "")</style>
        </head><body>\(html)</body></html>
        """
    }
}
