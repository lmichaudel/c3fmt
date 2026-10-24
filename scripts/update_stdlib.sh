#!/usr/bin/env bash
# Update test/stdlib/src from the upstream c3c repo.
#
# Usage:
#   ./scripts/update_stdlib.sh [ref]
#
# Arguments:
#   ref  Git branch, tag or commit to use (default: master)

set -euo pipefail

REF="${1:-master}"
REPO="https://github.com/c3lang/c3c"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STDLIB_SRC_DIR="$SCRIPT_DIR/../test/stdlib/src"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

# dependency checks
for cmd in git; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "error: '$cmd' not found in PATH" >&2
        exit 1
    fi
done

# clone
echo "Cloning $REPO @ $REF ..."
git clone --quiet --depth=1 "$REPO" "$STAGING/repo"
(
    cd "$STAGING/repo"
    git fetch --quiet --depth=1 origin "$REF"
    git checkout --quiet FETCH_HEAD
)

# sync
echo "Syncing stdlib/src ..."
mkdir -p "$STDLIB_SRC_DIR"
rm -rf "$STDLIB_SRC_DIR"/*
rm -rf "$SCRIPT_DIR/../test/stdlib/src-formatted"

cp -r "$STAGING/repo/lib/std"/* "$STDLIB_SRC_DIR/"

echo "Done. test/stdlib/src updated from $REPO/lib/std @ $REF"
