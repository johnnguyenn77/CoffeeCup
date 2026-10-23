/// Deterministic coverage of the UI contract, independent of AppKit timing or permissions.
nonisolated enum PopoverInteractionTests {
    static func run() -> Int {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            checks += 1
        }
        func model(in phase: PopoverInteraction.Phase) -> PopoverInteraction {
            var state = PopoverInteraction()
            if phase != .hidden { _ = state.handle(.iconClicked) }
            if phase == .settings { _ = state.handle(.menuOpened(state.session)) }
            if phase == .confirmation { _ = state.handle(.requestConfirmation) }
            return state
        }

        for phase in PopoverInteraction.Phase.allCases {
            var state = model(in: phase)
            let effects = state.handle(.iconClicked)
            check(state.isVisible == (phase == .hidden), "Icon always toggles visibility, including child UI: \(phase)")
            check(effects.filter { $0 == .show }.count == (phase == .hidden ? 1 : 0), "Exactly one opening per click")
            check(effects.contains(.restoreFocus) == (phase != .hidden), "Only explicit dismissal restores focus")
            if phase != .hidden {
                check(effects.contains(.dismissMenu) && effects.contains(.dismissConfirmation), "Closing cancels all children")
                check(effects.contains(.removeMonitors) && effects.contains(.cancelDeferredWork), "Closing releases transient resources")
            }

            state = model(in: phase)
            let escape = state.handle(.escape)
            let expected: PopoverInteraction.Phase = phase == .hidden || phase == .popover ? .hidden : .popover
            check(state.phase == expected, "Escape dismisses exactly one level: \(phase)")
            check(escape.contains(.restoreFocus) == (phase == .popover), "Child Escape keeps focus inside CoffeeCup")
            if phase == .settings || phase == .confirmation {
                check(escape.contains(.focus), "Dismissing child UI returns focus to popover")
                _ = state.handle(.escape)
                check(!state.isVisible, "A second Escape closes the popover")
            }

            for event in [PopoverInteraction.Event.outsideInteraction, .applicationResigned, .spaceChanged, .windowClosed] {
                state = model(in: phase)
                let closing = state.handle(event)
                check(!state.isVisible, "Outside/focus-loss closes every state: \(phase), \(event)")
                check(!closing.contains(.restoreFocus) && !closing.contains(.activate), "Never steal focus on outside dismissal")
                check(!closing.contains(.startCatMode), "Dismissed confirmation cannot block input")
            }
        }

        var state = model(in: .popover)
        let original = state.session
        check(state.handle(.activationCompleted(original)) == [.focus], "Asynchronous activation can finish opening focus")
        _ = state.handle(.focusAcquired(original))
        check(state.handle(.activationCompleted(original)).isEmpty, "Later activation never refocuses an already-focused popover")
        check(state.handle(.displayChanged) == [.scheduleReanchor(original)], "Display changes only schedule repositioning")
        check(state.handle(.reanchorReady(original)) == [.reanchor], "Repositioning does not activate or focus")
        _ = state.handle(.outsideInteraction)
        for event in [PopoverInteraction.Event.displayChanged, .reanchorReady(original), .activationCompleted(original),
                      .menuOpened(original), .menuClosed(original), .confirmationCompleted(original, true), .windowClosed] {
            check(state.handle(event).isEmpty && !state.isVisible, "Late callbacks never reopen a closed popover: \(event)")
        }
        _ = state.handle(.iconClicked)
        for event in [PopoverInteraction.Event.reanchorReady(original), .activationCompleted(original),
                      .focusAcquired(original), .menuOpened(original), .menuClosed(original), .confirmationCompleted(original, true)] {
            check(state.handle(event).isEmpty && state.phase == .popover, "Old-session callbacks cannot affect a new opening")
        }
        check(state.openingFocusPending, "An old focus callback cannot consume a new focus request")

        state = model(in: .confirmation)
        let confirmation = state.session
        check(state.handle(.confirmationCompleted(confirmation, false)) == [.focus], "Cancel returns focus without enabling Cat Mode")
        check(state.handle(.confirmationCompleted(confirmation, true)).isEmpty, "Duplicate completion cannot enable Cat Mode")
        _ = state.handle(.requestConfirmation)
        check(state.handle(.confirmationCompleted(confirmation, true)) == [.startCatMode], "Only current confirmed activation starts Cat Mode")
        check(state.phase == .popover, "Failed Cat Mode start can leave the popover available to display its error")
        let started = state.handle(.catModeChanged(true))
        check(!state.isVisible && started.contains(.restoreFocus), "Successful Cat Mode hides UI and restores the user's video")
        check(state.handle(.iconClicked).isEmpty && !state.isVisible, "An active Cat Mode cannot open the popover")
        check(state.handle(.catModeChanged(false)).isEmpty && !state.isVisible, "Unlocking stays closed")
        check(state.handle(.iconClicked).contains(.show), "An explicit click works after unlocking")

        for phase in [PopoverInteraction.Phase.settings, .confirmation] {
            state = model(in: phase)
            let token = state.session
            _ = state.handle(.escape)
            let late: PopoverInteraction.Event = phase == .settings ? .menuClosed(token) : .confirmationCompleted(token, true)
            check(state.handle(late).isEmpty, "Cancelled child completion is ignored")
        }

        for phase in PopoverInteraction.Phase.allCases {
            state = model(in: phase)
            let about = state.handle(.about)
            check(!state.isVisible, "About never leaves the popover open")
            check(about.contains(.showAbout) == (phase != .hidden), "Only a visible UI can request About")
            check(!about.contains(.restoreFocus), "About takes focus rather than restoring another app")
            for stopping in [PopoverInteraction.Event.quit, .shutdown] {
                state = model(in: phase)
                let effects = state.handle(stopping)
                check(state.isStopped && !state.isVisible, "Quit/shutdown stops every phase")
                check(effects.contains(.terminate) == (stopping == .quit), "Termination is requested only by Quit")
                for late in [PopoverInteraction.Event.iconClicked, .requestConfirmation, .displayChanged,
                             .activationCompleted(state.session), .catModeChanged(false)] {
                    check(state.handle(late).isEmpty, "Shutdown ignores queued UI work")
                }
            }
        }

        state = PopoverInteraction()
        for click in 1...100 {
            let effects = state.handle(.iconClicked)
            check(state.isVisible == (click % 2 == 1), "Rapid icon clicks alternate predictably")
            check(effects.contains(.show) != effects.contains(.hide), "Each icon action has one transition, never close-and-reopen")
        }
        return checks
    }
}
