import SwiftUI
import SwiftData

@main
struct PrompterApp: App {
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            ScriptListView()
                .environmentObject(settings)
                .preferredColorScheme(.dark)
                .tint(.accentGold)
        }
        .modelContainer(for: Script.self)
    }
}
