#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
output_dir="$project_root/build/KeyboardModifierTests"
mkdir -p "$output_dir"
xcrun swiftc -swift-version 5 -default-isolation MainActor -parse-as-library -D COFFEECUP_CORE_TESTS \
    "$project_root/CoffeeCup/KeyboardModifierModels.swift" \
    "$project_root/CoffeeCup/KeyboardHIDService.swift" \
    "$project_root/CoffeeCup/KeyboardModifierEngine.swift" \
    "$project_root/CoffeeCup/KeyboardModifierWorker.swift" \
    "$project_root/CoffeeCup/KeyboardModifierController.swift" \
    "$project_root/CoffeeCup/CoffeeCupController.swift" \
    "$project_root/CoffeeCup/CatModeController.swift" \
    "$project_root/CoffeeCup/CatModeInputSession.swift" \
    "$project_root/CoffeeCup/CoffeeCupSettingsButton.swift" \
    "$project_root/CoffeeCup/CoffeeCupToggleRow.swift" \
    "$project_root/CoffeeCup/PopoverInteraction.swift" \
    "$project_root/Tests/PopoverInteractionTests.swift" \
    "$project_root/Tests/NativeControlTests.swift" \
    "$project_root/Tests/KeyboardDisconnectTests.swift" \
    "$project_root/Tests/ResourceUsageTests.swift" \
    "$project_root/Tests/KeyboardModifierTests.swift" \
    -o "$output_dir/KeyboardModifierTests"
"$output_dir/KeyboardModifierTests" "$@"
