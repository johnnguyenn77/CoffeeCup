#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--test" && "$1" != "--build-only" ) ]]; then
    echo "Usage: $0 [--test|--build-only]" >&2
    exit 1
fi
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
source_dir="$project_root/Demos/CleanPopover"
output_dir="$project_root/build/CleanPopoverDemo"
app_path="$output_dir/CoffeeCup Layout Demo.app"

if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

mkdir -p "$output_dir"
xcrun swiftc -swift-version 5 -parse-as-library \
    "$source_dir/DemoState.swift" "$source_dir/StateTests.swift" \
    -o "$output_dir/StateTests"
"$output_dir/StateTests"
if [[ "${1:-}" == "--test" ]]; then exit 0; fi

mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
xcrun swiftc -swift-version 5 -parse-as-library -O \
    -target "$(uname -m)-apple-macosx13.0" \
    "$source_dir/DemoState.swift" "$source_dir/DemoView.swift" "$source_dir/DemoApp.swift" \
    "$project_root/CoffeeCup/DisplayRotationControls.swift" \
    -o "$app_path/Contents/MacOS/CleanPopoverDemo"
cp "$source_dir/Info.plist" "$app_path/Contents/Info.plist"
xcrun actool "$project_root/CoffeeCup/AppIcon.icon" \
    --compile "$app_path/Contents/Resources" --platform macosx --target-device mac \
    --minimum-deployment-target 13.0 --app-icon AppIcon \
    --output-partial-info-plist "$output_dir/AppIcon-Info.plist" >/dev/null
codesign --force --sign - "$app_path"
echo "Built: $app_path"
if [[ "${1:-}" != "--build-only" ]]; then open "$app_path"; fi
