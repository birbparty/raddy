#!/usr/bin/env bash
# Nim VERIFY script — run by `make test` and the ralph pre-commit hook.
# Runs `nim check` (semantic type-check, no codegen) on src/raddy.nim and all
# src/raddy/*.nim submodules for both desktop and Vita targets, runs a C syntax
# check on nuklear_impl.c (desktop and Vita macro configurations), then runs
# the nimble test suite.
set -euo pipefail
trap 'echo "==> verify: FAILED" >&2' ERR

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Type-check the entry point and all submodules under a given memory model.
# The glob guard handles the current empty src/raddy/ state safely.
check_target() {
  local mm="$1"; shift
  echo "    nim check src/raddy.nim"
  nim check --mm:"$mm" --hints:off --path:src "$@" src/raddy.nim
  for f in src/raddy/*.nim src/raddy/backend/*.nim; do
    [[ -f "$f" ]] || continue
    echo "    nim check $f"
    nim check --mm:"$mm" --hints:off --path:src "$@" "$f"
  done
}

# Desktop is also exercised by `nimble test` below; this is a fast lib-only
# pre-flight that isolates library failures from test failures.
echo "==> verify: type-check desktop (--mm:orc)"
check_target orc

echo "==> verify: type-check vita (-d:vita --mm:arc)"
check_target arc -d:vita

echo "==> verify: compile-only check src/raddy/types.nim (desktop + vita)"
nim c --compileOnly --mm:orc --hints:off --path:src src/raddy/types.nim
nim c --compileOnly --mm:arc --hints:off --path:src -d:vita src/raddy/types.nim

echo "==> verify: compile-only check src/raddy/errors.nim (desktop + vita)"
nim c --compileOnly --mm:orc --hints:off --path:src src/raddy/errors.nim
nim c --compileOnly --mm:arc --hints:off --path:src -d:vita src/raddy/errors.nim
echo "==> verify: compile-only check errors.nim with buffer size override"
nim c --compileOnly --mm:arc --hints:off --path:src -d:vita -d:raddyCmdBufBytes=32768 src/raddy/errors.nim

echo "==> verify: compile-only check src/raddy/backend/raylib_api.nim"
NAYLIB_DIR=$(find "$HOME/.nimble/pkgs2" -maxdepth 1 -name 'naylib-*' -type d | head -1)
if [[ -n "$NAYLIB_DIR" ]]; then
  nim c --compileOnly --mm:orc --hints:off --path:src --passC:"-I${NAYLIB_DIR}/raylib" \
    tests/verify_raylib_codegen.nim
  echo "    C names verified against raylib.h"
else
  echo "    WARNING: naylib not found in ~/.nimble/pkgs2 — skipping C-name verification"
fi

echo "==> verify: compile-only check src/raddy/input.nim (desktop + vita)"
nim c --compileOnly --mm:orc --hints:off --path:src src/raddy/input.nim
nim c --compileOnly --mm:arc --hints:off --path:src -d:vita src/raddy/input.nim

echo "==> verify: compile-only check src/raddy/context.nim (desktop + vita)"
nim c --compileOnly --mm:orc --hints:off --path:src src/raddy/context.nim
nim c --compileOnly --mm:arc --hints:off --path:src -d:vita src/raddy/context.nim

BDDY_DIR="$(find "$HOME/.nimble/pkgs2" -maxdepth 1 -name 'bddy-*' -type d | head -1)"

echo "==> verify: test_context with -d:raddyFixed (exercises overflow detection)"
nim c --mm:orc --hints:off --path:src -d:raddyFixed \
  --path:"$BDDY_DIR" \
  -r tests/test_context.nim

echo "==> verify: test_input with -d:raddyFixed (exercises fixed-buffer path)"
nim c --mm:orc --hints:off --path:src -d:raddyFixed \
  --path:"$BDDY_DIR" \
  -r tests/test_input.nim

echo "==> verify: test_render with -d:raddyFixed (exercises render overflow branch)"
NAYLIB_PASSC=""
if [[ -n "${NAYLIB_DIR:-}" ]]; then
  NAYLIB_PASSC="--passC:-I${NAYLIB_DIR}/raylib"
fi
nim c --mm:orc --hints:off --path:src -d:raddyFixed \
  --path:"$BDDY_DIR" \
  ${NAYLIB_PASSC} \
  -r tests/test_render.nim

echo "==> verify: nuklear.h SHA256 matches VENDORED.md"
EXPECTED_SHA=$(grep 'SHA256 of `nuklear.h`' src/raddy/vendor/VENDORED.md | grep -oE '[0-9a-f]{64}')
ACTUAL_SHA=$(sha256sum src/raddy/vendor/nuklear.h | awk '{print $1}')
if [[ "$EXPECTED_SHA" != "$ACTUAL_SHA" ]]; then
  echo "  ERROR: nuklear.h SHA256 mismatch" >&2
  echo "    VENDORED.md: $EXPECTED_SHA" >&2
  echo "    actual:      $ACTUAL_SHA" >&2
  echo "  Update VENDORED.md after upgrading nuklear.h." >&2
  exit 1
fi
echo "    SHA256 verified: $ACTUAL_SHA"

echo "==> verify: compile-check nuklear_impl.c (desktop)"
command -v gcc >/dev/null || { echo "verify: gcc not found — install a C compiler" >&2; exit 1; }
gcc -std=c99 -fsyntax-only -Wall \
  -Isrc/raddy/vendor \
  src/raddy/vendor/nuklear_impl.c

echo "==> verify: compile-check nuklear_impl.c (vita macro path)"
gcc -std=c99 -fsyntax-only -Wall \
  -DNK_VITA \
  -Isrc/raddy/vendor \
  src/raddy/vendor/nuklear_impl.c

echo "==> verify: nimble test"
nimble test

echo "==> verify: OK"
