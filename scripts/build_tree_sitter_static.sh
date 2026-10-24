#!/usr/bin/env bash
# Build `libtree-sitter.a` for the `c3fmt-static` target.
#   Inspired by tree-sitter/setup-action, but disables _FORTIFY_SOURCE to prevent
#   __snprintf_chk etc. from causing undefined references when statically linking with musl.
# Run via: c3c build tree-sitter (requires: cmake, cc, git)

set -euo pipefail

TS_VERSION="${1:-0.26.9}"
TS_REPO="https://github.com/tree-sitter/tree-sitter"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/.."
INSTALL_DIR="$PROJECT_DIR/build/ts-lib"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

# dependency checks
for cmd in cmake git; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "error: '$cmd' not found in PATH" >&2
        exit 1
    fi
done

# skip rebuild if already built
if [[ -f "$INSTALL_DIR/lib/libtree-sitter.a" || -f "$INSTALL_DIR/lib/tree-sitter.lib" || -f "$INSTALL_DIR/lib/tree-sitter-static.lib" ]]; then
    echo "tree-sitter static library already present at $INSTALL_DIR/lib — skipping build."
    echo "Delete $INSTALL_DIR to force a rebuild."
    exit 0
fi

echo "Cloning tree-sitter @ v${TS_VERSION} ..."
git clone "$TS_REPO" "$STAGING/tree-sitter" --quiet --filter=blob:none
git -C "$STAGING/tree-sitter" checkout "v${TS_VERSION}" --quiet

# from their github actions
if [[ -f "$STAGING/tree-sitter/CMakeLists.txt" ]]; then
    LIB_DIR="."
else
    LIB_DIR="lib"
fi

OS="$(uname -s)"
C_FLAGS=""
EXTRA_CMAKE_FLAGS=()
if [[ "$OS" == "Linux" || "$OS" == "Darwin" ]]; then
    C_FLAGS="-U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0"
elif [[ "$OS" == MINGW* || "$OS" == MSYS* || "$OS" == CYGWIN* ]]; then
    # Use static MSVC runtime (/MT) to match c3c's --wincrt=static.
    # CMP0091=NEW is required or CMake silently ignores CMAKE_MSVC_RUNTIME_LIBRARY.
    EXTRA_CMAKE_FLAGS=(
        "-DCMAKE_POLICY_DEFAULT_CMP0091=NEW"
        "-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded"
    )
fi

echo "Configuring (static) ..."
cmake -S "$STAGING/tree-sitter/$LIB_DIR" -B "$STAGING/build" \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_C_FLAGS="$C_FLAGS" \
    ${EXTRA_CMAKE_FLAGS[@]+"${EXTRA_CMAKE_FLAGS[@]}"}

echo "Building ..."
cmake --build "$STAGING/build" --config Release --parallel

echo "Installing to $INSTALL_DIR ..."
cmake --install "$STAGING/build" --config Release

echo "Done. Static library written to $INSTALL_DIR/lib"
