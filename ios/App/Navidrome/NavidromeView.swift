import SwiftUI
// Connection credentials are submitted to native transport rather than a web login page.
struct NavidromeView: View {
    let server: NavidromeClient
    let player: PlayerStore
    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var search = ""
    var body: some View {
        NavigationStack {
            List {
                if !server.connected {
                    Section("连接 Navidrome") {
                        TextField("https://music.example.com", text: $address)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("用户名", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("密码", text: $password)
                        Button("连接服务器") {
                            Task { await server.connect(address: address, username: username, password: password); if server.connected { password = "" } }
                        }.disabled(server.loading)
                        Text("填写 HTTPS 地址，支持带路径的反向代理。登录信息保存在本机钥匙串。").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let error = server.error { Section { Text(error).foregroundStyle(.red) } }
                if server.loading { ProgressView("正在加载…") }
                if server.connected {
                    let filtered = server.tracks.filter { search.isEmpty || ($0.title + $0.artist).localizedCaseInsensitiveContains(search) }
                    ForEach(filtered) { track in
                        Button { player.play(track, in: filtered) } label: {
                            TrackRow(track: track, player: player, isCurrent: player.current?.id == track.id)
                        }.buttonStyle(.plain)
                    }
                    if server.hasMore {
                        Button("加载更多") { Task { await server.loadMore() } }.disabled(server.loading)
                    } else if server.tracks.isEmpty && !server.loading {
                        ContentUnavailableView("曲库为空", systemImage: "music.note", description: Text("请检查服务器中的音乐库及账号权限。"))
                    }
                }
            }
            .navigationTitle("Navidrome")
            .searchable(text: $search, prompt: "搜索已加载的歌曲")
            .toolbar {
                if server.connected {
                    Button("断开") { player.pause(); server.disconnect() }
                }
            }
            .task {
                address = server.savedAddress; username = server.savedUsername
                await server.reconnect()
            }
        }
    }
}
