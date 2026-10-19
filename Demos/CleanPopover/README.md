# Clean popover layout demo

A standalone native SwiftUI preview of the proposed cleaner CoffeeCup layout.
It does not replace or modify the installed app. Its own menu-bar item includes
“Demo” so it can run alongside CoffeeCup without confusion.

```sh
bash scripts/run-clean-popover-demo.sh
```

The popup keeps two action rows and the three-position display rotation selector.
Launch at login, keyboard configuration, About/version, and Quit move into a gear
menu. The rotation section is hidden without a simulated display; keyboard
settings are hidden without a simulated external keyboard. Device pickers appear
only when more than one device is available.

Use the separate **CoffeeCup — Layout Demo** window to choose zero, one, or two
displays/keyboards, preview an available update, reset the preview, or reopen the
popover. Cat Mode closes the popup after confirmation; **End Cat Mode** in the
controls window restores its simulated state.

All controls are session-only simulations. This demo does not run caffeinate,
intercept input, remap keys, rotate a monitor, register a login item, download
updates, save preferences, or request Accessibility/Screen Recording permission.
It reuses the app’s actual rotation selector view with a simulated callback; the
real display controller is never instantiated.

```sh
bash scripts/run-clean-popover-demo.sh --test
bash scripts/run-clean-popover-demo.sh --build-only
```

The build script runs the state tests first and outputs the standalone app to
`build/CleanPopoverDemo/CoffeeCup Layout Demo.app`. Quit only the demo with
**Quit Demo**; your installed CoffeeCup stays running.
