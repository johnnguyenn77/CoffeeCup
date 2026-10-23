import Darwin
import Foundation
import IOKit
import IOKit.hid
import IOKit.hidsystem

/// Confined to the keyboard worker's serial queue; it never reads input events.
nonisolated final class KeyboardHIDService: KeyboardHIDProviding {
    private var client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
    private var services: [UInt64: IOHIDServiceClient] = [:]
    private var cachedUSBTopology: Set<UInt64> = []
    private var cachedUSBRoles: [String: ExternalKeyboard.USBInputRole]?
    private(set) var usbClassificationScans = 0

    func invalidateDiscoveryCache() {
        // A KVM can invalidate the client's service handles. Rebuild discovery on
        // topology changes/recovery instead of requiring the app to be restarted.
        client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        services = [:]
        cachedUSBRoles = nil
    }

    func keyboards() throws -> [ExternalKeyboard] {
        guard let all = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else {
            services = [:]
            throw KeyboardModifierError.deviceUnavailable
        }
        var grouped: [String: ExternalKeyboard] = [:]
        var available: [UInt64: IOHIDServiceClient] = [:]
        let topology = Set(all.compactMap {
            (IOHIDServiceClientGetRegistryID($0) as? NSNumber)?.uint64Value
        })
        if cachedUSBRoles == nil || topology != cachedUSBTopology {
            cachedUSBRoles = primaryUSBInputRoles()
            cachedUSBTopology = topology
        }
        let usbRoles = cachedUSBRoles ?? [:]
        let pointerIDs = Set(all.filter { IOHIDServiceClientConformsTo($0, 1, 2) != 0 }
            .compactMap { identity(of: $0)?.connectionID })

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
                let name = property(service, "Product") as? String ?? "External Keyboard"
                let hasPointerInterface = pointerIDs.contains(identity.connectionID)
                grouped[identity.id] = ExternalKeyboard(id: identity.id,
                    name: name,
                    vendorID: identity.vendor, productID: identity.product, locationID: identity.location,
                    transport: identity.transport, hasPointerInterface: hasPointerInterface,
                    serviceIDs: [serviceID], isSelectable: ExternalKeyboard.shouldOfferModifierSwap(
                        name: name, hasPointerInterface: hasPointerInterface,
                        usbRole: usbRoles[identity.connectionID] ?? .unknown))
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
              try ModifierKeyMapping.equivalent(self.mapping(for: serviceID), mapping) else {
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

    private func primaryUSBInputRoles() -> [String: ExternalKeyboard.USBInputRole] {
        usbClassificationScans += 1
        var roles: [String: ExternalKeyboard.USBInputRole] = [:]
        // Event services are virtual on some macOS/DriverKit versions and cannot reliably be
        // walked back to a USB parent. Match physical devices by VID/PID/port instead, once per scan.
        for className in ["IOUSBHostDevice", "IOUSBDevice"] {
            var devices: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &devices)
                == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(devices) }
            while true {
                let device = IOIteratorNext(devices)
                guard device != 0 else { break }
                defer { IOObjectRelease(device) }
                guard let vendor = registryNumber(device, "idVendor"),
                      let product = registryNumber(device, "idProduct"),
                      let location = registryNumber(device, "locationID") else { continue }
                let connectionID = usbConnectionID(vendor: vendor, product: product, location: UInt64(location))
                var children: io_iterator_t = 0
                guard IORegistryEntryGetChildIterator(device, kIOServicePlane, &children) == KERN_SUCCESS else {
                    continue
                }
                defer { IOObjectRelease(children) }
                while true {
                    let child = IOIteratorNext(children)
                    guard child != 0 else { break }
                    defer { IOObjectRelease(child) }
                    guard IOObjectConformsTo(child, "IOUSBHostInterface") != 0
                            || IOObjectConformsTo(child, "IOUSBInterface") != 0,
                          registryNumber(child, "bInterfaceNumber") == 0,
                          (registryNumber(child, "bAlternateSetting") ?? 0) == 0 else { continue }
                    let role = ExternalKeyboard.usbInputRole(
                        interfaceClass: registryNumber(child, "bInterfaceClass"),
                        subclass: registryNumber(child, "bInterfaceSubClass"),
                        protocolCode: registryNumber(child, "bInterfaceProtocol"))
                    if role != .unknown { roles[connectionID] = role }
                }
            }
        }
        return roles
    }

    private func registryNumber(_ entry: io_registry_entry_t, _ key: String) -> UInt32? {
        (IORegistryEntryCreateCFProperty(entry, key as CFString,
            kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.uint32Value
    }

    private func usbConnectionID(vendor: UInt32, product: UInt32, location: UInt64) -> String {
        "USB:\(vendor):\(product):\(location)"
    }

    private func identity(of service: IOHIDServiceClient)
        -> (id: String, connectionID: String, vendor: UInt32, product: UInt32, location: UInt64, transport: String)? {
        guard let vendor = property(service, "VendorID") as? NSNumber,
              let product = property(service, "ProductID") as? NSNumber,
              let location = property(service, "LocationID") as? NSNumber,
              let transport = property(service, "Transport") as? String,
              vendor.uint32Value != 0, product.uint32Value != 0 else { return nil }
        let id = ExternalKeyboard.persistentID(vendorID: vendor.uint32Value, productID: product.uint32Value,
            transport: transport, serialNumber: property(service, "SerialNumber") as? String,
            locationID: location.uint64Value)
        let connectionID = transport.caseInsensitiveCompare("USB") == .orderedSame
            ? usbConnectionID(vendor: vendor.uint32Value, product: product.uint32Value, location: location.uint64Value)
            : id
        return (id, connectionID, vendor.uint32Value, product.uint32Value, location.uint64Value, transport)
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
