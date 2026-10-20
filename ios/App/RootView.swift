import SwiftUI
import UniformTypeIdentifiers
import FoliaCore
// System tabs supply Liquid Glass navigation and keep the mini player above the tab bar.
struct RootView: View {
    let library: LibraryStore
    let server: NavidromeClient
    let player: PlayerStore
    @State private var showImporter = false
    @State private var showPlayer = false
    @State private var search = ""
    @AppStorage("appearance") private var appearance = 0
    private var filtered: [Track] {
        library.tracks.filter { search.isEmpty || ($0.title + $0.artist).localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        TabView {
            Tab("音乐库", systemImage: "music.note.house.fill") {
                NavigationStack {
                    List {
                        if library.importing {
                            HStack { ProgressView(); Text("正在导入音乐…") }
                        }
                        if library.tracks.isEmpty && !library.importing {
                            ContentUnavailableView {
                                Label("把喜欢的音乐带进来", systemImage: "waveform")
                            } description: {
                                Text("从“文件”导入歌曲，连接 Navidrome，开启沉浸式歌词。")
                            } actions: {
                                Button("导入音乐", systemImage: "plus") { showImporter = true }
                                    .buttonStyle(.borderedProminent)
                            }.listRowBackground(Color.clear)
                        }
                        ForEach(filtered) { track in
                            Button {
                                player.play(track, in: filtered)
                            } label: {
                                TrackRow(track: track, player: player, isCurrent: player.current?.id == track.id)
                            }.buttonStyle(.plain)
                        }
                    }
                    .navigationTitle("音乐库")
                    .searchable(text: $search, prompt: "搜索歌曲或歌手")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("导入音乐", systemImage: "plus") { showImporter = true }
                                .disabled(library.importing)
                        }
                    }
                }
            }
            Tab("服务器", systemImage: "network") {
                NavidromeView(server: server, player: player)
            }
            Tab("设置", systemImage: "slider.horizontal.3") {
                NavigationStack {
                    Form {
                        Section("外观") {
                            Picker("显示模式", selection: $appearance) {
                                Text("跟随系统").tag(0)
                                Text("浅色").tag(1)
                                Text("深色").tag(2)
                            }
                        }
                        Section("Folia iOS") {
                            LabeledContent("版本", value: "0.1.0")
                            Text("动态歌词使用 Folia 原版流光渲染器。可在播放页导入 LRC、TTML 或 VTT 歌词。")
                                .foregroundStyle(.secondary)
                            Link("项目源码与许可证", destination: URL(string: "https://github.com/zkjjs/folia-major/tree/codex/folia-ios")!)
                            Link("原作 Folia", destination: URL(string: "https://github.com/chthollyphile/folia-major")!)
                            Text("基于 Folia，按 AGPL-3.0 发布。").font(.footnote).foregroundStyle(.secondary)
                        }
                    }.navigationTitle("设置")
                }
            }
        }
        .tint(.indigo)
        .tabViewBottomAccessory {
            if let current = player.current {
                HStack(spacing: 12) {
                    Button { showPlayer = true } label: {
                        HStack(spacing: 10) {
                            ArtworkView(track: current, player: player).frame(width: 38, height: 38).clipShape(.rect(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(current.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text(current.artist.isEmpty ? "本地音乐" : current.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("打开播放页")
                    Button(player.playing ? "暂停" : "播放", systemImage: player.playing ? "pause.fill" : "play.fill") {
                        player.toggle()
                    }.labelStyle(.iconOnly).font(.title3)
                    Button("下一首", systemImage: "forward.fill") { player.next() }
                        .labelStyle(.iconOnly).padding(.trailing, 6)
                }.padding(.horizontal, 12).padding(.vertical, 7)
            }
        }
        .preferredColorScheme(appearance == 1 ? .light : appearance == 2 ? .dark : nil)
        .sheet(isPresented: $showPlayer) { PlayerView(player: player) }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): Task { await library.importAudio(urls) }
            case .failure(let error): library.error = error.localizedDescription
            }
        }
        .alert("提示", isPresented: Binding(get: { player.error != nil || library.error != nil },
            set: { if !$0 { player.error = nil; library.error = nil } })) {
            Button("好") { player.error = nil; library.error = nil }
        } message: { Text(player.error ?? library.error ?? "") }
        .task {
            player.configure(library: library, server: server)
        }
    }
}
struct TrackRow: View {
    let track: Track
    let player: PlayerStore
    var isCurrent = false
    var body: some View {
        HStack(spacing: 13) {
            ArtworkView(track: track, player: player).frame(width: 50, height: 50).clipShape(.rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 5) {
                Text(track.title).font(.body.weight(.medium)).lineLimit(1)
                Text(track.artist.isEmpty ? "未知歌手" : track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if isCurrent { Image(systemName: "waveform").foregroundStyle(.indigo).accessibilityLabel("正在播放") }
        }.padding(.vertical, 4).contentShape(Rectangle())
    }
}
struct ArtworkView: View {
    let track: Track
    let player: PlayerStore
    @State private var image: UIImage?
    var body: some View {
        ZStack {
            LinearGradient(colors: [.indigo, .purple.opacity(0.65), .blue.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else { Image(systemName: "music.note").font(.title).foregroundStyle(.white.opacity(0.8)) }
        }.clipped()
        .task(id: track.id) { image = nil; let loaded = await player.artwork(for: track); if !Task.isCancelled { image = loaded } }
        .accessibilityHidden(true)
    }
}
