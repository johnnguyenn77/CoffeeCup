/// The visibility contract for the menu bar UI. Only an icon click can open it.
/// AppKit callbacks carry a session number so an older session cannot affect a new one.
nonisolated struct PopoverInteraction {
    enum Phase: CaseIterable, Equatable { case hidden, popover, settings, confirmation }

    enum Event: Equatable {
        case iconClicked, escape, outsideInteraction, applicationResigned, spaceChanged
        case menuOpened(Int), menuClosed(Int)
        case requestConfirmation, confirmationCompleted(Int, Bool)
        case catModeChanged(Bool), about, quit, shutdown, windowClosed
        case activationCompleted(Int), focusAcquired(Int)
        case displayChanged, reanchorReady(Int)
    }

    enum Effect: Equatable {
        case rememberFocus, installMonitors, show, activate, focus, deferFocus(Int)
        case removeMonitors, cancelDeferredWork, dismissMenu, dismissConfirmation, hide
        case restoreFocus, forgetFocus, presentConfirmation(Int), startCatMode
        case scheduleReanchor(Int), reanchor, showAbout, terminate
    }

    private(set) var phase: Phase = .hidden
    private(set) var session = 0
    private(set) var catModeActive = false
    private(set) var isStopped = false
    private(set) var openingFocusPending = false

    var isVisible: Bool { phase != .hidden }
    var menuRequestSession: Int? { phase == .popover ? session : nil }

    mutating func handle(_ event: Event) -> [Effect] {
        guard !isStopped else { return [] }
        switch event {
        case .iconClicked:
            if isVisible { return close(restoringFocus: true) }
            guard !catModeActive else { return [] }
            session += 1
            phase = .popover
            openingFocusPending = true
            return [.rememberFocus, .installMonitors, .show, .activate, .focus, .deferFocus(session)]

        case .escape:
            switch phase {
            case .hidden: return []
            case .popover: return close(restoringFocus: true)
            case .settings:
                phase = .popover
                openingFocusPending = false
                return [.dismissMenu, .focus]
            case .confirmation:
                phase = .popover
                openingFocusPending = false
                return [.dismissConfirmation, .focus]
            }

        case .outsideInteraction, .applicationResigned, .spaceChanged, .windowClosed:
            return close(restoringFocus: false)

        case .menuOpened(let token):
            guard token == session, phase == .popover else { return [] }
            phase = .settings
            openingFocusPending = false
            return []

        case .menuClosed(let token):
            guard token == session, phase == .settings else { return [] }
            phase = .popover
            return [.focus]

        case .requestConfirmation:
            guard phase == .popover, !catModeActive else { return [] }
            phase = .confirmation
            openingFocusPending = false
            return [.presentConfirmation(session)]

        case .confirmationCompleted(let token, let confirmed):
            guard token == session, phase == .confirmation else { return [] }
            phase = .popover
            return confirmed ? [.startCatMode] : [.focus]

        case .catModeChanged(let active):
            catModeActive = active
            // Unlocking never opens a window. Closing after activation also puts
            // the user's video/app back in front without requiring any input.
            return active ? close(restoringFocus: true) : []

        case .about:
            guard isVisible, !catModeActive else { return [] }
            return close(restoringFocus: false) + [.showAbout]

        case .quit, .shutdown:
            let effects = close(restoringFocus: false)
            isStopped = true
            return effects + (event == .quit ? [.terminate] : [])

        case .activationCompleted(let token):
            guard token == session, phase == .popover, openingFocusPending else { return [] }
            return [.focus]

        case .focusAcquired(let token):
            if token == session, phase == .popover { openingFocusPending = false }
            return []

        case .displayChanged:
            return isVisible ? [.scheduleReanchor(session)] : []

        case .reanchorReady(let token):
            return token == session && isVisible ? [.reanchor] : []
        }
    }

    private mutating func close(restoringFocus: Bool) -> [Effect] {
        guard isVisible else { return [] }
        phase = .hidden
        session += 1
        openingFocusPending = false
        return [.removeMonitors, .cancelDeferredWork, .dismissMenu, .dismissConfirmation, .hide,
                restoringFocus ? .restoreFocus : .forgetFocus]
    }
}
