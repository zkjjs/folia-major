import XCTest
@testable import FoliaCore

final class SessionTests: XCTestCase {
    private func song(_ id: String, _ source: Track.Source = .local) -> Track {
        Track(id: id, title: id, artist: "", album: "", source: source, location: id, artwork: nil, lyric: nil)
    }
    func testImportedLyricsSurviveQueueNavigationWithoutChangingOtherSongs() {
        let queue = [song("first"), song("second")]
        let updated = PlaybackRules.queueByAttachingLyrics("new lyrics", to: "first", in: queue)
        XCTAssertEqual(updated[0].lyric, "new lyrics")
        XCTAssertNil(updated[1].lyric)
        XCTAssertEqual(updated.map(\.id), queue.map(\.id))
        XCTAssertEqual(PlaybackRules.queueByAttachingLyrics("ignored", to: "absent", in: queue), queue)
    }
    func testDisconnectInvalidatesRemoteQueueButKeepsLocalQueue() {
        XCTAssertFalse(PlaybackRules.needsServerReset([song("local")]))
        XCTAssertTrue(PlaybackRules.needsServerReset([song("remote", .navidrome)]))
        XCTAssertTrue(PlaybackRules.needsServerReset([song("local"), song("remote", .navidrome)]))
        XCTAssertFalse(PlaybackRules.needsServerReset([]))
    }
    func testServerLyricsUseMillisecondsAndPositiveOffsetAppearsSooner() throws {
        let json = Data(#"{"lyricsList":{"structuredLyrics":[{"synced":true,"offset":500,"line":[{"start":1500,"value":"hello"},{"start":62500,"value":"world"}]}]}}"#.utf8)
        XCTAssertEqual(try ServerLyrics.text(from: json), "[00:01.000]hello\n[01:02.000]world")
    }
    func testServerLyricsPreferSyncedAndKeepPlainLyricsReadable() throws {
        let plain = Data(#"{"lyricsList":{"structuredLyrics":[{"synced":false,"line":[{"value":"plain"},{"value":"text"}]}]}}"#.utf8)
        XCTAssertEqual(try ServerLyrics.text(from: plain), "plain\ntext")
        let multiple = Data(#"{"lyricsList":{"structuredLyrics":[{"synced":false,"line":[{"value":"plain"}]},{"synced":true,"line":[{"start":2000,"value":"timed"}]}]}}"#.utf8)
        XCTAssertEqual(try ServerLyrics.text(from: multiple), "[00:02.000]timed")
        XCTAssertNil(try ServerLyrics.text(from: Data(#"{"lyricsList":{"structuredLyrics":[]}}"#.utf8)))
        XCTAssertThrowsError(try ServerLyrics.text(from: Data("invalid".utf8)))
    }
}
