import SwiftUI

@MainActor
final class CoffeeCupAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        CoffeeCupController.shared.startWeeklyUpdateChecks()
    }

    func applicationWillTerminate(_ notification: Notification) {
        CoffeeCupController.shared.stop()
    }
}

@main
struct CoffeeCupApp: App {
    @NSApplicationDelegateAdaptor(CoffeeCupAppDelegate.self) private var appDelegate
    @StateObject private var caffeinate = CoffeeCupController.shared

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(caffeinate)
        } label: {
            Image(systemName: caffeinate.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                .accessibilityLabel("CoffeeCup")
        }
        .menuBarExtraStyle(.window)
    }
}
