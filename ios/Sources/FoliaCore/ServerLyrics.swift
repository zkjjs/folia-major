import Foundation
// Convert OpenSubsonic timed lyrics to the same LRC input the upstream renderer parses.
public enum ServerLyrics {
    private struct Response: Decodable { var lyricsList: LyricsList? }
    private struct LyricsList: Decodable { var structuredLyrics: [LyricsTrack]? }
    private struct LyricsTrack: Decodable {
        var synced: Bool
        var offset: Double?
        var line: [LyricsLine]
    }
    private struct LyricsLine: Decodable { var start: Double?; var value: String }
    public static func text(from data: Data) throws -> String? {
        let tracks = try JSONDecoder().decode(Response.self, from: data).lyricsList?.structuredLyrics ?? []
        guard let track = tracks.first(where: { $0.synced && !$0.line.isEmpty }) ?? tracks.first(where: { !$0.line.isEmpty }) else { return nil }
        let offset = track.offset ?? 0
        return track.line.map { line in
            guard track.synced, let start = line.start, start.isFinite, offset.isFinite else { return line.value }
            let milliseconds = Int(min(59_999_999, max(0, start - offset)).rounded())
            return String(format: "[%02d:%02d.%03d]", milliseconds / 60000, (milliseconds / 1000) % 60, milliseconds % 1000) + line.value
        }.joined(separator: "\n")
    }
}
