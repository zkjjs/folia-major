import Foundation
import AVFoundation
import MediaPlayer
import Observation
import UIKit
import FoliaCore
// AVPlayer is the only audio clock; the WebView renders pictures without playing media.
@MainActor @Observable final class PlayerStore {
    var queue: [Track] = []
    var index: Int?
    var time: Double = 0
    var duration: Double = 0
    var playing = false
    var lyrics = ""
    var error: String?
    var current: Track? {
        guard let index, queue.indices.contains(index) else { return nil }
        return queue[index]
    }
    @ObservationIgnored private let audio = AVPlayer()
    @ObservationIgnored private var periodic: Any?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var rateObservation: NSKeyValueObservation?
    @ObservationIgnored private var notifications: [NSObjectProtocol] = []
    @ObservationIgnored private var library: LibraryStore?
    @ObservationIgnored private var server: NavidromeClient?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var resumeAfterInterruption = false
    init() {
        periodic = audio.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] value in
            Task { @MainActor in
                guard let self else { return }
                self.time = value.seconds.isFinite ? max(0, value.seconds) : 0
                let length = self.audio.currentItem?.duration.seconds ?? 0
                self.duration = length.isFinite ? max(0, length) : 0
                self.publishNowPlaying()
            }
        }
        rateObservation = audio.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                self.playing = self.audio.timeControlStatus == .playing
                self.publishNowPlaying()
            }
        }
        notifications.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] note in
            guard let item = note.object as? AVPlayerItem else { return }
            Task { @MainActor in
                guard let self, item === self.audio.currentItem else { return }
                self.next()
            }
        })
        notifications.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor in
                guard let self, let type else { return }
                if type == AVAudioSession.InterruptionType.began.rawValue {
                    self.resumeAfterInterruption = self.playing
                    self.pause()
                } else if self.resumeAfterInterruption && AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                    self.resumeAfterInterruption = false; self.resume()
                }
            }
        })
        notifications.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                Task { @MainActor in self?.pause() }
            }
        })
        let remote = MPRemoteCommandCenter.shared()
        remote.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.resume() }; return .success }
        remote.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        remote.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }
        remote.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        remote.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.previous() }; return .success }
        remote.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor in self?.seek(position) }
            return .success
        }
    }
    func configure(library: LibraryStore, server: NavidromeClient) {
        self.library = library; self.server = server
    }
    func play(_ track: Track, in tracks: [Track]) {
        queue = tracks; index = tracks.firstIndex(where: { $0.id == track.id })
        loadCurrent()
    }
    func playQueueIndex(_ value: Int) {
        guard queue.indices.contains(value) else { return }
        index = value; loadCurrent()
    }
    private func loadCurrent() {
        loadTask?.cancel()
        audio.pause(); audio.replaceCurrentItem(with: nil)
        statusObservation = nil; time = 0; duration = 0; lyrics = ""
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        guard let track = current else { return }
        do {
            let url: URL
            if track.source == .local {
                guard let library else { return }
                url = library.url(for: track)
            } else {
                guard let server else { return }
                url = try server.endpoint("stream", params: ["id": track.location])
            }
            let item = AVPlayerItem(url: url)
            audio.replaceCurrentItem(with: item)
            statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                let failed = item.status == .failed
                Task { @MainActor in
                    guard let self, self.audio.currentItem === item, failed else { return }
                    self.error = "无法播放这首歌曲，请检查文件格式、网络或服务器权限。"
                    self.pause()
                }
            }
            lyrics = track.lyric ?? ""
            publishNowPlaying()
            resume()
            loadTask = Task { [weak self] in
                guard let self else { return }
                if track.source == .navidrome, let text = await self.server?.lyrics(for: track),
                   !Task.isCancelled, self.current?.id == track.id { self.lyrics = text }
                let image = await self.artwork(for: track)
                guard !Task.isCancelled, self.current?.id == track.id else { return }
                if let image {
                    var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                    info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                }
            }
        } catch { self.error = error.localizedDescription }
    }
    func resume() {
        guard current != nil else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            if duration > 0 && time >= duration { seek(0) }
            audio.play()
        } catch { self.error = error.localizedDescription }
    }
    func pause() { audio.pause(); playing = false; publishNowPlaying() }
    func toggle() { if playing { pause() } else { resume() } }
    func seek(_ value: Double) {
        let target = PlaybackRules.seekTime(value, duration: duration)
        audio.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        time = target; publishNowPlaying()
    }
    func next() {
        guard let next = PlaybackRules.nextIndex(current: index, count: queue.count) else { pause(); return }
        index = next; loadCurrent()
    }
    func previous() {
        if time > 3 { seek(0); return }
        guard let index, index > 0 else { seek(0); return }
        self.index = index - 1; loadCurrent()
    }
    func resetServerSession() {
        guard PlaybackRules.needsServerReset(queue) else { return }
        loadTask?.cancel(); audio.pause(); audio.replaceCurrentItem(with: nil)
        statusObservation = nil; queue = []; index = nil; time = 0; duration = 0
        lyrics = ""; playing = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
    func setLyrics(_ text: String) {
        lyrics = text
        if let id = current?.id { queue = PlaybackRules.queueByAttachingLyrics(text, to: id, in: queue) }
        if let current, current.source == .local { library?.attachLyrics(text, to: current.id) }
    }
    func artwork(for track: Track) async -> UIImage? {
        guard let art = track.artwork else { return nil }
        if track.source == .local, let library {
            return UIImage(contentsOfFile: library.documents.appendingPathComponent(art).path)
        }
        guard let url = try? server?.endpoint("getCoverArt", params: ["id": art, "size": "600"]),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return UIImage(data: data)
    }
    private func publishNowPlaying() {
        guard let track = current else { return }
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        if info[MPMediaItemPropertyTitle] as? String != track.title { info.removeValue(forKey: MPMediaItemPropertyArtwork) }
        info[MPMediaItemPropertyTitle] = track.title
        info[MPMediaItemPropertyArtist] = track.artist
        info[MPMediaItemPropertyAlbumTitle] = track.album
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = time
        info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
