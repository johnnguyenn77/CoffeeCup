import Foundation

nonisolated struct ModifierKeyMapping: Codable, Equatable, Sendable {
    let source: UInt64
    let destination: UInt64

    static let sourceKey = "HIDKeyboardModifierMappingSrc"
    static let destinationKey = "HIDKeyboardModifierMappingDst"

    static func equivalent(_ lhs: [Self], _ rhs: [Self]) -> Bool {
        if lhs == rhs { return true }
        guard lhs.count == rhs.count else { return false }
        func ordered(_ mappings: [Self]) -> [Self] {
            mappings.sorted { $0.source == $1.source
                ? $0.destination < $1.destination : $0.source < $1.source }
        }
        return ordered(lhs) == ordered(rhs)
    }
}

nonisolated enum WindowsKeyboardMapping {
    // USB HID keyboard usages: left/right Alt (Option) and GUI (Command).
    // Control, Shift, Caps Lock, Fn, and the function row are deliberately unchanged.
    static let swap: [ModifierKeyMapping] = [
        .init(source: 0x7000000E2, destination: 0x7000000E3),
        .init(source: 0x7000000E3, destination: 0x7000000E2),
        .init(source: 0x7000000E6, destination: 0x7000000E7),
        .init(source: 0x7000000E7, destination: 0x7000000E6)
    ]
    static let sources = Set(swap.map(\.source))

    static func applying(to original: [ModifierKeyMapping]) -> [ModifierKeyMapping] {
        original.filter { !sources.contains($0.source) } + swap
    }

    static func isApplied(to mappings: [ModifierKeyMapping]) -> Bool {
        swap.allSatisfy { expected in mappings.filter { $0.source == expected.source } == [expected] }
    }

    static func restoring(original: [ModifierKeyMapping], current: [ModifierKeyMapping]) -> [ModifierKeyMapping] {
        if ModifierKeyMapping.equivalent(current, applying(to: original)) { return original }
        // Restore only keys still set to CoffeeCup's values. Never overwrite a later edit by another app.
        let ownedSources = Set(swap.filter { expected in
            current.filter { $0.source == expected.source } == [expected]
        }.map(\.source))
        return current.filter { !ownedSources.contains($0.source) }
            + original.filter { ownedSources.contains($0.source) }
    }
}

nonisolated struct ExternalKeyboard: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let vendorID: UInt32
    let productID: UInt32
    let locationID: UInt64
    let transport: String
    let hasPointerInterface: Bool
    var serviceIDs: [UInt64]
    var isSelectable = true

    enum USBInputRole: Sendable { case keyboard, pointer, unknown }

    static func usbInputRole(interfaceClass: UInt32?, subclass: UInt32?, protocolCode: UInt32?) -> USBInputRole {
        guard interfaceClass == 3, subclass == 1 else { return .unknown }
        switch protocolCode {
        case 1: return .keyboard
        case 2: return .pointer
        default: return .unknown
        }
    }

    static func shouldOfferModifierSwap(name: String, hasPointerInterface: Bool,
                                       usbRole: USBInputRole) -> Bool {
        switch usbRole {
        case .pointer: return false
        case .keyboard: return true
        case .unknown:
            let name = name.lowercased()
            if ["mouse", "trackpad", "trackball"].contains(where: name.contains) { return false }
            // Ambiguous pointer devices often advertise a helper keyboard for macro buttons.
            // Without physical keyboard evidence, don't offer to remap that helper interface.
            return !hasPointerInterface || name.contains("keyboard")
        }
    }

    static func isPrimaryUSBMouse(interfaceClass: UInt32?, subclass: UInt32?, protocolCode: UInt32?) -> Bool {
        // USB HID boot-mouse protocol on the device's first interface identifies its
        // primary role, unlike extra keyboard reports used for programmable buttons.
        usbInputRole(interfaceClass: interfaceClass, subclass: subclass, protocolCode: protocolCode) == .pointer
    }

    static func preferredBefore(_ lhs: ExternalKeyboard, _ rhs: ExternalKeyboard) -> Bool {
        // Gaming keyboards and mice can both expose keyboard AND pointer services.
        // Prefer a clearly named keyboard; nothing is remapped until the user opts in.
        let lhsNamedKeyboard = lhs.name.localizedCaseInsensitiveContains("keyboard")
        let rhsNamedKeyboard = rhs.name.localizedCaseInsensitiveContains("keyboard")
        if lhsNamedKeyboard != rhsNamedKeyboard { return lhsNamedKeyboard }
        if lhs.hasPointerInterface != rhs.hasPointerInterface { return !lhs.hasPointerInterface }
        let comparison = lhs.name.localizedStandardCompare(rhs.name)
        return comparison == .orderedSame ? lhs.id < rhs.id : comparison == .orderedAscending
    }

    static func isExternal(builtIn: Bool?, transport: String?, name: String?) -> Bool {
        // External HID services commonly omit Built-In instead of publishing false.
        // Restrict that fallback to external transports; never accept internal buses.
        guard builtIn != true, let transport,
              ["usb", "bluetooth", "bluetooth low energy", "bluetoothlowenergy"]
                .contains(transport.lowercased()),
              name?.localizedCaseInsensitiveContains("internal") != true else { return false }
        return true
    }

    static func persistentID(vendorID: UInt32, productID: UInt32, transport: String,
                             serialNumber: String?, locationID: UInt64) -> String {
        // A serial survives port changes. Without one, scope to the physical USB port so two
        // identical keyboards don't silently acquire one another's preference.
        let serial = serialNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let identity = serial.isEmpty ? "port:\(locationID)" : "serial:\(serial)"
        let fields = [String(vendorID), String(productID), transport, identity]
        return fields.map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
    }
}

