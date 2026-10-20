import SwiftUI
// Native scene owns the library, server connection and playback session.
@main struct FoliaApp: App {
    @State private var library = LibraryStore()
    @State private var server = NavidromeClient()
    @State private var player = PlayerStore()
    var body: some Scene {
        WindowGroup {
            RootView(library: library, server: server, player: player)
        }
    }
}
