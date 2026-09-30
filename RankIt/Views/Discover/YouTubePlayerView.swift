import SwiftUI
import WebKit

/// Classifies a YouTube IFrame Player API failure so logs (and callers, if
/// they ever need to) can tell a genuine per-video embed restriction apart
/// from something else going wrong. Only 101 and 150 are YouTube's
/// documented codes for "the uploader disabled embedding" -- everything
/// else (2 invalid parameter, 5 HTML5 player error, 100 removed/private,
/// or the player's own script/ready-state failures) is somewhere else in
/// the pipeline, not a real embed restriction, even though the fallback UI
/// looks the same for both today.
enum YouTubeEmbedFailure: Equatable, CustomStringConvertible {
    case embeddingDisabled(code: Int)
    case playbackError(code: Int)
    case scriptLoadFailed
    case scriptTimedOut

    static func classify(errorCode: Int) -> YouTubeEmbedFailure {
        switch errorCode {
        case 101, 150: return .embeddingDisabled(code: errorCode)
        default: return .playbackError(code: errorCode)
        }
    }

    var description: String {
        switch self {
        case .embeddingDisabled(let code): return "embedding disabled by uploader (code \(code))"
        case .playbackError(let code): return "playback error, NOT an embed restriction (code \(code))"
        case .scriptLoadFailed: return "iframe_api script failed to load"
        case .scriptTimedOut: return "iframe_api script never called onYouTubeIframeAPIReady"
        }
    }
}

/// Embeds an official YouTube trailer via the IFrame Player API. Never
/// downloads, caches, or plays a raw video file — see SPEC.md's legal
/// constraints. Autoplays muted; `isPlaying` drives play/pause via the
/// IFrame postMessage command API.
///
/// A genuinely blocked video reports it via the IFrame API's `onError`
/// callback (codes 101/150) rather than failing to load, so it can't be
/// detected from `WKNavigationDelegate`. That callback is bridged out via
/// a `WKScriptMessageHandler` and surfaced as `onEmbedFailure`, so the
/// caller can show a non-blank fallback.
///
/// The page is loaded via `loadHTMLString`, which needs *some* `baseURL`
/// for the document's nominal origin. That origin must not be
/// `https://www.youtube.com` itself: the IFrame API passes it to YouTube
/// as the embedding page's `origin` for its postMessage security check,
/// and a page whose own origin claims to BE youtube.com is self-referential
/// in a way YouTube's player rejects -- it fails almost every video with
/// `onError` code 152 (not one of YouTube's documented codes), which looks
/// exactly like a genuine per-video embed restriction but isn't one. Fixed
/// by using an arbitrary non-YouTube origin instead, matching how every
/// real third-party site embedding a YouTube player actually looks to it.
struct YouTubePlayerView: UIViewRepresentable {
    let youtubeKey: String
    @Binding var isPlaying: Bool
    var onEmbedFailure: () -> Void = {}

    /// Deliberately not youtube.com -- see the type's doc comment. Doesn't
    /// need to resolve to anything; it's only ever used as the document's
    /// nominal origin, never fetched over the network.
    private static let embedBaseURL = URL(string: "https://rankit.app")!

    func makeCoordinator() -> Coordinator {
        Coordinator(onEmbedFailure: onEmbedFailure)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.add(context.coordinator, name: "playerBridge")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.loadHTMLString(Self.embedHTML(youtubeKey: youtubeKey), baseURL: Self.embedBaseURL)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onEmbedFailure = onEmbedFailure
        let command = isPlaying ? "playVideo" : "pauseVideo"
        let js = "player.\(command) && player.\(command)();"
        webView.evaluateJavaScript(js)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "playerBridge")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var onEmbedFailure: () -> Void
        init(onEmbedFailure: @escaping () -> Void) {
            self.onEmbedFailure = onEmbedFailure
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "playerBridge" else { return }
            let body = String(describing: message.body)

            let failure: YouTubeEmbedFailure?
            switch body {
            case "SCRIPT_TIMEOUT": failure = .scriptTimedOut
            case "SCRIPT_LOAD_FAILED": failure = .scriptLoadFailed
            case _ where body.hasPrefix("ERROR:"):
                let code = Int(body.dropFirst("ERROR:".count)) ?? -1
                failure = .classify(errorCode: code)
            default: failure = nil // unrecognized message; nothing to classify.
            }

            #if DEBUG
            if let failure {
                NSLog("[YouTubePlayerView] %@", failure.description)
            } else {
                NSLog("[YouTubePlayerView] %@", body)
            }
            #endif

            if failure != nil {
                onEmbedFailure()
            }
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
          <script>
            // Reports every stage of setup -- not just onError -- so a
            // genuinely blocked video (see YouTubeEmbedFailure) can be told
            // apart from the iframe_api script never loading/never calling
            // back, which look identical from the fallback UI alone.
            var apiReadyFired = false;
            setTimeout(function() {
              if (!apiReadyFired) {
                window.webkit.messageHandlers.playerBridge.postMessage('SCRIPT_TIMEOUT');
              }
            }, 8000);

            var player;
            function onYouTubeIframeAPIReady() {
              apiReadyFired = true;
              player = new YT.Player('player', {
                videoId: '\(youtubeKey)',
                playerVars: {
                  autoplay: 1, mute: 1, playsinline: 1, controls: 0,
                  loop: 1, playlist: '\(youtubeKey)', modestbranding: 1, rel: 0
                },
                events: {
                  onError: function(e) {
                    window.webkit.messageHandlers.playerBridge.postMessage('ERROR:' + e.data);
                  }
                }
              });
            }
          </script>
          <script src="https://www.youtube.com/iframe_api"
                  onerror="window.webkit.messageHandlers.playerBridge.postMessage('SCRIPT_LOAD_FAILED')"></script>
        </body>
        </html>
        """
    }
}
