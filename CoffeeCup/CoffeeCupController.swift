import Foundation
import Combine
import ServiceManagement

@MainActor
final class CoffeeCupController: ObservableObject {
    static let shared = CoffeeCupController()

    @Published private(set) var isActive = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var launchesAtLogin = false

    private var process: Process?

    init() {
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
}
