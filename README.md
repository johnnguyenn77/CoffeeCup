# CoffeeCup

CoffeeCup is a tiny macOS menu-bar app for keeping the display awake.

When the toggle is on, the app runs:

```sh
caffeinate -d
```

That prevents the display from sleeping while the app is active. System and disk sleep continue to work normally. Turn the toggle off to stop the command.

CoffeeCup checks GitHub for a newer release on first launch when needed, then every Wednesday at 9 a.m. local time while the app is running. If an update is available, a download icon appears beside the app name and downloads the release DMG when clicked. To update a DMG-installed copy, quit CoffeeCup, open the downloaded DMG, drag CoffeeCup into `/Applications`, and choose **Replace** when prompted. Then reopen the app. If installed with Homebrew, update it with the Homebrew command below so the cask stays in sync.

## Requirements

- macOS 13.0 or later

## Run it in Xcode

1. Open `CoffeeCup.xcodeproj` in Xcode.
2. Select the `CoffeeCup` scheme and choose **My Mac** as the run destination.
3. Press **Run** (`⌘R`).
4. Look for the coffee-cup icon in the macOS menu bar.
5. Click the icon and switch on **Keep display awake**.

The app is configured as a menu-bar accessory, so it does not open a normal Dock window.
The popover keeps **Keep display awake** and **Cat Mode** within reach. **Display**
rotation controls appear only when an external display is connected, with a display
picker when more than one is connected. Open the gear menu for **Launch at login**,
external keyboard settings, **About CoffeeCup** (including the installed version),
and **Quit CoffeeCup**.

## External keyboards and KVM switches

Keep your external keyboard in **Windows mode**, then open CoffeeCup’s gear menu
and enable **Swap Alt / Windows**. If multiple external keyboards are connected,
choose the one to configure in the **Keyboard** submenu first. This exchanges left and
right Alt/Option with Windows/Command, giving those keys their usual Mac positions.
Control, Shift, the function row, and the Mac’s built-in keyboard are unchanged.

Keyboard settings appear when a supported USB or Bluetooth keyboard is connected,
including keyboards already attached when CoffeeCup starts. These menu items
hide when the last external keyboard disconnects; the built-in keyboard or a
mouse alone does not show the swap option. USB devices whose
primary HID interface is a mouse are excluded, even if they expose extra keyboard
interfaces for macro buttons. Detection uses the physical USB device rather than
the helper event service; ambiguous pointer devices without keyboard evidence are
also excluded.
CoffeeCup remembers the setting per device and reapplies it after reconnects or
wake while the app is running. Without a device serial number, the preference is
tied to its USB port, so use the same KVM/port or select and enable it again.
Temporary reconnect failures keep the saved preference and retry; a conflicting
mapping from another app still stops the swap for safety.

Turning the swap off or quitting CoffeeCup restores the previous mappings, while
preserving unrelated key remaps. If another app changes the same modifiers,
CoffeeCup stops swapping instead of repeatedly overriding it. Run only one copy of
CoffeeCup when using this feature; it does not change the keyboard’s firmware or
your Windows PC’s settings.

## Install as an app

For a local install, use a signed Release build:

1. In Xcode, select the **CoffeeCup** target and open **Signing & Capabilities**.
2. Choose your Apple Development team. Xcode may ask you to use a unique bundle identifier.
3. Choose **Product → Archive**.
4. In the Organizer, choose **Distribute App → Copy App**, then save `CoffeeCup.app`.
5. Drag `CoffeeCup.app` into `/Applications` and open it from there.

The gear menu includes a **Launch at login** option. Turn it on after installing the app. If macOS asks for approval, open **System Settings → General → Login Items** and allow CoffeeCup. The app must be code-signed for macOS to register it as a login item.

CoffeeCup saves your Launch at login preference outside the app bundle and restores the login item when the app starts after an update. With an ad-hoc signed build, macOS may still require approval after replacing the app; Developer ID signing and notarization provide the smoothest update experience.

## Create a DMG

The repository includes a drag-and-drop installer script:

```sh
./scripts/create-dmg.sh
open build/CoffeeCup.dmg
```

Release DMGs are built for both Apple silicon and Intel Macs.

The DMG contains `CoffeeCup.app` and an `/Applications` shortcut. Drag the app onto the shortcut, open it from `/Applications`, and enable **Launch at login**. Configure your Apple Development team in Xcode first if you want Login Items registration to work; otherwise the local build will be ad-hoc signed.

## Install with Homebrew

