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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            HStack(alignment: .center, spacing: 12) {
                Label("Display", systemImage: "display")

                Spacer(minLength: 8)

                displayPicker
            }

            DisplayRotationSelector(
                currentRotation: controller.currentRotation,
                onSelect: controller.setRotation
            )
            .id(controller.selectedDisplayID)

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

struct DisplayRotationSelector: View {
    let currentRotation: Int
    let onSelect: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var hoveredRotation: DisplayRotation?
    @State private var requestedRotation: Int?

    private let buttonHeight: CGFloat = 60
    private let inset: CGFloat = 4
    private let spacing: CGFloat = 4
    private let cornerRadius: CGFloat = 10
    private let slideDuration = 0.22

    private var highlightedRotation: DisplayRotation? {
        DisplayRotation(rawValue: requestedRotation ?? currentRotation)
    }

    private var highlightedIndex: Int {
        highlightedRotation.flatMap { DisplayRotation.allCases.firstIndex(of: $0) } ?? 1
    }

    private var selectionAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: slideDuration)
    }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(DisplayRotation.allCases) { rotation in
                rotationButton(rotation)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: buttonHeight)
        .background {
            GeometryReader { geometry in
                let count = CGFloat(DisplayRotation.allCases.count)
                let buttonWidth = (geometry.size.width - spacing * (count - 1)) / count

                // The highlight matches each full-width segment and remains alive as it slides.
                selectionHighlight
                    .frame(width: buttonWidth, height: buttonHeight)
                    .offset(x: CGFloat(highlightedIndex) * (buttonWidth + spacing))
                    .opacity(highlightedRotation == nil ? 0 : 1)
                    .animation(selectionAnimation, value: highlightedRotation)
                    .allowsHitTesting(false)
            }
        }
        .padding(inset)
        .background(
            Color.primary.opacity(contrast == .increased ? 0.10 : 0.045),
            in: RoundedRectangle(cornerRadius: cornerRadius + inset, style: .continuous)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Display rotation")
        .task(id: requestedRotation) {
            guard let requestedRotation else { return }

            // Screen reconfiguration can interrupt rendering, so finish the slide first.
            if !reduceMotion {
                do {
                    try await Task.sleep(for: .seconds(slideDuration))
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else { return }

            if requestedRotation != currentRotation {
                onSelect(requestedRotation)
            }
            self.requestedRotation = nil
        }
        .onChange(of: currentRotation) { _ in
            requestedRotation = nil
        }
        .onDisappear {
            requestedRotation = nil
        }
    }

    private func rotationButton(_ rotation: DisplayRotation) -> some View {
        let isHighlighted = highlightedRotation == rotation

        return Button {
            guard highlightedRotation != rotation else { return }
            requestedRotation = rotation.rawValue
        } label: {
            DisplayRotationIcon(rotation: rotation)
                .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .frame(width: 30, height: 34)
                .accessibilityHidden(true)
                .foregroundStyle(isHighlighted ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .frame(height: buttonHeight)
                .background(
                    hoveredRotation == rotation && !isHighlighted ? Color.primary.opacity(0.06) : .clear,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredRotation = hovering ? rotation : (hoveredRotation == rotation ? nil : hoveredRotation)
        }
        .help(rotation.accessibilityTitle)
        .accessibilityLabel(rotation.accessibilityTitle)
        .accessibilityAddTraits(currentRotation == rotation.rawValue ? .isSelected : [])
    }

    @ViewBuilder
    private var selectionHighlight: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(macOS 26.0, *), !reduceTransparency {
            shape
                .fill(.clear)
                .glassEffect(.regular, in: shape)
                .overlay {
                    if contrast == .increased {
                        shape.strokeBorder(.primary, lineWidth: 1)
                    }
                }
        } else {
            shape
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay {
                    shape.strokeBorder(Color.primary.opacity(contrast == .increased ? 0.8 : 0.12), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        }
    }
}

private struct DisplayRotationIcon: Shape {
    let rotation: DisplayRotation

    func path(in rect: CGRect) -> Path {
        let isPortrait = rotation != .landscape
        let screen = isPortrait
            ? CGRect(x: 10, y: 10, width: 16, height: 24)
            : CGRect(x: 4, y: 10, width: 28, height: 18)
        let footY: CGFloat = isPortrait ? 38 : 33

        var path = Path()
        path.addRoundedRect(in: screen, cornerSize: CGSize(width: 2, height: 2))
        path.move(to: CGPoint(x: 18, y: screen.maxY))
        path.addLine(to: CGPoint(x: 18, y: footY))
        path.move(to: CGPoint(x: 13, y: footY))
        path.addLine(to: CGPoint(x: 23, y: footY))

        if isPortrait {
            // A curved arrow above the portrait screen distinguishes the two directions.
            let turnsRight = rotation == .portraitRight
            let startX: CGFloat = turnsRight ? 7 : 29
            let endX: CGFloat = turnsRight ? 29 : 7
            path.move(to: CGPoint(x: startX, y: 8))
            path.addCurve(
                to: CGPoint(x: endX, y: 8),
                control1: CGPoint(x: turnsRight ? 12 : 24, y: 0),
                control2: CGPoint(x: turnsRight ? 24 : 12, y: 0)
            )
            path.addLines([
                CGPoint(x: endX + (turnsRight ? -1 : 1), y: 3),
                CGPoint(x: endX, y: 8),
                CGPoint(x: endX + (turnsRight ? -5 : 5), y: 7)
            ])
        }

        return path.applying(CGAffineTransform(
            a: rect.width / 36, b: 0,
            c: 0, d: rect.height / 40,
            tx: rect.minX, ty: rect.minY
        ))
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
    case portraitLeft = 270
    case landscape = 0
    case portraitRight = 90

    var id: Int { rawValue }

    var accessibilityTitle: String {
        switch self {
        case .portraitLeft: "Rotate display left to portrait, 90° counterclockwise"
        case .landscape: "Horizontal display, no rotation"
        case .portraitRight: "Rotate display right to portrait, 90° clockwise"
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
