#!/usr/bin/env bash
# Update lib/tree_sitter_c3.c3l from the upstream tree-sitter-c3 repo.
#
# Usage:
#   ./scripts/update_tree_sitter_c3.sh [ref]
#
# Arguments:
#   ref  Git branch, tag or commit to use (default: main)
#
# Requirements: git, tree-sitter CLI, zip

set -euo pipefail

REF="${1:-main}"
REPO="https://github.com/c3lang/tree-sitter-c3"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

# dependency checks
for cmd in git tree-sitter zip; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "error: '$cmd' not found in PATH" >&2
        [[ "$cmd" == "tree-sitter" ]] && echo "  install with: npm install -g tree-sitter-cli" >&2
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

# generate
echo "Running tree-sitter generate ..."
(
    cd "$STAGING/repo"
    tree-sitter generate
)

# stage
echo "Staging files ..."
mkdir -p "$STAGING/c3l/src/tree_sitter"

cp "$STAGING/repo/bindings/c3/tree_sitter_c3.c3l/manifest.json"      "$STAGING/c3l/"
cp "$STAGING/repo/bindings/c3/tree_sitter_c3.c3l/tree_sitter_c3.c3i" "$STAGING/c3l/"

# Fix the ../../../src relative paths for the .c3l layout
perl -pi -e 's|\Q../../../src\E|src|g' "$STAGING/c3l/manifest.json"
perl -pi -e 's|\Q../../../src\E|src|g' "$STAGING/c3l/tree_sitter_c3.c3i"

# Move -fPIC to specific non-windows targets to avoid MSVC warnings
perl -pi -e 's|"cflags" : "-O2 -fPIC"|"cflags" : "-O2"|g' "$STAGING/c3l/manifest.json"
perl -0pi -e 's/("(?:linux-x64|linux-x86|macos-x64|macos-aarch64)"\s*:\s*)\{\s*\}/${1}{ "cflags": "-fPIC" }/g' "$STAGING/c3l/manifest.json"

# Ensure Windows targets are available in the manifest (NOTE: fix this upstream)
for target in "windows-x64" "windows-aarch64"; do
    if ! grep -q "$target" "$STAGING/c3l/manifest.json"; then
        perl -pi -e 's|("targets" : \{)|$1\n    "'"$target"'" : { },|g' "$STAGING/c3l/manifest.json"
    fi
done

cp "$STAGING/repo/src/parser.c" "$STAGING/repo/src/scanner.c" \
   "$STAGING/repo/src/node-types.json" "$STAGING/repo/src/grammar.json" "$STAGING/c3l/src/"

cp "$STAGING/repo/src/tree_sitter/parser.h" \
   "$STAGING/repo/src/tree_sitter/array.h" \
   "$STAGING/repo/src/tree_sitter/alloc.h" "$STAGING/c3l/src/tree_sitter/"

# pack
echo "Packing .c3l ..."
(
    cd "$STAGING/c3l"
    zip --quiet -r tree_sitter_c3.c3l .
)

# install
cp "$STAGING/c3l/tree_sitter_c3.c3l" "$LIB_DIR/tree_sitter_c3.c3l"

echo "Clearing compiler caches to ensure library reload ..."
rm -rf "$SCRIPT_DIR/../build" "$HOME/.c3"

echo "Done. lib/tree_sitter_c3.c3l updated from $REPO @ $REF"
