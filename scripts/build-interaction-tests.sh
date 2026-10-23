#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
output_dir="$project_root/build/InteractionTests"
app_path="$output_dir/CoffeeCup Input Tests.app"
mkdir -p "$app_path/Contents/MacOS"
launch_flags=()
if [[ "${1:-}" == "--swiftui" ]]; then
    launch_flags=(-D COFFEECUP_SWIFTUI_INTERACTION_TESTS)
fi
xcrun swiftc -swift-version 5 -default-isolation MainActor -parse-as-library -O \
    ${launch_flags[@]+"${launch_flags[@]}"} \
    -D COFFEECUP_INTERACTION_TESTS -target "$(uname -m)-apple-macosx13.0" \
    "$project_root"/CoffeeCup/*.swift \
    "$project_root/Tests/KeyboardModifierTests.swift" \
    "$project_root/Tests/NativePopoverTests.swift" \
    "$project_root/Tests/InteractionHarness.swift" \
    -o "$app_path/Contents/MacOS/InputTests"
cp "$project_root/Tests/InteractionHarness-Info.plist" "$app_path/Contents/Info.plist"
codesign --force --sign - "$app_path"
echo "Built: $app_path"
echo "Open it to test the production popover and simulated click targets without installing CoffeeCup."
