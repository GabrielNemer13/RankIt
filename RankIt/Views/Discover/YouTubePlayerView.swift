import SwiftUI
import WebKit

/// Embeds an official YouTube trailer via the IFrame Player API. Never
/// downloads, caches, or plays a raw video file — see SPEC.md's legal
/// constraints. Autoplays muted; `isPlaying` drives play/pause via the
/// IFrame postMessage command API.
///
/// Some videos block embedding entirely (the uploader disabled it) — the
/// IFrame API reports this via an `onError` callback (codes 101/150) rather
/// than failing to load, so it can't be detected from `WKNavigationDelegate`.
/// That callback is bridged out via a `WKScriptMessageHandler` and surfaced
/// as `onEmbedFailure`, so the caller can show a non-blank fallback.
struct YouTubePlayerView: UIViewRepresentable {
    let youtubeKey: String
    @Binding var isPlaying: Bool
    var onEmbedFailure: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onEmbedFailure: onEmbedFailure)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.add(context.coordinator, name: "playerError")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.loadHTMLString(Self.embedHTML(youtubeKey: youtubeKey), baseURL: URL(string: "https://www.youtube.com"))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onEmbedFailure = onEmbedFailure
        let command = isPlaying ? "playVideo" : "pauseVideo"
        let js = "player.\(command) && player.\(command)();"
        webView.evaluateJavaScript(js)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "playerError")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var onEmbedFailure: () -> Void
        init(onEmbedFailure: @escaping () -> Void) {
            self.onEmbedFailure = onEmbedFailure
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "playerError" else { return }
            // 2 = invalid video id, 100 = removed/private, 101/150 = the
            // uploader disabled embedding -- all of these mean "can't play
            // here," so treat them uniformly rather than special-casing.
            onEmbedFailure()
        }
    }

    private static func embedHTML(youtubeKey: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
          <style>
            html, body { margin: 0; padding: 0; background: #000; height: 100%; overflow: hidden; }
            #player { position: absolute; top: 0; left: 0; width: 100%; height: 100%; }
          </style>
        </head>
        <body>
          <div id="player"></div>
          <script src="https://www.youtube.com/iframe_api"></script>
          <script>
            var player;
            function onYouTubeIframeAPIReady() {
              player = new YT.Player('player', {
                videoId: '\(youtubeKey)',
                playerVars: {
                  autoplay: 1, mute: 1, playsinline: 1, controls: 0,
                  loop: 1, playlist: '\(youtubeKey)', modestbranding: 1, rel: 0
                },
                events: {
                  onError: function(e) {
                    window.webkit.messageHandlers.playerError.postMessage(String(e.data));
                  }
                }
              });
            }
          </script>
        </body>
        </html>
        """
    }
}
