#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
build_dir="$project_root/build"
derived_data_dir="$build_dir/DerivedData"
dmg_path="$build_dir/CoffeeCup.dmg"

if [[ -x "/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild" ]]; then
    developer_dir="/Applications/Xcode.app/Contents/Developer"
else
    developer_dir="$(xcode-select -p)"
fi

mkdir -p "$build_dir"

echo "Building CoffeeCup.app in Release configuration..."
DEVELOPER_DIR="$developer_dir" \
xcodebuild \
    -project "$project_root/CoffeeCup.xcodeproj" \
    -scheme CoffeeCup \
    -configuration Release \
    -sdk macosx \
    -derivedDataPath "$derived_data_dir" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    build

app_path="$derived_data_dir/Build/Products/Release/CoffeeCup.app"
if [[ ! -d "$app_path" ]]; then
    echo "Could not find the Release app at $app_path" >&2
    exit 1
fi

staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/CoffeeCup-dmg.XXXXXX")"
cleanup() {
    rm -rf "$staging_dir"
}
trap cleanup EXIT

ditto "$app_path" "$staging_dir/CoffeeCup.app"
ln -s /Applications "$staging_dir/Applications"

echo "Creating $dmg_path..."
hdiutil create \
    -volname CoffeeCup \
    -srcfolder "$staging_dir" \
    -ov \
    -format UDZO \
    "$dmg_path" >/dev/null

echo "Created $dmg_path"
