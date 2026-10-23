# CoffeeCup

CoffeeCup is a lightweight macOS menu-bar app for keeping your display awake,
blocking input with Cat Mode, rotating external displays, and using Windows-mode
keyboards with Mac modifier-key positions.

## Install

Requires **macOS 13 or later**. Release DMGs include Apple silicon and Intel builds.

### Download a DMG

1. Download `CoffeeCup.dmg` from [GitHub Releases](https://github.com/johnnguyenn77/CoffeeCup/releases/latest).
2. Open it and drag **CoffeeCup** onto **Applications**.
3. Open CoffeeCup from `/Applications` and look for the coffee-cup menu-bar icon.

CoffeeCup is currently **ad-hoc signed**, not Developer ID signed or notarized.
macOS may show a security warning when opening a downloaded copy.

### Homebrew

CoffeeCup uses a custom tap, not the official Homebrew cask repository:

```sh
brew tap johnnguyenn77/coffeecup https://github.com/johnnguyenn77/CoffeeCup.git
brew install --cask johnnguyenn77/coffeecup/coffeecup
```

## Using CoffeeCup

Click the menu-bar icon to open and focus the compact popover. Click it again or
press **Escape** to close it. Clicking outside or switching apps also closes it.
If a settings menu or Cat Mode confirmation is open, Escape dismisses that first;
a second Escape closes the popover.

The gear menu contains **Launch at login**, external keyboard settings,
**About CoffeeCup** (including the installed version), and **Quit CoffeeCup**.
CoffeeCup has no normal Dock window.

### Keep display awake

Turn on **Keep display awake** to run the equivalent of:

```sh
caffeinate -d
```

CoffeeCup requests display-sleep prevention only; it does not add separate system-
or disk-sleep assertions. Turning the toggle off or quitting releases the assertion.
Internally, `-w <CoffeeCup PID>` also makes the helper exit if CoffeeCup terminates
unexpectedly.

### Cat Mode

Cat Mode blocks keyboard, trackpad, and mouse input so you can watch a video while
your cats walk on the laptop. Confirm activation to start; the popover then closes.

**To unlock, press Control–Option–Command–Escape (`⌃⌥⌘Esc`).**
Unlocking leaves the popover closed.

Cat Mode requires approval in **System Settings → Privacy & Security →
Accessibility**. CoffeeCup does not request Screen Recording access. Because the
app is ad-hoc signed, macOS may require Accessibility approval again after an update.

### External displays

The **Display** section appears only when an external display is detected,
including one connected before CoffeeCup starts. Its three buttons select
left portrait, normal landscape, or right portrait. A display picker appears when
more than one external display is connected.

Rotation depends on macOS and display support; failures appear in the popover.

### External keyboards and KVM switches

Leave your external keyboard in **Windows mode**, then enable **Swap Alt /
Windows** in the gear menu. If multiple keyboards are connected, select one in
the **Keyboard** submenu first. This exchanges left and right Alt/Option with
Windows/Command. Control, Shift, the function row, and the built-in keyboard are
unchanged.

Keyboard settings appear only when a supported external USB or Bluetooth keyboard
is detected. Mouse helper interfaces are filtered out; a mouse alone does not show
the swap option.

CoffeeCup remembers the choice per device and reapplies it after reconnecting or
waking while the app is running. Without a device serial number, the preference
is tied to its USB port, so keep using the same KVM/port.

Disconnects are silent, with a short, bounded discovery retry sequence for slow
KVM reconnects. Opening the popover also refreshes discovery. Mapping conflicts
and preference-save failures remain visible.

Turning the swap off or quitting restores the previous mappings without
overwriting unrelated remaps. If another app changes those modifiers, CoffeeCup
stops swapping rather than repeatedly overriding it. Run only one copy of
CoffeeCup when using this feature. It does not change keyboard firmware or your
Windows PC's settings.

### Launch at login

Enable **Launch at login** in the gear menu after installing into
`/Applications`. Approve it in **System Settings → General → Login Items** if asked.

The preference is stored outside the app bundle. CoffeeCup attempts to restore
registration when launched after replacement, but macOS may require renewed
approval for an ad-hoc signed update.

## Updating

CoffeeCup checks GitHub Releases on launch if a check is due, and every Wednesday
at **9 a.m. local time** while running. When a newer release is available, a
download icon appears beside the app name.

- **DMG installation:** Click the update icon to open the DMG download in your
  browser. Quit CoffeeCup, open the DMG, drag the new app into `/Applications`,
  choose **Replace**, then reopen it. CoffeeCup does not install updates itself.
- **Homebrew installation:** Use Homebrew so the installed cask stays in sync:

  ```sh
  brew update
  brew upgrade --cask johnnguyenn77/coffeecup/coffeecup
  ```

## Development

Build with **Xcode 26 or later**. The deployment target remains macOS 13;
newer appearance APIs are availability-guarded.

1. Open `CoffeeCup.xcodeproj`.
2. Select the **CoffeeCup** scheme and **My Mac** destination.
3. Quit any other CoffeeCup instance, then press **Run** (`⌘R`).
4. Click the coffee-cup menu-bar icon.

For a terminal Release build:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project CoffeeCup.xcodeproj -scheme CoffeeCup \
  -configuration Release -sdk macosx build
```

App Sandbox is disabled because CoffeeCup launches the system `caffeinate`
utility. No third-party runtime dependencies are required.

### Build an installer

```sh
./scripts/create-dmg.sh
open build/CoffeeCup.dmg
```

The script builds a universal Release app and creates the drag-and-drop DMG.
Local builds use ad-hoc signing unless you configure a signing identity in Xcode.

### Tests

```sh
bash scripts/test-keyboard-modifiers.sh
```

The suite covers keyboard mapping/filtering and reconnect recovery, native control
behavior, popover state transitions, Cat Mode filtering, and resource cleanup.
It uses simulated keyboards and does not change live mappings or install an input
blocker. A short `caffeinate` test checks cleanup when its temporary owner exits.
The release workflow runs this suite before building the DMG.

To build the separate native interaction-test app:

```sh
bash scripts/build-interaction-tests.sh
open "build/InteractionTests/CoffeeCup Input Tests.app"
```

The **T** menu-bar icon distinguishes it from CoffeeCup. Choose **Run popover
edge-case tests** to exercise actual AppKit focus, click routing, menus,
confirmation teardown, and the global-click/button-action race regression.
Cat Mode is simulated and never blocks input. The test window's keyboard and
rotation controls are also simulated; the production popover's display-awake and
rotation controls affect real hardware if enabled.

For a minimal SwiftUI-startup fixture for physical menu-bar clicks, build with
`bash scripts/build-interaction-tests.sh --swiftui` instead. Quit the test app when
finished. The installed CoffeeCup app is not replaced.

Physical external-display and KVM checks supplement the simulated tests.
See [the popover behavior contract](Design/PopoverBehavior.md) for expected states
and edge cases.

A read-only keyboard discovery benchmark is available with:

```sh
bash scripts/test-keyboard-modifiers.sh --benchmark-discovery
```

Discovery runs on a serial utility queue. Topology changes coalesce into bounded
fresh scans; idle, unmanaged keyboards have no polling timer. Five-second KVM
verification runs only while a connected device has an enabled swap or a mapping
needing restoration. Cat Mode's input thread exists only while enabled.

## Publishing a release

Review pending changes first: the helper commits **all** working-tree changes.

```sh
git status
./scripts/release.sh
```

The helper publishes the current version if it has no local tag yet; otherwise it
increments the patch version. It also increments the build number, commits, tags,
and pushes to `main`. To choose a version explicitly:

```sh
./scripts/release.sh 1.1.0
```

The tag push triggers [the release workflow](.github/workflows/release.yml), which
runs regression tests, builds the DMG, creates the GitHub release, uploads
`CoffeeCup.dmg`, and updates `Casks/coffeecup.rb` with the version and SHA-256.
A published release tag must match the app's marketing version.

Afterward, pull the workflow's cask-update commit before starting the next release
from an older checkout. Published builds remain ad-hoc signed until Developer ID
signing and notarization are configured.
