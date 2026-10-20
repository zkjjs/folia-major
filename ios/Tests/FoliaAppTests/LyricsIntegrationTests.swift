import XCTest
import WebKit
import UIKit

// Exercise the actual bundled upstream renderer in WebKit instead of assuming a successful Vite build is enough.
@MainActor final class LyricsIntegrationTests: XCTestCase {
    final class PageMessages: NSObject, WKScriptMessageHandler {
        let ready: XCTestExpectation
        var receivedReady = false
        var errors: [String] = []
        init(ready: XCTestExpectation) { self.ready = ready }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            if body["type"] as? String == "ready", !receivedReady {
                receivedReady = true; ready.fulfill()
            }
            if body["type"] as? String == "error" { errors.append("renderer error") }
        }
    }
    func testBundledLyricsBecomeReadySeekAndResumeOffline() async throws {
        let ready = expectation(description: "React lyric bridge ready")
        let messages = PageMessages(ready: ready)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(messages, name: "folia")
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        window.rootViewController?.view.addSubview(view)
        defer {
            view.configuration.userContentController.removeScriptMessageHandler(forName: "folia")
            view.removeFromSuperview(); window.isHidden = true
        }
        let page = try XCTUnwrap(Bundle.main.url(forResource: "lyrics", withExtension: "html"))
        view.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        await fulfillment(of: [ready], timeout: 30)
        let snapshot: [String: Any] = ["id": "test-track", "time": 0.5, "duration": 10,
            "playing": false, "active": true, "dark": true, "title": "Test", "artist": "Test",
            "lyric": "[00:00.00]First test line\n[00:02.00]Second test line"]
        let json = String(data: try JSONSerialization.data(withJSONObject: snapshot), encoding: .utf8)!
        _ = try await view.callAsyncJavaScript("window.FoliaNative.receive(JSON.parse(snapshot));",
            arguments: ["snapshot": json], in: nil, contentWorld: .page)
        let first = try await view.callAsyncJavaScript("""
            for (let i = 0; i < 50; i++) {
                if (document.body.textContent.includes('First')) return true;
                await new Promise(resolve => setTimeout(resolve, 100));
            }
            return false;
            """, arguments: [:], in: nil, contentWorld: .page)
        XCTAssertEqual(first as? Bool, true, "Bundled original renderer did not show the first lyric")
        let second = try await view.callAsyncJavaScript("""
            window.FoliaNative.receive({id:'test-track',time:2.5,duration:10,playing:false,active:false,dark:true});
            await new Promise(resolve => setTimeout(resolve, 100));
            window.FoliaNative.receive({id:'test-track',time:2.5,duration:10,playing:false,active:true,dark:true});
            for (let i = 0; i < 50; i++) {
                if (document.body.textContent.includes('Second')) return true;
                await new Promise(resolve => setTimeout(resolve, 100));
            }
            return false;
            """, arguments: [:], in: nil, contentWorld: .page)
        XCTAssertEqual(second as? Bool, true, "Native seek/background resume did not synchronize the lyric")
        XCTAssertTrue(messages.errors.isEmpty)
    }
}
