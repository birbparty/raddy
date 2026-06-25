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
  for f in src/raddy/*.nim; do
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

echo "==> verify: compile-only check src/raddy/context.nim (desktop + vita)"
nim c --compileOnly --mm:orc --hints:off --path:src src/raddy/context.nim
nim c --compileOnly --mm:arc --hints:off --path:src -d:vita src/raddy/context.nim

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
