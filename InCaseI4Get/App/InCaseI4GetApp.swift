import SwiftData
import SwiftUI

@main
struct InCaseI4GetApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(settings)
        }
        .modelContainer(for: ReminderItem.self)
    }
}
