import Foundation
import Combine
import ServiceManagement

@MainActor
final class CoffeeCupController: ObservableObject {
    static let shared = CoffeeCupController()

    private static let launchAtLoginPreferenceKey = "CoffeeCup.launchAtLogin"

    @Published private(set) var isActive = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var launchesAtLogin = false

    private var process: Process?

    init() {
        restoreLaunchAtLoginIfNeeded()
        refreshLoginItemStatus()
    }

    func setActive(_ active: Bool) {
        active ? start() : stop()
    }

    private func start() {
        guard process?.isRunning != true else {
            isActive = true
            return
        }

        let caffeinate = Process()
        caffeinate.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        caffeinate.arguments = ["-dimsu"]
        caffeinate.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.process?.isRunning != true else { return }
                self.process = nil
                self.isActive = false
            }
        }

        do {
            try caffeinate.run()
            process = caffeinate
            errorMessage = nil
            isActive = true
        } catch {
            process = nil
            isActive = false
            errorMessage = "Could not start caffeinate: \(error.localizedDescription)"
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        isActive = false
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.launchAtLoginPreferenceKey)

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }

            refreshLoginItemStatus()

            if enabled && !launchesAtLogin {
                errorMessage = "Allow CoffeeCup in System Settings → General → Login Items."
            } else {
                errorMessage = nil
            }
        } catch {
            refreshLoginItemStatus()
            errorMessage = "Could not update Login Items: \(error.localizedDescription)"
        }
    }

    deinit {
        process?.terminate()
    }

    func refreshLoginItemStatus() {
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func restoreLaunchAtLoginIfNeeded() {
        let service = SMAppService.mainApp
        let savedPreference = UserDefaults.standard.object(
            forKey: Self.launchAtLoginPreferenceKey
        ) as? Bool

        // Migrate an existing enabled login item from versions that did not
        // persist the user's preference yet.
        if savedPreference == nil {
            if service.status == .enabled {
                UserDefaults.standard.set(true, forKey: Self.launchAtLoginPreferenceKey)
            }
            return
        }

        guard savedPreference == true, service.status != .enabled else { return }

        // Re-register after an app replacement. UserDefaults survives app
        // updates because it is stored outside the application bundle.
        try? service.register()
    }
}
