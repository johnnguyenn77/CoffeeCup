import Combine
import Foundation

struct DemoDevice: Identifiable, Equatable {
    let id: String
    let name: String
}

/// Session-only UI state. Deliberately has no system controllers or persisted preferences.
@MainActor
final class CleanPopoverDemoState: ObservableObject {
    static let availableDisplays = [
        DemoDevice(id: "display-1", name: "Studio Display"),
        DemoDevice(id: "display-2", name: "Desk Monitor")
    ]
    static let availableKeyboards = [
        DemoDevice(id: "keyboard-1", name: "External Keyboard"),
        DemoDevice(id: "keyboard-2", name: "Travel Keyboard")
    ]

    @Published var keepsDisplayAwake = false
    @Published var launchesAtLogin = false
    @Published var updateAvailable = false
    @Published private(set) var catModeActive = false
    @Published private(set) var displayCount = 1
    @Published private(set) var keyboardCount = 1
    @Published private(set) var selectedDisplayID = "display-1"
    @Published private(set) var selectedKeyboardID = "keyboard-1"
    @Published private var rotations: [String: Int] = [:]
    @Published private var modifierSwaps: [String: Bool] = [:]

    var displays: [DemoDevice] { Array(Self.availableDisplays.prefix(displayCount)) }
    var keyboards: [DemoDevice] { Array(Self.availableKeyboards.prefix(keyboardCount)) }
    var selectedKeyboard: DemoDevice? { keyboards.first { $0.id == selectedKeyboardID } }
    var currentRotation: Int { rotations[selectedDisplayID] ?? 0 }
    var swapsModifiers: Bool { selectedKeyboard != nil && (modifierSwaps[selectedKeyboardID] ?? false) }

    func setDisplayCount(_ count: Int) {
        displayCount = max(0, min(count, Self.availableDisplays.count))
        if !displays.contains(where: { $0.id == selectedDisplayID }), let first = displays.first {
            selectedDisplayID = first.id
        }
    }

    func setKeyboardCount(_ count: Int) {
        keyboardCount = max(0, min(count, Self.availableKeyboards.count))
        if !keyboards.contains(where: { $0.id == selectedKeyboardID }), let first = keyboards.first {
            selectedKeyboardID = first.id
        }
    }

    func selectDisplay(_ id: String) {
        guard displays.contains(where: { $0.id == id }) else { return }
        selectedDisplayID = id
    }

    func selectKeyboard(_ id: String) {
        guard keyboards.contains(where: { $0.id == id }) else { return }
        selectedKeyboardID = id
    }

    func setRotation(_ degrees: Int) {
        guard !displays.isEmpty, [270, 0, 90].contains(degrees) else { return }
        rotations[selectedDisplayID] = degrees
    }

    func setSwapEnabled(_ enabled: Bool) {
        guard selectedKeyboard != nil else { return }
        modifierSwaps[selectedKeyboardID] = enabled
    }

    func setCatMode(_ enabled: Bool) { catModeActive = enabled }

    func reset() {
        keepsDisplayAwake = false
        launchesAtLogin = false
        updateAvailable = false
        catModeActive = false
        displayCount = 1
        keyboardCount = 1
        selectedDisplayID = "display-1"
        selectedKeyboardID = "keyboard-1"
        rotations = [:]
        modifierSwaps = [:]
    }
}
