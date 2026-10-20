import Foundation
import CryptoKit
import Security
import Observation
import FoliaCore
// HTTPS Subsonic transport: credentials stay native and never enter the lyric WebView.
@MainActor @Observable final class NavidromeClient {
    struct Credentials: Codable { var address: String; var username: String; var password: String }
    struct RemoteError: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }
    var tracks: [Track] = []
    var connected = false
    var loading = false
    var error: String?
    var hasMore = false
    private var credentials: Credentials?
    private var generation = UUID()
    private let keychainKey = "com.zkjjs.folia.navidrome"
    var savedAddress: String { credentials?.address ?? "" }
    var savedUsername: String { credentials?.username ?? "" }
    init() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainKey, kSecAttrAccount as String: "server",
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data {
            credentials = try? JSONDecoder().decode(Credentials.self, from: data)
        }
    }
    func connect(address: String, username: String, password: String) async {
        guard !loading else { return }
        let old = credentials
        do {
            let base = try ServerAddress.validate(address)
            guard !username.isEmpty, !password.isEmpty else { throw RemoteError(message: "请输入账号和密码。") }
            credentials = Credentials(address: base.absoluteString, username: username, password: password)
            loading = true; error = nil
            defer { loading = false }
            _ = try await request("ping")
            try persistCredentials()
            generation = UUID()
            tracks = []; connected = true; hasMore = true
        } catch { credentials = old; self.error = error.localizedDescription; return }
        await loadMore()
    }
    func reconnect() async {
        guard let c = credentials, !connected else { return }
        await connect(address: c.address, username: c.username, password: c.password)
    }
    func disconnect() {
        generation = UUID(); credentials = nil; tracks = []; connected = false; hasMore = false
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainKey, kSecAttrAccount as String: "server"]
        SecItemDelete(query as CFDictionary)
    }
    private func persistCredentials() throws {
        guard let credentials else { return }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainKey, kSecAttrAccount as String: "server"]
        let data = try JSONEncoder().encode(credentials)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query; add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw RemoteError(message: "无法安全保存登录信息。") }
        } else if status != errSecSuccess { throw RemoteError(message: "无法更新登录信息。") }
    }
    func endpoint(_ method: String, params: [String: String] = [:]) throws -> URL {
        guard let c = credentials else { throw RemoteError(message: "请先连接 Navidrome。") }
        let base = try ServerAddress.validate(c.address)
        let salt = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let token = Insecure.MD5.hash(data: Data((c.password + salt).utf8)).map { String(format: "%02x", $0) }.joined()
        let url = base.appendingPathComponent("rest").appendingPathComponent(method + ".view")
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw RemoteError(message: "服务器地址无效。") }
        var values = params
        values.merge(["u": c.username, "t": token, "s": salt, "v": "1.16.1", "c": "Folia-iOS", "f": "json"]) { _, new in new }
        parts.queryItems = values.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let result = parts.url else { throw RemoteError(message: "无法生成请求。") }
        return result
    }
    private func request(_ method: String, params: [String: String] = [:]) async throws -> [String: Any] {
        let url = try endpoint(method, params: params)
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw RemoteError(message: "服务器请求失败，请检查连接。") }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let body = root["subsonic-response"] as? [String: Any] else { throw RemoteError(message: "服务器返回了无法识别的数据。") }
        guard body["status"] as? String == "ok" else {
            let details = body["error"] as? [String: Any]
            throw RemoteError(message: details?["message"] as? String ?? "认证或请求失败。")
        }
        return body
    }
    func loadMore() async {
        guard connected, hasMore, !loading else { return }
        loading = true; error = nil
        let version = generation
        defer { loading = false }
        do {
            let body = try await request("search3", params: ["query": "", "songCount": "100", "songOffset": String(tracks.count), "albumCount": "0", "artistCount": "0"])
            guard version == generation else { return }
            let result = body["searchResult3"] as? [String: Any]
            let songs = result?["song"] as? [[String: Any]] ?? []
            let next: [Track] = songs.compactMap { item in
                guard let id = item["id"] as? String else { return nil }
                return Track(id: "navidrome:" + id, title: item["title"] as? String ?? id,
                    artist: item["artist"] as? String ?? "", album: item["album"] as? String ?? "",
                    source: .navidrome, location: id, artwork: item["coverArt"] as? String, lyric: nil)
            }
            let known = Set(tracks.map(\.id))
            tracks += next.filter { !known.contains($0.id) }
            hasMore = songs.count == 100 && next.contains(where: { !known.contains($0.id) })
        } catch { if version == generation { self.error = error.localizedDescription } }
    }
    func lyrics(for track: Track) async -> String? {
        if let body = try? await request("getLyricsBySongId", params: ["id": track.location]),
           let data = try? JSONSerialization.data(withJSONObject: body),
           let text = try? ServerLyrics.text(from: data), !text.isEmpty { return text }
        guard let body = try? await request("getLyrics", params: ["artist": track.artist, "title": track.title]),
              let lyrics = body["lyrics"] as? [String: Any] else { return nil }
        return lyrics["value"] as? String
    }
}