After the `v1.0.3` release is published, CoffeeCup will be available through a custom Homebrew tap backed by this repository. It is not part of the official Homebrew cask repository, and the app is currently ad-hoc signed.

Add the tap and install CoffeeCup with:

```sh
brew tap johnnguyenn77/coffeecup https://github.com/johnnguyenn77/CoffeeCup.git
brew install --cask johnnguyenn77/coffeecup/coffeecup
```

To update CoffeeCup later:

```sh
brew update
brew upgrade --cask johnnguyenn77/coffeecup/coffeecup
```

The release workflow updates `Casks/coffeecup.rb` with the new release version and DMG checksum whenever a GitHub release is published. Because the app is not notarized yet, macOS may show a security warning when it is first opened.

## Terminal build

From the project directory:

```sh
xcodebuild -project CoffeeCup.xcodeproj -scheme CoffeeCup -configuration Debug -sdk macosx build
```

The app uses `/usr/bin/caffeinate`, which is built into macOS. App Sandbox is disabled because the utility launches this system command directly.

Run the keyboard mapping and reconnect regression checks with:

```sh
bash scripts/test-keyboard-modifiers.sh
```

These checks use simulated devices and do not change your live keyboard mappings.
They also check native menu visibility, checkmarks, and first-click acceptance.
The suite additionally checks Cat Mode's filtering and background run-loop lifecycle
without installing an input blocker or requesting Accessibility. A short native
`caffeinate` test verifies owner-exit cleanup using a temporary test process.

Keyboard discovery and preference recovery run on one serial utility queue, not the
UI thread. Plug/unplug and wake notifications trigger fresh discovery. USB device
classification is cached between topology changes, and bursts of refresh requests
are coalesced. The five-second KVM verification timer runs only while a connected
device has an enabled swap or a live mapping needing restoration; idle unmanaged
devices have no polling timer. Cat Mode's event thread exists only while enabled
and is released on exit; its unlock path does not wait for the UI thread.

To measure native discovery without changing device mappings:

```sh
bash scripts/test-keyboard-modifiers.sh --benchmark-discovery
```

The benchmark compares repeated full USB classification with cached classification
and verifies that both produce identical device lists. The release workflow runs
the regression tests before building or uploading a DMG.

To build the isolated accessory-app interaction harness:

```sh
bash scripts/build-interaction-tests.sh
open "build/InteractionTests/CoffeeCup Input Tests.app"
```

Its test-window row, keyboard menu, and rotation selector use simulated state, so
you can test clicks and hot-plug scenarios without changing your devices. **Open
real CoffeeCup popover** opens the production popover in that separate test app;
its controls affect real hardware if enabled. The physical-modifier readout observes
only modifier presses delivered to the test app, not text or input in other apps.
Quit the test app when finished; the installed CoffeeCup app is not replaced.

## GitHub Releases

The repository includes a GitHub Actions workflow that builds the DMG and uploads it to a GitHub release when you publish that release.

After creating a GitHub repository and adding it as `origin`:

```sh
git add -A
git commit -m "Prepare CoffeeCup release"
git push -u origin main
```

Then create the release on GitHub:

1. Open **Releases → Draft a new release**.
2. Enter a new version tag matching the project version, such as `v1.0.3`, and select `main` as the target.
3. Publish the release.
4. Wait for the **Release CoffeeCup** GitHub Actions workflow to finish.

The workflow attaches `CoffeeCup.dmg` to the release and updates the Homebrew cask on `main`. Users can download the DMG from the update icon or the release page, drag CoffeeCup into `/Applications`, and enable **Launch at login**.

The automated workflow currently creates an ad-hoc signed build. For a public download without Gatekeeper warnings, configure Apple Developer ID signing and notarization in the workflow before distributing it broadly.

## Publish a release

After making app changes, use the release helper from the project directory:

```sh
./scripts/release.sh
```

This publishes the current project version if it has not been tagged yet; subsequent runs increment the patch version. It also increments the build number, commits the changes, creates a matching Git tag, and pushes both to GitHub. To choose a specific version instead, pass it explicitly:

```sh
./scripts/release.sh 1.1.0
```

The tag push automatically creates the GitHub release, uploads the DMG, and refreshes the Homebrew cask. After the release workflow finishes, update an existing installation with:

```sh
brew update
brew upgrade --cask johnnguyenn77/coffeecup/coffeecup
```

The release workflow also updates `Casks/coffeecup.rb` on `main`; pull that workflow commit before starting the next release from an older local checkout.
