import AppKit
import Combine
import CoreGraphics
import Darwin
import SwiftUI

struct DisplayRotationControls: View {
    @ObservedObject var controller: DisplayRotationController

    private var displaySelection: Binding<CGDirectDisplayID> {
        Binding(
            get: { controller.selectedDisplayID ?? controller.displays.first?.id ?? 0 },
            set: { controller.selectDisplay($0) }
        )
    }

    private var rotationSelection: Binding<Int> {
        Binding(
            get: { controller.currentRotation },
            set: { controller.setRotation($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            HStack(alignment: .center, spacing: 12) {
                Label("Display", systemImage: "display")

                Spacer(minLength: 8)

                displayPicker
            }

            HStack(alignment: .center, spacing: 12) {
                Text("Rotation")

                Spacer(minLength: 8)

                Picker("Rotation", selection: rotationSelection) {
                    ForEach(DisplayRotation.allCases) { rotation in
                        Text(rotation.title).tag(rotation.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }

            if let errorMessage = controller.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
        }
    }

    @ViewBuilder
    private var displayPicker: some View {
        if controller.displays.count > 1 {
            Picker("Display", selection: displaySelection) {
                ForEach(controller.displays) { display in
                    Text(display.name).tag(display.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        } else if let display = controller.selectedDisplay {
            Text(display.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
        }
    }
}

@MainActor
final class DisplayRotationController: ObservableObject {
    static let shared = DisplayRotationController()

    @Published private(set) var displays: [RotationDisplay] = []
    @Published private(set) var selectedDisplayID: CGDirectDisplayID?
    @Published private(set) var currentRotation = 0
    @Published private(set) var errorMessage: String?

    var hasDisplays: Bool { !displays.isEmpty }

    var selectedDisplay: RotationDisplay? {
        displays.first { $0.id == selectedDisplayID }
    }

    func refreshDisplays() {
        let screens = NSScreen.screens.compactMap { screen -> RotationDisplay? in
            guard
                let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else {
                return nil
            }

            let displayID = CGDirectDisplayID(number.uint32Value)
            return RotationDisplay(id: displayID, name: screen.localizedName)
        }

        let onlineDisplayIDs = getOnlineDisplayIDs() ?? screens.map(\.id)
        let externalDisplayIDs = onlineDisplayIDs.filter { CGDisplayIsBuiltin($0) == 0 }
        let connectedDisplays = externalDisplayIDs.enumerated().map { index, displayID in
            let screenName = screens.first(where: { $0.id == displayID })?.name
            let fallbackName = externalDisplayIDs.count > 1
                ? "External Display \(index + 1)"
                : "External Display"
            return RotationDisplay(id: displayID, name: screenName ?? fallbackName)
        }

        displays = connectedDisplays

        if let selectedDisplayID,
           connectedDisplays.contains(where: { $0.id == selectedDisplayID }) {
            currentRotation = Int(CGDisplayRotation(selectedDisplayID).rounded())
        } else if let firstDisplay = connectedDisplays.first {
            selectedDisplayID = firstDisplay.id
            currentRotation = Int(CGDisplayRotation(firstDisplay.id).rounded())
        } else {
            selectedDisplayID = nil
            currentRotation = 0
        }
    }

    private func getOnlineDisplayIDs() -> [CGDirectDisplayID]? {
        var displayCount: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &displayCount) == .success else { return nil }
        guard displayCount > 0 else { return [] }

        let maximumDisplays = displayCount
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(maximumDisplays))
        let result = displayIDs.withUnsafeMutableBufferPointer { buffer in
            CGGetOnlineDisplayList(maximumDisplays, buffer.baseAddress, &displayCount)
        }
        guard result == .success else { return nil }
        return Array(displayIDs.prefix(Int(displayCount)))
    }

    func selectDisplay(_ displayID: CGDirectDisplayID) {
        selectedDisplayID = displayID
        currentRotation = Int(CGDisplayRotation(displayID).rounded())
        errorMessage = nil
    }

    func setRotation(_ degrees: Int) {
        guard let rotation = DisplayRotation(rawValue: degrees) else { return }
        apply(rotation)
    }

    private func apply(_ rotation: DisplayRotation) {
        guard let selectedDisplayID else { return }

        errorMessage = nil
        guard DisplayRotationService.set(rotation.rawValue, on: selectedDisplayID) else {
            errorMessage = "This display couldn’t be rotated."
            return
        }

        currentRotation = rotation.rawValue
    }
}

struct RotationDisplay: Identifiable {
    let id: CGDirectDisplayID
    let name: String
}

private enum DisplayRotation: Int, CaseIterable, Identifiable {
    case landscape = 0
    case portraitRight = 90
    case upsideDown = 180
    case portraitLeft = 270

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .landscape: "Landscape · 0°"
        case .portraitRight: "Portrait · 90° clockwise"
        case .upsideDown: "Upside Down · 180°"
        case .portraitLeft: "Portrait · 270° clockwise"
        }
    }
}

private enum DisplayRotationService {
    private typealias RotationSetter = @convention(c) (CGDirectDisplayID, Int32) -> Int32

    // This private macOS symbol is resolved dynamically so unsupported systems fail gracefully.
    private static let setter: RotationSetter? = {
        guard let framework = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            RTLD_LAZY
        ) else {
            return nil
        }

        guard let symbol = dlsym(framework, "SLSSetDisplayRotation") else { return nil }
        return unsafeBitCast(symbol, to: RotationSetter.self)
    }()

    static func set(_ degrees: Int, on displayID: CGDirectDisplayID) -> Bool {
        guard let setter else { return false }
        return setter(displayID, Int32(degrees)) == 0
    }
}
