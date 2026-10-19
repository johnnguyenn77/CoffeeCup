#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
output_dir="$project_root/build/KeyboardModifierTests"
mkdir -p "$output_dir"
xcrun swiftc -swift-version 5 -parse-as-library \
    "$project_root/CoffeeCup/KeyboardModifierModels.swift" \
    "$project_root/CoffeeCup/KeyboardHIDService.swift" \
    "$project_root/CoffeeCup/KeyboardModifierEngine.swift" \
    "$project_root/Tests/KeyboardModifierTests.swift" \
    -o "$output_dir/KeyboardModifierTests"
"$output_dir/KeyboardModifierTests" "$@"
