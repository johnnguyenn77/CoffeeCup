import Foundation
import AppKit
import Combine
import ServiceManagement

@MainActor
final class CoffeeCupController: ObservableObject {
    static let shared = CoffeeCupController()

    private static let launchAtLoginPreferenceKey = "CoffeeCup.launchAtLogin"
    private static let lastUpdateCheckKey = "CoffeeCup.lastUpdateCheckAt"
    private static let availableUpdateVersionKey = "CoffeeCup.availableUpdateVersion"
    private static let availableUpdateDMGURLKey = "CoffeeCup.availableUpdateDMGURL"
    private static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/johnnguyenn77/CoffeeCup/releases/latest"
    )!

    @Published private(set) var isActive = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var launchesAtLogin = false
    @Published private(set) var updateAvailableVersion: String?
    @Published private(set) var updateDMGURL: URL?

    private var process: Process?
    private var updateCheckTask: Task<Void, Never>?
    private var weeklyUpdateCheckTask: Task<Void, Never>?
    private var isCheckingForUpdates = false

    init() {
        updateAvailableVersion = UserDefaults.standard.string(forKey: Self.availableUpdateVersionKey)
        updateDMGURL = nil
        if let savedURL = UserDefaults.standard.string(forKey: Self.availableUpdateDMGURLKey) {
            updateDMGURL = URL(string: savedURL)
        }

        if let updateAvailableVersion,
           let installedVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
           !Self.isNewerVersion(updateAvailableVersion, than: installedVersion) {
            self.updateAvailableVersion = nil
            updateDMGURL = nil
            UserDefaults.standard.removeObject(forKey: Self.availableUpdateVersionKey)
            UserDefaults.standard.removeObject(forKey: Self.availableUpdateDMGURLKey)
        }

        restoreLaunchAtLoginIfNeeded()
        refreshLoginItemStatus()
    }

    func startWeeklyUpdateChecks() {
        guard weeklyUpdateCheckTask == nil else { return }

        if isUpdateCheckDue(at: Date()) {
            updateCheckTask = Task { [weak self] in
                await self?.checkForUpdates()
            }
        }

        scheduleNextWeeklyUpdateCheck()
    }

    func downloadUpdateDMG() {
        guard let updateDMGURL else { return }
        NSWorkspace.shared.open(updateDMGURL)
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
        caffeinate.arguments = ["-d"]
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

    private func checkForUpdates() async {
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        defer { isCheckingForUpdates = false }

        var request = URLRequest(url: Self.latestReleaseURL)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("CoffeeCup macOS app", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  response.statusCode == 200 else { return }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

            guard let installedVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                  Self.isNewerVersion(release.tagName, than: installedVersion) else {
                clearAvailableUpdate()
                UserDefaults.standard.set(Date(), forKey: Self.lastUpdateCheckKey)
                return
            }

            guard let dmgURL = release.assets.first(where: { $0.name == "CoffeeCup.dmg" })?.downloadURL else {
                return
            }

            updateAvailableVersion = release.tagName
            updateDMGURL = dmgURL
            UserDefaults.standard.set(release.tagName, forKey: Self.availableUpdateVersionKey)
            UserDefaults.standard.set(dmgURL.absoluteString, forKey: Self.availableUpdateDMGURLKey)
            UserDefaults.standard.set(Date(), forKey: Self.lastUpdateCheckKey)
        } catch {
            // A failed network check is retried on the next launch or Wednesday.
        }
    }

    private func clearAvailableUpdate() {
        updateAvailableVersion = nil
        updateDMGURL = nil
        UserDefaults.standard.removeObject(forKey: Self.availableUpdateVersionKey)
        UserDefaults.standard.removeObject(forKey: Self.availableUpdateDMGURLKey)
    }

    private func scheduleNextWeeklyUpdateCheck() {
        var components = DateComponents()
        components.weekday = 4 // Foundation weekday numbering: Sunday is 1, Wednesday is 4.
        components.hour = 9
        components.minute = 0
        components.second = 0

        let calendar = Calendar.current
        guard let nextWednesday = calendar.nextDate(
            after: Date(),
            matching: components,
            matchingPolicy: .nextTime,
            direction: .forward
        ) else { return }

        let delay = max(1, nextWednesday.timeIntervalSinceNow)
        weeklyUpdateCheckTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }

            guard let self else { return }
            self.weeklyUpdateCheckTask = nil
            await self.checkForUpdates()
            self.scheduleNextWeeklyUpdateCheck()
        }
    }

    private func isUpdateCheckDue(at now: Date) -> Bool {
        guard let lastCheck = UserDefaults.standard.object(forKey: Self.lastUpdateCheckKey) as? Date else {
            return true
        }

        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: now)
        let daysSinceWednesday = (weekday - 4 + 7) % 7
        guard let wednesday = calendar.date(
            byAdding: .day,
            value: -daysSinceWednesday,
            to: calendar.startOfDay(for: now)
        ), let scheduledTime = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: wednesday) else {
            return false
        }

        let mostRecentScheduledCheck = now >= scheduledTime
            ? scheduledTime
            : calendar.date(byAdding: .day, value: -7, to: scheduledTime) ?? scheduledTime
        return lastCheck < mostRecentScheduledCheck
    }

    private static func isNewerVersion(_ candidate: String, than installed: String) -> Bool {
        func components(_ version: String) -> [Int]? {
            let versionWithoutPrefix = version.hasPrefix("v") ? String(version.dropFirst()) : version
            let numericVersion = versionWithoutPrefix.split(separator: "-", maxSplits: 1).first.map(String.init)
                ?? versionWithoutPrefix
            let parts = numericVersion.split(separator: ".")
            guard !parts.isEmpty, parts.allSatisfy({ Int($0) != nil }) else { return nil }
            return parts.compactMap { Int($0) }
        }

        guard let candidateParts = components(candidate),
              let installedParts = components(installed) else { return false }

        for index in 0..<max(candidateParts.count, installedParts.count) {
            let candidatePart = index < candidateParts.count ? candidateParts[index] : 0
            let installedPart = index < installedParts.count ? installedParts[index] : 0
            if candidatePart != installedPart {
                return candidatePart > installedPart
            }
        }
        return false
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let downloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case downloadURL = "browser_download_url"
    }
}
