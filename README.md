# CoffeeCup

CoffeeCup is a tiny macOS menu-bar app for toggling `caffeinate`.

When the toggle is on, the app runs:

```sh
caffeinate -dimsu
```

That prevents idle system sleep, display sleep, disk idle sleep, and system sleep while the app is active. Turn the toggle off to stop the command and restore normal sleep behavior.

## Requirements

- macOS 13.0 or later

## Run it in Xcode

1. Open `CoffeeCup.xcodeproj` in Xcode.
2. Select the `CoffeeCup` scheme and choose **My Mac** as the run destination.
3. Press **Run** (`⌘R`).
4. Look for the coffee-cup icon in the macOS menu bar.
5. Click the icon and switch on **Keep Mac awake**.

The app is configured as a menu-bar accessory, so it does not open a normal Dock window. Use **Quit** in the popover to close it.

## Install as an app

For a local install, use a signed Release build:

1. In Xcode, select the **CoffeeCup** target and open **Signing & Capabilities**.
2. Choose your Apple Development team. Xcode may ask you to use a unique bundle identifier.
3. Choose **Product → Archive**.
4. In the Organizer, choose **Distribute App → Copy App**, then save `CoffeeCup.app`.
5. Drag `CoffeeCup.app` into `/Applications` and open it from there.

The popover includes a **Launch at login** toggle. Turn it on after installing the app. If macOS asks for approval, open **System Settings → General → Login Items** and allow CoffeeCup. The app must be code-signed for macOS to register it as a login item.

## Create a DMG

The repository includes a drag-and-drop installer script:

```sh
./scripts/create-dmg.sh
open build/CoffeeCup.dmg
```

The DMG contains `CoffeeCup.app` and an `/Applications` shortcut. Drag the app onto the shortcut, open it from `/Applications`, and enable **Launch at login**. Configure your Apple Development team in Xcode first if you want Login Items registration to work; otherwise the local build will be ad-hoc signed.

## Terminal build

From the project directory:

```sh
xcodebuild -project CoffeeCup.xcodeproj -scheme CoffeeCup -configuration Debug -sdk macosx build
```

The app uses `/usr/bin/caffeinate`, which is built into macOS. App Sandbox is disabled because the utility launches this system command directly.

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
2. Enter a new version tag, such as `v1.0.2`, and select `main` as the target.
3. Publish the release.
4. Wait for the **Release CoffeeCup** GitHub Actions workflow to finish.

The workflow attaches `CoffeeCup.dmg` to the release. Users can download the DMG from the release page, drag CoffeeCup into `/Applications`, and enable **Launch at login**.

The automated workflow currently creates an ad-hoc signed build. For a public download without Gatekeeper warnings, configure Apple Developer ID signing and notarization in the workflow before distributing it broadly.
