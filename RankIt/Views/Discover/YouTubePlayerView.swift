import SwiftUI
import WebKit

/// Embeds an official YouTube trailer via the IFrame Player API. Never
/// downloads, caches, or plays a raw video file — see SPEC.md's legal
/// constraints. Autoplays muted; `isPlaying` drives play/pause via the
/// IFrame postMessage command API.
struct YouTubePlayerView: UIViewRepresentable {
    let youtubeKey: String
    @Binding var isPlaying: Bool

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.loadHTMLString(Self.embedHTML(youtubeKey: youtubeKey), baseURL: URL(string: "https://www.youtube.com"))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let command = isPlaying ? "playVideo" : "pauseVideo"
        let js = "player.\(command) && player.\(command)();"
        webView.evaluateJavaScript(js)
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
                }
              });
            }
          </script>
        </body>
        </html>
        """
    }
}
