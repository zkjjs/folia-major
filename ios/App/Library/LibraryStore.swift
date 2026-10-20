import Foundation
import AVFoundation
import Observation
import UIKit
import FoliaCore
// Imported audio is copied into the app so file-provider access survives relaunch.
@MainActor @Observable final class LibraryStore {
    var tracks: [Track] = []
    var error: String?
    var importing = false
    private var loadFailed = false
    let documents: URL
    private var indexURL: URL { documents.appendingPathComponent("library.json") }
    init() {
        documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        do {
            try FileManager.default.createDirectory(at: documents.appendingPathComponent("Music"), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: indexURL.path) {
                tracks = try JSONDecoder().decode([Track].self, from: Data(contentsOf: indexURL))
            }
        } catch {
            loadFailed = true
            self.error = "读取音乐库失败，原索引已保留。请先通过“文件”备份 library.json。"
        }
    }
    func url(for track: Track) -> URL {
        documents.appendingPathComponent(track.location)
    }
    private func save(_ next: [Track]) throws {
        guard !loadFailed else { throw CocoaError(.fileReadCorruptFile) }
        try JSONEncoder().encode(next).write(to: indexURL, options: .atomic)
        tracks = next
    }
    func importAudio(_ urls: [URL]) async {
        guard !importing else { return }
        importing = true
        defer { importing = false }
        for source in urls {
            let granted = source.startAccessingSecurityScopedResource()
            defer { if granted { source.stopAccessingSecurityScopedResource() } }
            let id = UUID().uuidString
            let relative = "Music/" + id + "." + source.pathExtension
            let destination = documents.appendingPathComponent(relative)
            do {
                guard !loadFailed else { throw CocoaError(.fileReadCorruptFile) }
                try await Task.detached {
                    try FileManager.default.copyItem(at: source, to: destination)
                }.value
                let asset = AVURLAsset(url: destination)
                let metadata = (try? await asset.load(.commonMetadata)) ?? []
                var title = source.deletingPathExtension().lastPathComponent
                var artist = ""; var album = ""; var artwork: String?
                for item in metadata {
                    if item.commonKey == .commonKeyTitle, let value = try? await item.load(.stringValue) { title = value }
                    if item.commonKey == .commonKeyArtist, let value = try? await item.load(.stringValue) { artist = value }
                    if item.commonKey == .commonKeyAlbumName, let value = try? await item.load(.stringValue) { album = value }
                    if item.commonKey == .commonKeyArtwork, let data = try? await item.load(.dataValue),
                       let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.8) {
                        let path = "Music/" + id + ".jpg"
                        try jpeg.write(to: documents.appendingPathComponent(path), options: .atomic)
                        artwork = path
                    }
                }
                let song = Track(id: id, title: title, artist: artist, album: album, source: .local,
                                 location: relative, artwork: artwork, lyric: nil)
                try save(tracks + [song])
            } catch {
                self.error = "导入“" + source.lastPathComponent + "”失败：" + error.localizedDescription
            }
        }
    }
    func attachLyrics(_ text: String, to id: String) {
        var next = tracks
        guard let index = next.firstIndex(where: { $0.id == id }) else { return }
        next[index].lyric = text
        do { try save(next) } catch { self.error = error.localizedDescription }
    }
}
