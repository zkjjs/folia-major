import XCTest
@testable import FoliaCore

final class PlaybackTests: XCTestCase {
    func testQueueStopsAtEndAndNeverIndexesEmptyQueue() {
        XCTAssertNil(PlaybackRules.nextIndex(current: nil, count: 0))
        XCTAssertEqual(PlaybackRules.nextIndex(current: 0, count: 2), 1)
        XCTAssertNil(PlaybackRules.nextIndex(current: 1, count: 2))
        XCTAssertNil(PlaybackRules.nextIndex(current: -1, count: 2))
    }
    func testSeekRejectsNonFiniteAndClampsToDuration() {
        XCTAssertEqual(PlaybackRules.seekTime(-10, duration: 90), 0)
        XCTAssertEqual(PlaybackRules.seekTime(100, duration: 90), 90)
        XCTAssertEqual(PlaybackRules.seekTime(.nan, duration: 90), 0)
        XCTAssertEqual(PlaybackRules.seekTime(2, duration: .infinity), 0)
    }
    func testLibraryRoundTripAndInvalidSchema() throws {
        let song = Track(id: "local-1", title: "测试", artist: "歌手", album: "", source: .local,
                         location: "song.m4a", artwork: nil, lyric: nil)
        let data = try JSONEncoder().encode([song])
        XCTAssertEqual(try JSONDecoder().decode([Track].self, from: data), [song])
        XCTAssertThrowsError(try JSONDecoder().decode([Track].self, from: Data("{}".utf8)))
    }
    func testNavidromeRejectsInsecureAndMalformedURLs() {
        XCTAssertThrowsError(try ServerAddress.validate("http://music.example.com"))
        XCTAssertThrowsError(try ServerAddress.validate("file:///etc/passwd"))
        XCTAssertThrowsError(try ServerAddress.validate("https://user:pass@music.example.com"))
        XCTAssertEqual(try ServerAddress.validate("https://music.example.com/music/").absoluteString, "https://music.example.com/music/")
    }
}
