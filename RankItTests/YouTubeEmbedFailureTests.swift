import XCTest
@testable import RankIt

/// Covers the classifier that tells a genuine YouTube embed restriction
/// apart from any other player failure -- added after a real bug where a
/// self-referential `baseURL` (`https://www.youtube.com`) made the IFrame
/// Player API report a non-standard `onError` code (152) for nearly every
/// video, which the app's fallback UI couldn't distinguish from a real
/// per-video restriction without this classification. See
/// `YouTubePlayerView`'s doc comment for the root cause and fix.
final class YouTubeEmbedFailureTests: XCTestCase {
    func test_documentedEmbedRestrictionCodes_classifyAsEmbeddingDisabled() {
        XCTAssertEqual(YouTubeEmbedFailure.classify(errorCode: 101), .embeddingDisabled(code: 101))
        XCTAssertEqual(YouTubeEmbedFailure.classify(errorCode: 150), .embeddingDisabled(code: 150))
    }

    func test_otherDocumentedCodes_classifyAsPlaybackErrorNotEmbedRestriction() {
        XCTAssertEqual(YouTubeEmbedFailure.classify(errorCode: 2), .playbackError(code: 2)) // invalid parameter
        XCTAssertEqual(YouTubeEmbedFailure.classify(errorCode: 5), .playbackError(code: 5)) // HTML5 player error
        XCTAssertEqual(YouTubeEmbedFailure.classify(errorCode: 100), .playbackError(code: 100)) // removed/private
    }

    /// The exact regression this suite exists for: code 152 is not one of
    /// YouTube's documented codes and must never be silently treated as a
    /// genuine embed restriction.
    func test_undocumentedCode152_classifiesAsPlaybackErrorNotEmbedRestriction() {
        let result = YouTubeEmbedFailure.classify(errorCode: 152)

        XCTAssertEqual(result, .playbackError(code: 152))
        if case .embeddingDisabled = result {
            XCTFail("code 152 must never classify as a genuine embed restriction")
        }
    }

    func test_description_distinguishesEmbedRestrictionFromOtherFailures() {
        XCTAssertTrue(YouTubeEmbedFailure.embeddingDisabled(code: 150).description.contains("embedding disabled"))
        XCTAssertTrue(YouTubeEmbedFailure.playbackError(code: 152).description.contains("NOT an embed restriction"))
        XCTAssertTrue(YouTubeEmbedFailure.scriptLoadFailed.description.contains("script failed to load"))
        XCTAssertTrue(YouTubeEmbedFailure.scriptTimedOut.description.contains("never called onYouTubeIframeAPIReady"))
    }
}
