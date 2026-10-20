import Foundation
// Playback boundary rules are independent of AVPlayer and can be tested on Linux.
public enum PlaybackRules {
    public static func nextIndex(current: Int?, count: Int) -> Int? {
        guard let current, current >= 0, current < count - 1 else { return nil }
        return current + 1
    }
    public static func seekTime(_ time: Double, duration: Double) -> Double {
        guard time.isFinite, duration.isFinite, duration > 0 else { return 0 }
        return min(max(0, time), duration)
    }
}
public enum ServerAddress {
    public enum ValidationError: Error, LocalizedError {
        case invalid
        public var errorDescription: String? { "请输入不含账号密码的 HTTPS 服务器地址。" }
    }
    public static func validate(_ text: String) throws -> URL {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw ValidationError.invalid
        }
        return url
    }
}
