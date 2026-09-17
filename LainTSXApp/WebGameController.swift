//
//  WebGameController.swift
//  LainTSXApp
//

import SwiftUI
import WebKit

/// lainTSX を表示する WKWebView を保持し、画面上のボタン操作をキーイベントとして流し込む。
@MainActor
final class WebGameController: NSObject, ObservableObject {
    static let gameURL = URL(string: "https://3d.laingame.net/game.html")!

    @Published private(set) var isLoading = true
    @Published private(set) var loadError: String?

    let webView: WKWebView

    /// keydown を送ってからゲームが 1 フレームでも押下を拾えるようにするための最小保持時間。
    /// 素早いタップだと keydown と keyup が同じフレームに収まり、入力が取りこぼされる。
    private static let minimumHoldDuration: Duration = .milliseconds(100)

    /// 現在押されているキー。keydown / keyup が必ず対で飛ぶようにするために保持する。
    private var pressedKeys: Set<PSXKey> = []

    /// キーごとの keydown を送った時刻。
    private var pressedAt: [PSXKey: ContinuousClock.Instant] = [:]

    /// 最小保持時間の経過待ちで keyup を保留しているキー。
    private var pendingRelease: Set<PSXKey> = []

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        // lainTSX は HTMLAudioElement で SE / BGM を鳴らすため、ユーザー操作なしの再生を許可する
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.addUserScript(
            WKUserScript(source: Self.viewportScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )

        webView = WKWebView(frame: .zero, configuration: configuration)

        super.init()

        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = false
    }

    func loadGameIfNeeded() {
        guard webView.url == nil else { return }
        load()
    }

    func reload() {
        releaseAll()
        load()
    }

    private func load() {
        loadError = nil
        isLoading = true
        webView.load(URLRequest(url: Self.gameURL))
    }

    // MARK: - キー入力

    func press(_ key: PSXKey) {
        // 離す直前に押し直された場合は、保留していた keyup を取り消して押下を継続する
        pendingRelease.remove(key)

        guard pressedKeys.insert(key).inserted else { return }
        pressedAt[key] = ContinuousClock.now
        dispatch(key, type: "keydown")
    }

    func release(_ key: PSXKey) {
        guard pressedKeys.contains(key), !pendingRelease.contains(key) else { return }

        let elapsed = pressedAt[key].map { ContinuousClock.now - $0 } ?? .zero
        guard elapsed < Self.minimumHoldDuration else {
            finishRelease(key)
            return
        }

        pendingRelease.insert(key)
        Task { [weak self] in
            try? await Task.sleep(for: Self.minimumHoldDuration - elapsed)
            guard let self, self.pendingRelease.remove(key) != nil else { return }
            self.finishRelease(key)
        }
    }

    private func finishRelease(_ key: PSXKey) {
        guard pressedKeys.remove(key) != nil else { return }
        pressedAt[key] = nil
        dispatch(key, type: "keyup")
    }

    /// D-pad のように押下中のキーが入れ替わる入力用。差分だけを keydown / keyup に変換する。
    func setDirections(_ keys: Set<PSXKey>) {
        let directions = pressedKeys.filter { $0.isDirection }
        for key in directions.subtracting(keys) {
            release(key)
        }
        for key in keys.subtracting(directions) {
            press(key)
        }
    }

    /// アプリが非アクティブになったときなど、押下状態をその場で打ち切る。
    func releaseAll() {
        pendingRelease.removeAll()
        for key in pressedKeys {
            finishRelease(key)
        }
    }

    private func dispatch(_ key: PSXKey, type: String) {
        let script = """
        window.dispatchEvent(new KeyboardEvent('\(type)', {
            key: '\(key.rawValue)',
            code: '\(key.code)',
            bubbles: true,
            cancelable: true
        }));
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    /// ピンチ / ダブルタップによる拡大とスクロールを抑え、キャンバスが画面いっぱいに収まるようにする。
    /// あわせてページ上部のナビゲーションバーを隠し、ゲーム画面を広く使えるようにする。
    private static let viewportScript = """
    (function () {
        var meta = document.querySelector('meta[name=viewport]');
        if (!meta) {
            meta = document.createElement('meta');
            meta.name = 'viewport';
            document.head.appendChild(meta);
        }
        meta.content = 'width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover';
        document.documentElement.style.touchAction = 'none';
        document.documentElement.style.overscrollBehavior = 'none';
        if (document.body) {
            document.body.style.touchAction = 'none';
            document.body.style.overscrollBehavior = 'none';
        }

        var style = document.createElement('style');
        style.textContent = [
            '#header-bar { display: none !important; }',
            // キャンバスは 800x600 固定で生成されるため、縦横比を保ったまま画面に収める
            '#game-container canvas, #game-container video {',
            '  width: auto !important;',
            '  height: auto !important;',
            '  max-width: 100vw !important;',
            '  max-height: 100vh !important;',
            '}'
        ].join('\\n');
        document.head.appendChild(style);
    })();
    """
}

extension WebGameController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        loadError = error.localizedDescription
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        loadError = error.localizedDescription
    }
}

private extension PSXKey {
    var isDirection: Bool {
        switch self {
        case .up, .down, .left, .right: return true
        default: return false
        }
    }
}

/// `WebGameController` が持つ WKWebView を SwiftUI に載せるだけのラッパー。
struct GameWebView: UIViewRepresentable {
    let controller: WebGameController

    func makeUIView(context: Context) -> WKWebView {
        controller.loadGameIfNeeded()
        return controller.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
