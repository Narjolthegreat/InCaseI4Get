import Foundation
import SwiftData
import SwiftUI

@main
struct InCaseI4GetApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settings = AppSettings()
    private let modelContainer: ModelContainer

    init() {
        let isUITesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")
        let configuration = ModelConfiguration(isStoredInMemoryOnly: isUITesting)

        do {
            modelContainer = try ModelContainer(
                for: ReminderItem.self,
                configurations: configuration
            )
        } catch {
            fatalError("Unable to create model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(settings)
        }
        .modelContainer(modelContainer)
    }
}
