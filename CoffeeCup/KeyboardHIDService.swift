import Darwin
import Foundation
import IOKit
import IOKit.hid
import IOKit.hidsystem

@MainActor
final class KeyboardHIDService: KeyboardHIDProviding {
    private let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
    private var services: [UInt64: IOHIDServiceClient] = [:]

    func keyboards() throws -> [ExternalKeyboard] {
        guard let all = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else {
            throw KeyboardModifierError.deviceUnavailable
        }
        var grouped: [String: ExternalKeyboard] = [:]
        var available: [UInt64: IOHIDServiceClient] = [:]
        let pointerIDs = Set(all.filter { IOHIDServiceClientConformsTo($0, 1, 2) != 0 }
            .compactMap { identity(of: $0)?.id })

        for service in all {
            guard IOHIDServiceClientConformsTo(service, 1, 6) != 0,
                  isExternal(service), let identity = identity(of: service),
                  let registryID = IOHIDServiceClientGetRegistryID(service) as? NSNumber else { continue }
            let serviceID = registryID.uint64Value
            available[serviceID] = service
            if var keyboard = grouped[identity.id] {
                keyboard.serviceIDs.append(serviceID)
                keyboard.serviceIDs.sort()
                grouped[identity.id] = keyboard
            } else {
                grouped[identity.id] = ExternalKeyboard(id: identity.id,
                    name: property(service, "Product") as? String ?? "External Keyboard",
                    vendorID: identity.vendor, productID: identity.product, locationID: identity.location,
                    transport: identity.transport, hasPointerInterface: pointerIDs.contains(identity.id),
                    serviceIDs: [serviceID], isSelectable: identity.transport != "USB"
                        || !primaryUSBInterfaceIsMouse(serviceID: serviceID))
            }
        }
        services = available
        return grouped.values.sorted(by: ExternalKeyboard.preferredBefore)
    }

    func mapping(for serviceID: UInt64) throws -> [ModifierKeyMapping] {
        let service = try externalService(serviceID)
        guard let raw = property(service, "UserKeyMapping") else { return [] }
        guard let array = raw as? [[String: Any]] else { throw KeyboardModifierError.unsupportedMapping }
        return try array.map { entry in
            guard Set(entry.keys) == Set([ModifierKeyMapping.sourceKey, ModifierKeyMapping.destinationKey]),
                  let source = entry[ModifierKeyMapping.sourceKey] as? NSNumber,
                  let destination = entry[ModifierKeyMapping.destinationKey] as? NSNumber,
                  CFGetTypeID(source) != CFBooleanGetTypeID(), CFGetTypeID(destination) != CFBooleanGetTypeID(),
                  let sourceValue = UInt64(source.stringValue), let destinationValue = UInt64(destination.stringValue)
            else { throw KeyboardModifierError.unsupportedMapping }
            return ModifierKeyMapping(source: sourceValue, destination: destinationValue)
        }
    }

    func setMapping(_ mapping: [ModifierKeyMapping], for serviceID: UInt64) throws {
        let service = try externalService(serviceID)
        let value = mapping.map { [ModifierKeyMapping.sourceKey: NSNumber(value: $0.source),
                                  ModifierKeyMapping.destinationKey: NSNumber(value: $0.destination)] }
        guard IOHIDServiceClientSetProperty(service, "UserKeyMapping" as CFString, value as CFArray),
              try self.mapping(for: serviceID) == mapping else {
            throw KeyboardModifierError.mappingNotApplied
        }
    }

    private func externalService(_ serviceID: UInt64) throws -> IOHIDServiceClient {
        guard let service = services[serviceID], isExternal(service),
              IOHIDServiceClientConformsTo(service, 1, 6) != 0 else {
            throw KeyboardModifierError.deviceUnavailable
        }
        return service
    }

    private func isExternal(_ service: IOHIDServiceClient) -> Bool {
        ExternalKeyboard.isExternal(
            builtIn: (property(service, "Built-In") as? NSNumber)?.boolValue,
            transport: property(service, "Transport") as? String,
            name: property(service, "Product") as? String
        )
    }

    private func property(_ service: IOHIDServiceClient, _ key: String) -> CFTypeRef? {
        IOHIDServiceClientCopyProperty(service, key as CFString)
    }

    private func primaryUSBInterfaceIsMouse(serviceID: UInt64) -> Bool {
        var entry = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(serviceID))
        guard entry != 0 else { return false }
        defer { IOObjectRelease(entry) }

        // Inspect the physical USB device, not just the helper keyboard interface.
        // No devices are opened or seized, and no input events are read.
        for _ in 0..<16 {
            if IOObjectConformsTo(entry, "IOUSBHostDevice") != 0
                || IOObjectConformsTo(entry, "IOUSBDevice") != 0 {
                var iterator: io_iterator_t = 0
                guard IORegistryEntryGetChildIterator(entry, kIOServicePlane, &iterator) == KERN_SUCCESS else {
                    return false
                }
                defer { IOObjectRelease(iterator) }
                while true {
                    let child = IOIteratorNext(iterator)
                    guard child != 0 else { break }
                    defer { IOObjectRelease(child) }
                    func number(_ key: String) -> UInt32? {
                        (IORegistryEntryCreateCFProperty(child, key as CFString,
                            kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.uint32Value
                    }
                    guard number("bInterfaceNumber") == 0,
                          number("bAlternateSetting") ?? 0 == 0 else { continue }
                    return ExternalKeyboard.isPrimaryUSBMouse(interfaceClass: number("bInterfaceClass"),
                        subclass: number("bInterfaceSubClass"), protocolCode: number("bInterfaceProtocol"))
                }
                return false
            }
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent) == KERN_SUCCESS else {
                return false
            }
            IOObjectRelease(entry)
            entry = parent
        }
        return false
    }

    private func identity(of service: IOHIDServiceClient)
        -> (id: String, vendor: UInt32, product: UInt32, location: UInt64, transport: String)? {
        guard let vendor = property(service, "VendorID") as? NSNumber,
              let product = property(service, "ProductID") as? NSNumber,
              let location = property(service, "LocationID") as? NSNumber,
              let transport = property(service, "Transport") as? String,
              vendor.uint32Value != 0, product.uint32Value != 0 else { return nil }
        let id = ExternalKeyboard.persistentID(vendorID: vendor.uint32Value, productID: product.uint32Value,
            transport: transport, serialNumber: property(service, "SerialNumber") as? String,
            locationID: location.uint64Value)
        return (id, vendor.uint32Value, product.uint32Value, location.uint64Value, transport)
    }

    static func bootSessionID() throws -> String {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 1, size < 1024 else {
            throw KeyboardModifierError.unavailableBootSession
        }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.bootsessionuuid", &bytes, &size, nil, 0) == 0 else {
            throw KeyboardModifierError.unavailableBootSession
        }
        return String(cString: bytes)
    }
}
