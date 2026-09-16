#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
project_file="$project_root/CoffeeCup.xcodeproj/project.pbxproj"

cd "$project_root"

current_version="$(awk -F ' = ' '/MARKETING_VERSION/ { sub(/;$/, "", $2); print $2; exit }' "$project_file")"
current_build="$(awk -F ' = ' '/CURRENT_PROJECT_VERSION/ { sub(/;$/, "", $2); print $2; exit }' "$project_file")"

if [[ ! "$current_version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "Expected a three-part MARKETING_VERSION, found: $current_version" >&2
    exit 1
fi
major="${BASH_REMATCH[1]}"
minor="${BASH_REMATCH[2]}"
patch="${BASH_REMATCH[3]}"

if [[ ! "$current_build" =~ ^[0-9]+$ ]]; then
    echo "Expected a numeric CURRENT_PROJECT_VERSION, found: $current_build" >&2
    exit 1
fi

if [[ $# -gt 1 ]]; then
    echo "Usage: ./scripts/release.sh [version]" >&2
    exit 1
fi

if [[ $# -eq 1 ]]; then
    next_version="$1"
elif git rev-parse --verify --quiet "refs/tags/v$current_version" >/dev/null; then
    next_version="$major.$minor.$((patch + 1))"
else
    next_version="$current_version"
fi

if [[ ! "$next_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Version must use MAJOR.MINOR.PATCH format: $next_version" >&2
    exit 1
fi

tag="v$next_version"
if git rev-parse --verify --quiet "refs/tags/$tag" >/dev/null; then
    echo "Tag already exists locally: $tag" >&2
    exit 1
fi

next_build=$((current_build + 1))

CURRENT_VERSION="$current_version" \
NEXT_VERSION="$next_version" \
CURRENT_BUILD="$current_build" \
NEXT_BUILD="$next_build" \
PROJECT_FILE="$project_file" \
perl -0pi -e '
    s/MARKETING_VERSION = \Q$ENV{CURRENT_VERSION}\E;/MARKETING_VERSION = $ENV{NEXT_VERSION};/g;
    s/CURRENT_PROJECT_VERSION = \Q$ENV{CURRENT_BUILD}\E;/CURRENT_PROJECT_VERSION = $ENV{NEXT_BUILD};/g;
' "$project_file"

git diff --check

git add -A
git commit -m "Release CoffeeCup $next_version"
git tag -a "$tag" -m "CoffeeCup $next_version"
git push origin main "$tag"

echo "Pushed CoffeeCup $next_version. GitHub Actions will build the DMG, create the release, and update the Homebrew cask."
