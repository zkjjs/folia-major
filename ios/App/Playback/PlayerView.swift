import SwiftUI
import UniformTypeIdentifiers
// Native playback controls remain usable independently of lyric-page rendering.
struct PlayerView: View {
    let player: PlayerStore
    @Environment(\.dismiss) private var dismiss
    @State private var showLyrics = false
    @State private var showQueue = false
    @State private var importLyrics = false
    @State private var lyricTargetID: String?
    @State private var dragging = false
    @State private var draftTime = 0.0
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 26) {
                    if let track = player.current {
                        ArtworkView(track: track, player: player)
                            .frame(width: 240, height: 240).clipShape(.rect(cornerRadius: 25))
                            .shadow(color: .indigo.opacity(0.25), radius: 28, y: 15)
                            .padding(.top, 30)
                        VStack(spacing: 7) {
                            Text(track.title).font(.title2.bold()).multilineTextAlignment(.center)
                            Text(track.artist.isEmpty ? "未知歌手" : track.artist).foregroundStyle(.secondary)
                        }
                        VStack(spacing: 8) {
                            Slider(value: Binding(get: { dragging ? draftTime : min(player.time, max(player.duration, 1)) },
                                                  set: { draftTime = $0 }),
                                   in: 0...max(player.duration, 1)) { editing in
                                dragging = editing
                                if !editing { player.seek(draftTime) } else { draftTime = player.time }
                            }.disabled(player.duration <= 0).tint(.primary)
                            HStack {
                                Text(clock(dragging ? draftTime : player.time))
                                Spacer()
                                Text("-" + clock(max(0, player.duration - (dragging ? draftTime : player.time))))
                            }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        PlaybackControls(player: player)
                        HStack(spacing: 20) {
                            Button("动态歌词", systemImage: "quote.bubble") { showLyrics = true }
                            Spacer()
                            Button("队列", systemImage: "list.bullet") { showQueue = true }
                        }.buttonStyle(.glass).padding(.top, 10)
                        if player.lyrics.isEmpty {
                            Button("导入歌词", systemImage: "doc.badge.plus") { beginLyricsImport() }
                                .font(.subheadline)
                            Text("支持 LRC、TTML、VTT；导入歌词只关联当前歌曲。")
                                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                    }
                }.padding(.horizontal, 32).padding(.bottom, 32)
            }
            .background(LinearGradient(colors: [.indigo.opacity(0.12), .clear], startPoint: .top, endPoint: .bottom))
            .navigationTitle("正在播放").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭", systemImage: "chevron.down") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("更多", systemImage: "ellipsis") { Button("导入或替换歌词") { beginLyricsImport() } }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .fullScreenCover(isPresented: $showLyrics) { LyricsScene(player: player) }
        .sheet(isPresented: $showQueue) {
            NavigationStack {
                List(Array(player.queue.enumerated()), id: \.element.id) { item in
                    Button { player.playQueueIndex(item.offset) } label: {
                        HStack {
                            Text(item.element.title).foregroundStyle(.primary)
                            Spacer()
                            if item.offset == player.index { Image(systemName: "waveform") }
                        }
                    }
                }.navigationTitle("播放队列")
                    .toolbar { Button("完成") { showQueue = false } }
            }
        }
        .fileImporter(isPresented: $importLyrics, allowedContentTypes: [.plainText, .xml, .data]) { result in
            let targetID = lyricTargetID
            do {
                let url = try result.get()
                let granted = url.startAccessingSecurityScopedResource()
                defer { if granted { url.stopAccessingSecurityScopedResource() } }
                let attributes = try url.resourceValues(forKeys: [.fileSizeKey])
                guard (attributes.fileSize ?? 0) <= 2_000_000 else { player.error = "歌词文件过大，请选择小于 2 MB 的文本歌词。"; return }
                let text = try String(contentsOf: url, encoding: .utf8)
                guard player.current?.id == targetID else { return }
                player.setLyrics(text)
            } catch { player.error = "读取歌词失败：" + error.localizedDescription }
        }
    }
    private func beginLyricsImport() {
        lyricTargetID = player.current?.id
        importLyrics = true
    }
    private func clock(_ value: Double) -> String {
        let seconds = value.isFinite ? Int(max(0, min(value, 359999))) : 0
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
struct PlaybackControls: View {
    let player: PlayerStore
    var body: some View {
        HStack(spacing: 46) {
            Button("上一首", systemImage: "backward.fill") { player.previous() }.font(.title)
            Button(player.playing ? "暂停" : "播放", systemImage: player.playing ? "pause.fill" : "play.fill") { player.toggle() }
                .font(.system(size: 40)).frame(width: 72, height: 72)
                .buttonStyle(.glassProminent).tint(.indigo)
            Button("下一首", systemImage: "forward.fill") { player.next() }.font(.title)
        }.labelStyle(.iconOnly).foregroundStyle(.primary)
    }
}
struct LyricsScene: View {
    let player: PlayerStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            LyricsWebView(player: player, time: player.time, duration: player.duration, playing: player.playing, lyric: player.lyrics, active: phase == .active, dark: colorScheme == .dark)
                .ignoresSafeArea(edges: .horizontal)
            VStack {
                HStack {
                    Button("返回", systemImage: "chevron.down") { dismiss() }.labelStyle(.iconOnly).buttonStyle(.glass)
                    Spacer()
                    Text(player.current?.title ?? "").font(.subheadline).lineLimit(1)
                    Spacer()
                }.padding()
                Spacer()
                if player.lyrics.isEmpty {
                    ContentUnavailableView("暂无歌词", systemImage: "quote.bubble",
                        description: Text("返回播放页，为当前歌曲导入歌词。")).foregroundStyle(.white)
                    Spacer()
                }
                PlaybackControls(player: player).padding(.bottom, 24)
            }
        }.preferredColorScheme(.dark)
    }
}
