import Foundation

@main
enum CleanPopoverStateTests {
    @MainActor static func main() {
        let state = CleanPopoverDemoState()
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            count += 1
        }
        check(state.displays.count == 1 && state.keyboards.count == 1, "Start with one of each simulated device")
        check(!state.keepsDisplayAwake && !state.launchesAtLogin && !state.catModeActive, "Start with all actions off")
        state.setDisplayCount(0)
        check(state.displays.isEmpty, "Hide rotation with no display")
        state.setRotation(90)
        check(state.currentRotation == 0, "Ignore rotation with no display")
        state.setDisplayCount(2)
        check(state.displays.count == 2, "Offer display selection for multiple displays")
        state.setRotation(270)
        check(state.currentRotation == 270, "Select left portrait")
        state.selectDisplay("display-2")
        check(state.currentRotation == 0, "Keep rotation per display")
        state.setRotation(90)
        state.selectDisplay("display-1")
        check(state.currentRotation == 270, "Restore the first display selection")
        state.setRotation(180)
        check(state.currentRotation == 270, "Only the three intended rotations are accepted")
        state.setKeyboardCount(0)
        check(state.keyboards.isEmpty && state.selectedKeyboard == nil, "Hide keyboard menu with no keyboard")
        state.setSwapEnabled(true)
        check(!state.swapsModifiers, "Do not swap a nonexistent keyboard")
        state.setKeyboardCount(2)
        state.setSwapEnabled(true)
        check(state.swapsModifiers, "Toggle a simulated keyboard swap")
        state.selectKeyboard("keyboard-2")
        check(!state.swapsModifiers, "Keep swap state per keyboard")
        state.setSwapEnabled(true)
        state.selectKeyboard("keyboard-1")
        check(state.swapsModifiers, "Retain the first keyboard setting")
        state.selectKeyboard("unknown")
        check(state.selectedKeyboardID == "keyboard-1", "Reject unknown selections")
        state.setKeyboardCount(0)
        state.setKeyboardCount(1)
        check(state.swapsModifiers, "Remember the simulated setting across reconnect")
        state.setCatMode(true)
        check(state.catModeActive, "Simulate Cat Mode activation")
        state.setCatMode(false)
        check(!state.catModeActive, "Simulate Cat Mode exit")
        state.setDisplayCount(99)
        state.setKeyboardCount(-5)
        check(state.displayCount == 2 && state.keyboardCount == 0, "Bound hardware counts")
        state.keepsDisplayAwake = true
        state.launchesAtLogin = true
        state.updateAvailable = true
        state.reset()
        check(!state.keepsDisplayAwake && !state.launchesAtLogin && !state.updateAvailable, "Reset action flags")
        check(state.currentRotation == 0 && !state.swapsModifiers, "Reset simulated device settings")
        check(state.displays.count == 1 && state.keyboards.count == 1, "Reset hardware scenario")
        print("PASS: \(count) clean-popover demo checks")
    }
}
