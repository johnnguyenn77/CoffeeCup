# Popover interaction contract

Only a deliberate menu-bar icon click opens CoffeeCup. Opening activates the app
and makes the popover key so Escape works immediately. A visible popover always
closes on the next icon click, regardless of focus; one click must never close and
reopen it.

| State | Icon | Escape | Outside click / app or Space switch |
| --- | --- | --- | --- |
| Hidden | Open and focus | No effect | Stay hidden |
| Popover | Close | Close | Close |
| Settings menu | Close both | Close menu, focus popover | Close both |
| Cat Mode confirmation | Cancel and close both | Cancel, focus popover | Cancel and close both |
| Cat Mode active | Input remains blocked | Only the deliberate unlock chord unlocks | Input remains blocked |

- Explicit icon/Escape dismissal restores the previous app/window. Outside clicks
  pass through unchanged on the first click and never restore/steal focus.
- Ordinary settings and display rotation leave the popover open. Display changes
  reposition a currently visible popover at its status icon without activating it.
- A successful Cat Mode start closes the popover and restores the previous app.
  Unlocking leaves it closed. Failed activation leaves room for its error message.
- Closing cancels menus, confirmations, event monitors, and pending focus/position
  work. An obsolete confirmation must never start Cat Mode. Async work is scoped
  to an opening, so a late callback cannot change a later opening.
- About closes the popover and focuses About. Quit tears down presentation before
  stopping the app's services. No background notification opens or activates UI.

## Implementation and verification

`PopoverInteraction` is the deterministic state/effect model.
`CoffeeCupPopoverController` owns the AppKit popover, menu tracking, native alert,
focus restoration, and temporary input monitors. The popover uses
`.applicationDefined` behavior; no automatic-close veto competes with its icon.
Mouse monitors cannot suppress clicks in other apps, and keyboard monitoring is
local to CoffeeCup. These monitors exist only while the popover is visible. The
interaction controller needs no Accessibility or Screen Recording permission.

The global outside-click monitor ignores presses on the status icon: macOS can
send that press globally before forwarding the button action, including with a
different event window. Treating it as outside would close, then reopen on the
same gesture. Icon hit-testing uses the full status-item host's screen frame,
including the clickable capsule padding outside `button.bounds`, rather than
window identity. Immediately adjacent menu-bar clicks still count as outside.
The local monitor also passes icon presses through without toggling. Native button
target/action is the only toggle owner, so forwarding a press cannot toggle twice.

Clicks inside the popover (including blank padding) or its confirmation/child
windows stay inside, even when delivered globally or without an `NSWindow`.
Windowless hit-testing uses the event's screen location, not the pointer position
when the handler finally runs. Mouse events timestamped before the current
opening cannot dismiss it; fresh outside clicks still dismiss immediately, with
no debounce interval.

Focus-loss notifications are validated on the next main-queue turn against native
activation and the current frontmost application. A stale notification from a
previous close must not dismiss a newly focused opening. Reopening also cancels
any pending activation yield on supported macOS versions. This is a one-shot
check tied to the opening, not a polling timer.

Run `bash scripts/test-keyboard-modifiers.sh` for state transitions and service
regressions. Build the isolated test host with
`bash scripts/build-interaction-tests.sh`, open it, and choose **Run popover
edge-case tests** for real AppKit focus, routing, nested menu tracking, stale menu
requests, native confirmation teardown, and monitor cleanup. Cat Mode activation
is simulated in that host: it never blocks input.

Live checks also cover Escape from settings/confirmation, inactive-to-active
opening, and restoring the previously active app. Physically rotating/removing a
monitor and rapid real menu-bar clicks across displays remain useful hardware
checks; simulated display notifications do not replace those tests.
