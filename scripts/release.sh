#!/bin/sh
set -eu

version="${1:-}"
if ! printf '%s' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "usage: scripts/release.sh MAJOR.MINOR.PATCH" >&2
    exit 1
fi

cd "$(dirname "$0")/.."

if [ "$(git rev-parse --abbrev-ref HEAD)" != "main" ]; then
    echo "Releases are cut from main." >&2
    exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
    echo "Working tree is not clean." >&2
    exit 1
fi
if git rev-parse -q --verify "refs/tags/v$version" >/dev/null; then
    echo "Tag v$version already exists." >&2
    exit 1
fi

notes=$(scripts/changelog-section.sh Unreleased)
if [ -z "$notes" ]; then
    echo "The Unreleased section of CHANGELOG.md is empty." >&2
    exit 1
fi

swift test

today=$(date +%Y-%m-%d)
awk -v v="$version" -v d="$today" '
    /^## \[Unreleased\]/ { print; print ""; print "## [" v "] - " d; next }
    { print }
' CHANGELOG.md > CHANGELOG.md.tmp
mv CHANGELOG.md.tmp CHANGELOG.md
printf '%s\n' "$version" > VERSION

git add CHANGELOG.md VERSION
git commit -m "Release $version"
git tag -a "v$version" -m "ThreadHaven $version" -m "$notes"

echo "Tagged v$version. Push with: git push origin main v$version"
