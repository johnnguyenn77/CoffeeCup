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

The app is configured as a menu-bar accessory, so it does not open a normal Dock window. Use **Quit** in the popover to close it.

## Install as an app

For a local install, use a signed Release build:

1. In Xcode, select the **CoffeeCup** target and open **Signing & Capabilities**.
2. Choose your Apple Development team. Xcode may ask you to use a unique bundle identifier.
3. Choose **Product → Archive**.
4. In the Organizer, choose **Distribute App → Copy App**, then save `CoffeeCup.app`.
5. Drag `CoffeeCup.app` into `/Applications` and open it from there.

The popover includes a **Launch at login** toggle. Turn it on after installing the app. If macOS asks for approval, open **System Settings → General → Login Items** and allow CoffeeCup. The app must be code-signed for macOS to register it as a login item.

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
