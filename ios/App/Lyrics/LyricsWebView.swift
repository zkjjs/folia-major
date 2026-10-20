import SwiftUI
import WebKit
// Only JSON clock/lyric snapshots cross this bridge; no file URLs or credentials are exposed.
struct LyricsWebView: UIViewRepresentable {
    let player: PlayerStore
    let time: Double
    let duration: Double
    let playing: Bool
    let lyric: String
    let active: Bool
    let dark: Bool
    func makeCoordinator() -> Coordinator { Coordinator(player: player) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(context.coordinator, name: "folia")
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false; view.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.navigationDelegate = context.coordinator
        context.coordinator.webView = view
        if let url = Bundle.main.url(forResource: "lyrics", withExtension: "html") {
            view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else { player.error = "歌词资源缺失，请重新安装完整构建。"; }
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.active = active
        context.coordinator.dark = dark
        context.coordinator.send()
    }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "folia")
        view.stopLoading()
        view.navigationDelegate = nil
    }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let player: PlayerStore
        weak var webView: WKWebView?
        var active = true
        var dark = true
        private var ready = false
        private var lastMetadata = ""
        init(player: PlayerStore) { self.player = player }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // React announces readiness after installing its receive handler.
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(navigationAction.request.url?.isFileURL == true ? .allow : .cancel)
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any] else { return }
            if body["type"] as? String == "ready" {
                ready = true; lastMetadata = ""; send(); return
            }
            guard body["id"] as? String == player.current?.id else { return }
            if body["type"] as? String == "seek", let value = body["time"] as? Double, value.isFinite { player.seek(value) }
            if body["type"] as? String == "error" { player.error = "歌词加载失败，请检查歌词文件格式。" }
        }
        func send() {
            guard ready, let webView, let track = player.current else { return }
            var snapshot: [String: Any] = ["id": track.id, "time": player.time, "duration": player.duration,
                "playing": player.playing, "active": active, "dark": dark]
            let key = track.id + "|" + String(player.lyrics.hashValue)
            if key != lastMetadata {
                snapshot["title"] = track.title; snapshot["artist"] = track.artist
                snapshot["lyric"] = player.lyrics
                lastMetadata = key
            }
            guard let data = try? JSONSerialization.data(withJSONObject: snapshot),
                  let json = String(data: data, encoding: .utf8) else { return }
            webView.callAsyncJavaScript("if (!window.FoliaNative) return false; window.FoliaNative.receive(JSON.parse(snapshot)); return true;",
                arguments: ["snapshot": json], in: nil, contentWorld: .page) { [weak self] result in
                    switch result {
                    case .failure: Task { @MainActor in self?.lastMetadata = "" }
                    case .success(let value):
                        if value as? Bool != true { Task { @MainActor in self?.lastMetadata = "" } }
                    }
                }
        }
    }
}