nonisolated struct KeyboardMappingLease: Codable, Equatable, Sendable {
    let keyboardID: String
    let serviceID: UInt64
    let original: [ModifierKeyMapping]
}

nonisolated struct KeyboardModifierPreferences: Codable, Equatable, Sendable {
    var selectedKeyboardID: String?
    var enabledKeyboardIDs: Set<String> = []
    var bootSessionID: String
    var leases: [String: KeyboardMappingLease] = [:]
}

nonisolated enum KeyboardModifierError: LocalizedError {
    case unsupportedMapping
    case deviceUnavailable
    case mappingNotApplied
    case changedElsewhere
    case cannotSave
    case invalidPreferences
    case unavailableBootSession

    var canRetryAfterReconnect: Bool {
        switch self {
        case .deviceUnavailable, .mappingNotApplied: return true
        default: return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .unsupportedMapping:
            return "This keyboard has an unsupported key mapping. CoffeeCup left it unchanged."
        case .deviceUnavailable:
            return "The selected keyboard is no longer available."
        case .mappingNotApplied:
            return "macOS couldn’t verify the keyboard mapping. Try the toggle again."
        case .changedElsewhere:
            return "Another app changed these modifier keys. CoffeeCup stopped swapping. Turn the swap on to try again."
        case .cannotSave:
            return "CoffeeCup couldn’t save the keyboard’s original mapping. No new swap was applied."
        case .invalidPreferences:
            return "CoffeeCup couldn’t read its saved keyboard settings. Existing mappings were left unchanged."
        case .unavailableBootSession:
            return "CoffeeCup couldn’t identify this login’s boot session. Existing mappings were left unchanged."
        }
    }
}

nonisolated protocol KeyboardHIDProviding {
    func keyboards() throws -> [ExternalKeyboard]
    func invalidateDiscoveryCache()
    func mapping(for serviceID: UInt64) throws -> [ModifierKeyMapping]
    func setMapping(_ mapping: [ModifierKeyMapping], for serviceID: UInt64) throws
}

extension KeyboardHIDProviding {
    func invalidateDiscoveryCache() { }
}

nonisolated protocol KeyboardModifierStoring {
    func load() throws -> KeyboardModifierPreferences?
    func save(_ preferences: KeyboardModifierPreferences) throws
}

nonisolated final class KeyboardModifierDefaultsStore: KeyboardModifierStoring {
    private static let key = "CoffeeCup.externalKeyboardModifiers.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() throws -> KeyboardModifierPreferences? {
        guard let raw = defaults.object(forKey: Self.key) else { return nil }
        guard let data = raw as? Data,
              let preferences = try? JSONDecoder().decode(KeyboardModifierPreferences.self, from: data) else {
            throw KeyboardModifierError.invalidPreferences
        }
        return preferences
    }

    func save(_ preferences: KeyboardModifierPreferences) throws {
        let data = try JSONEncoder().encode(preferences)
        defaults.set(data, forKey: Self.key)
        // The recovery journal must reach disk before changing the live HID service.
        guard defaults.synchronize(), defaults.data(forKey: Self.key) == data else {
            throw KeyboardModifierError.cannotSave
        }
    }
}
