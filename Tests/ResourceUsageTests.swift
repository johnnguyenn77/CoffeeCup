import AppKit
import CoreGraphics
import Foundation

@MainActor
enum ResourceUsageTests {
    static func run() async throws -> Int {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message)
            checks += 1
        }
        var filter = CatModeInputFilter()
        let key = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
        check(filter.action(for: .keyDown, event: key) == .suppress, "Ordinary typing is blocked")
        check(filter.action(for: .keyUp, event: key) == .suppress, "Ordinary key releases are blocked")
        for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged,
                     .rightMouseDown, .rightMouseUp, .otherMouseDown, .scrollWheel, .tabletPointer] {
            check(filter.action(for: type, event: key) == .suppress, "Pointer event remains blocked: \(type.rawValue)")
        }
        check(filter.action(for: .flagsChanged, event: key) == .allow, "Modifier releases cannot leave keys stuck")
        for code in UInt16(122)...UInt16(126) {
            let function = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)!
            check(filter.action(for: .keyDown, event: function) == .suppress, "Function/arrow key \(code) stays blocked")
        }
        for code in [0, 1, 2, 3, 7, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23] {
            let event = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, subtype: 8, data1: code << 16, data2: 0)!.cgEvent!
            check(filter.action(for: event.type, event: event) == .suppress, "Media/function action \(code) stays blocked")
        }
        let power = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, subtype: 8, data1: 6 << 16, data2: 0)!.cgEvent!
        check(filter.action(for: power.type, event: power) == .allow, "Power events are never suppressed")
        let escape = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true)!
        check(filter.action(for: .keyDown, event: escape) == .suppress, "Escape alone cannot unlock")
        escape.flags = [.maskControl, .maskAlternate]
        check(filter.action(for: .keyDown, event: escape) == .suppress, "A partial unlock chord cannot unlock")
        escape.flags = [.maskControl, .maskAlternate, .maskCommand]
        check(filter.action(for: .keyDown, event: escape) == .beginUnlock, "The deliberate chord begins unlocking")
        check(filter.action(for: .keyDown, event: escape) == .suppress, "Key repeat cannot enqueue multiple unlocks")
        escape.flags = []
        check(filter.action(for: .keyUp, event: escape) == .finishUnlock, "Escape release is swallowed before input resumes")

        for index in 0..<12 {
            var stops = 0
            let session = CatModeInputSession.simulated { _, _ in stops += 1 }
            session.start()
            if index % 2 == 0 {
                // Intentionally keep the main thread occupied while the real event thread
                // executes a block. No global tap is installed and no input is posted.
                for _ in 0..<200 where !session.isRunningForTesting {
                    try await Task.sleep(for: .milliseconds(2))
                }
                check(session.isRunningForTesting, "The input run loop starts off-main")
                let processed = DispatchSemaphore(value: 0)
                session.performForTesting {
                    precondition(!Thread.isMainThread)
                    processed.signal()
                }
                check(processed.wait(timeout: .now() + 1) == .success,
                      "The input loop remains responsive while the UI thread is blocked")
            }
            session.stop()
            session.stop()
            for _ in 0..<200 where !session.isFinishedForTesting {
                try await Task.sleep(for: .milliseconds(2))
            }
            check(session.isFinishedForTesting, "Input threads are released, including immediate start/stop races")
            // Main-queue delivery is independent of the input thread's teardown.
            for _ in 0..<200 where stops == 0 { try await Task.sleep(for: .milliseconds(2)) }
            check(stops == 1, "A session sends exactly one stop notification")
        }

        let released = DispatchSemaphore(value: 0)
        var unlockReason: CatModeInputSession.StopReason?
        let unlockSession = CatModeInputSession.simulated(onFinished: { released.signal() }) { _, reason in
            unlockReason = reason
        }
        unlockSession.start()
        for _ in 0..<200 where !unlockSession.isRunningForTesting {
            try await Task.sleep(for: .milliseconds(2))
        }
        check(unlockSession.isRunningForTesting, "The simulated unlock session is ready")
        unlockSession.performForTesting {
            let chord = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true)!
            chord.flags = [.maskControl, .maskAlternate, .maskCommand]
            unlockSession.handleForTesting(type: .keyDown, event: chord)
        }
        check(released.wait(timeout: .now() + 2) == .success,
              "The real unlock timer releases the input loop while the main thread is blocked, even without key-up")
        for _ in 0..<200 where unlockReason == nil { try await Task.sleep(for: .milliseconds(2)) }
        check(unlockReason == .unlocked, "The completed background unlock is reported to the UI")

        check(CoffeeCupController.caffeinateArguments(for: 123) == ["-d", "-w", "123"],
              "Awake mode remains display-only and watches the owning process")
        let owner = Process()
        owner.executableURL = URL(fileURLWithPath: "/bin/sleep")
        owner.arguments = ["30"]
        let caffeinate = Process()
        caffeinate.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        caffeinate.standardError = FileHandle.nullDevice
        defer {
            if caffeinate.isRunning { caffeinate.terminate() }
            if owner.isRunning { owner.terminate() }
        }
        try owner.run()
        caffeinate.arguments = CoffeeCupController.caffeinateArguments(for: owner.processIdentifier)
        try caffeinate.run()
        try await Task.sleep(for: .milliseconds(100))
        check(caffeinate.isRunning, "The native awake assertion remains alive while its owner runs")
        owner.terminate()
        for _ in 0..<200 where caffeinate.isRunning { try await Task.sleep(for: .milliseconds(10)) }
        check(!caffeinate.isRunning && caffeinate.terminationStatus == 0,
              "Native caffeinate exits automatically after its watched owner exits")
        return checks
    }
}
