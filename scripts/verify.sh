#!/usr/bin/env bash
# Nim VERIFY script — run by `make test` and the ralph pre-commit hook.
# Runs type-check (--compileOnly) on all src/raddy/*.nim sources, then
# runs the full nimble test suite.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "==> verify: type-check desktop (--mm:orc)"
for f in src/raddy.nim; do
  echo "    nim check $f"
  nim check --mm:orc --hints:off --path:src "$f"
done

# When subdirectory modules land, this loop picks them up automatically.
for f in src/raddy/*.nim; do
  [[ -f "$f" ]] || continue
  echo "    nim check $f"
  nim check --mm:orc --hints:off --path:src "$f"
done

echo "==> verify: type-check vita (-d:vita --mm:arc)"
nim check --mm:arc --hints:off --path:src -d:vita src/raddy.nim

echo "==> verify: nimble test"
nimble test

echo "==> verify: OK"
