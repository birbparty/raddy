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
  local is_vita=0
  for a in "$@"; do [[ "$a" == "-d:vita" ]] && is_vita=1; done
  echo "    nim check src/raddy.nim"
  nim check --mm:"$mm" --hints:off --path:src "$@" src/raddy.nim
  for f in src/raddy/*.nim src/raddy/backend/*.nim; do
    [[ -f "$f" ]] || continue
    # Platform-specific pumps have {.error.} guards for the opposite target.
    [[ "$f" == *pump_vita*   ]] && [[ $is_vita -eq 0 ]] && continue
    [[ "$f" == *pump_naylib* ]] && [[ $is_vita -eq 1 ]] && continue
    echo "    nim check $f"
    nim check --mm:"$mm" --hints:off --path:src "$@" "$f"
  done
}

# nimble check is the built-in package validator (distinct from the 'check'
# task in raddy.nimble, which runs nim check type-checking). Runs first so a
# malformed .nimble file fails fast before the heavier compilation steps.
echo "==> verify: nimble check (package + task definitions)"
nimble check

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

echo "==> verify: test_bundle_render with -d:raddyFixed (fixed-buffer bundle alignment regression — raddy-ac3)"
# This is the ONLY path that exercised the bug: a fixed-buffer bundle rendered
# nothing (or crashed) when its cmdBuf was under-aligned. nimble test runs this
# file on the heap path (which always rendered), so the fixed-path regression is
# guarded HERE.
nim c --mm:orc --hints:off --path:src -d:raddyFixed \
  --path:"$BDDY_DIR" \
  ${NAYLIB_PASSC} \
  -r tests/test_bundle_render.nim

echo "==> verify: vita C surface check — generate + gcc -fsyntax-only against stub"
# Two-step check: Nim generates C; host gcc validates the generated C against the stub.
# Step 1: generate C for the vita render+font+geom surface.
#   --os:linux --cpu:amd64 avoids arm-vita-eabi-gcc (not installed on CI) while
#   still triggering all -d:vita Nim preprocessor branches.
#   {.exportc.} in vita_surface_check.nim prevents DCE of raddyRender + dependencies.
VITA_CACHE=/tmp/raddy_vita_surface_check
nim c --compileOnly --mm:arc --hints:off --path:src -d:vita \
  --os:linux --cpu:amd64 \
  --nimcache:"$VITA_CACHE" \
  tests/stubs/vita_surface_check.nim
# Step 2: syntax-check the generated C files against tests/stubs/raylib.h.
#   raylib_api / render / font / geom are the only files that import raylib symbols.
# Extract the Nim stdlib include path from the generated JSON build descriptor.
NIMLIB=$(grep -oE '\-I(/[^"]+/lib)' "$VITA_CACHE/vita_surface_check.json" | head -1 | sed 's/-I//')
gcc -std=c99 -fsyntax-only -w \
  -Itests/stubs \
  -I"$NIMLIB" \
  -Isrc/raddy/vendor \
  -include src/raddy/vendor/nk_config.h \
  -D__vita__ \
  "$VITA_CACHE/@praddy@sbackend@sraylib_api.nim.c" \
  "$VITA_CACHE/@praddy@sbackend@srender.nim.c" \
  "$VITA_CACHE/@praddy@sbackend@sfont.nim.c" \
  "$VITA_CACHE/@praddy@sbackend@sgeom.nim.c" \
  "$VITA_CACHE/@praddy@sbackend@spump_vita.nim.c"
echo "    vita C surface check: OK"
# Symbol presence/naming on the real vita console (arm-vita-eabi-gcc) is in raddy-tzc.

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

echo "==> verify: core import purity (no naylib/backend imports in core modules)"
CORE_FILES=(
  src/raddy/types.nim src/raddy/errors.nim src/raddy/context.nim
  src/raddy/style.nim src/raddy/input.nim  src/raddy/layout.nim
  src/raddy/widgets.nim src/raddy/vendor.nim
)
# Two-stage grep: extract import/include/from lines, then search for the
# forbidden name anywhere in the module list (catches `import std/os, naylib`).
# Word-boundary via ([[:space:],/]|$) prevents `naylib_compat` false positives.
IMPORT_LINES=$(grep -n -E '^\s*(import|include|from)\s+' \
  "${CORE_FILES[@]}" 2>/dev/null || true)
PURITY_VIOLATIONS=$(printf '%s\n' "$IMPORT_LINES" | \
  grep -E '(naylib|raylib_console|inputty)([[:space:],/]|$)' || true)
BACKEND_VIOLATIONS=$(printf '%s\n' "$IMPORT_LINES" | \
  grep -E '(\.\/backend|raddy\/backend)' || true)
if [[ -n "$PURITY_VIOLATIONS" || -n "$BACKEND_VIOLATIONS" ]]; then
  echo "  ERROR: core module import purity violation:" >&2
  [[ -n "$PURITY_VIOLATIONS"  ]] && echo "$PURITY_VIOLATIONS"  >&2
  [[ -n "$BACKEND_VIOLATIONS" ]] && echo "$BACKEND_VIOLATIONS" >&2
  exit 1
fi
echo "    core purity: OK (no naylib/raylib_console/inputty/backend imports in core)"

echo "==> verify: compile-check examples/demo.nim (desktop)"
NAYLIB_DIR_DEMO=$(find "$HOME/.nimble/pkgs2" -maxdepth 1 -name 'naylib-*' -type d | head -1)
if [[ -n "$NAYLIB_DIR_DEMO" ]]; then
  nim c --compileOnly --mm:orc --hints:off --path:src \
    --path:"$NAYLIB_DIR_DEMO" \
    --passC:"-I${NAYLIB_DIR_DEMO}/raylib" \
    examples/demo.nim
  echo "    examples/demo.nim: OK"
else
  echo "    WARNING: naylib not found — skipping examples/demo.nim compile check"
fi

echo "==> verify: test_smoke_headless (demo UI, 5 frames, -d:raddyFixed)"
BDDY_DIR_SMOKE=$(find "$HOME/.nimble/pkgs2" -maxdepth 1 -name 'bddy-*' -type d | head -1)
if [[ -z "$BDDY_DIR_SMOKE" ]]; then
  echo "    ERROR: bddy not found in ~/.nimble/pkgs2 — run: nimble install bddy" >&2
  exit 1
fi
nim c --mm:orc --hints:off --path:src --path:"$BDDY_DIR_SMOKE" \
  -d:raddyFixed \
  -r tests/test_smoke_headless.nim

echo "==> verify: nimble test"
nimble test

echo "==> verify: OK"
