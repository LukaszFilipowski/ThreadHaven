#!/bin/sh
set -eu

section="${1:?usage: scripts/changelog-section.sh VERSION|Unreleased}"
awk -v s="$section" '
    /^## \[/ { if (found) exit; if (index($0, "## [" s "]") == 1) { found = 1; next } }
    found { print }
' "$(dirname "$0")/../CHANGELOG.md" | sed -e '/./,$!d' | sed -e ':a' -e '/^\n*$/{$d;N;ba' -e '}'
