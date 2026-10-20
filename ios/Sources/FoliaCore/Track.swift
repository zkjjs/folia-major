import Foundation
// Stable library identity; local locations are relative to the app's Documents directory.
public struct Track: Identifiable, Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable { case local, navidrome }
    public var id: String
    public var title: String
    public var artist: String
    public var album: String
    public var source: Source
    public var location: String
    public var artwork: String?
    public var lyric: String?
    public init(id: String, title: String, artist: String, album: String, source: Source,
                location: String, artwork: String?, lyric: String?) {
        self.id = id; self.title = title; self.artist = artist; self.album = album
        self.source = source; self.location = location; self.artwork = artwork; self.lyric = lyric
    }
}
