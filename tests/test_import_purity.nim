## test_import_purity.nim — Core module import purity gate.
##
## Verifies that core modules (src/raddy/*.nim, excluding backend/) contain
## no Nim-level imports of naylib, raylib_console, inputty, or any backend
## submodule. Fails the test suite (runtime) if a violation is found.
##
## "Core" means the 8 modules that `import raddy` re-exports. Backend modules
## under src/raddy/backend/ are explicitly excluded — they may use platform FFI.
##
## Forbidden patterns (Nim module import level only; {.importc.} is fine):
##   import naylib
##   import raylib_console
##   import inputty
##   import ./backend/...
##   import raddy/backend/...
##   from naylib import ...
##   from raylib_console import ...
##   from inputty import ...

import bddy
import std/os
import std/strutils

const repoRoot = currentSourcePath().parentDir().parentDir()

const coreModules = [
  "src/raddy/types.nim",
  "src/raddy/errors.nim",
  "src/raddy/context.nim",
  "src/raddy/style.nim",
  "src/raddy/input.nim",
  "src/raddy/layout.nim",
  "src/raddy/widgets.nim",
  "src/raddy/vendor.nim",
]

## Forbidden prefix + keyword pairs. A line is a violation when it begins
## with "import" or "from" AND contains one of these keywords.
const forbidden = [
  "naylib",
  "raylib_console",
  "inputty",
  "./backend",
  "raddy/backend",
]

proc firstViolation(content, keyword: string): string =
  ## Returns the first import/from line containing `keyword`, or "".
  for line in content.splitLines():
    let stripped = line.strip()
    if (stripped.startsWith("import") or stripped.startsWith("from")) and
       keyword in stripped:
      return stripped
  return ""

spec "core module import purity":

  for module in coreModules:
    let content = readFile(repoRoot / module)
    let name = module.splitPath().tail

    it name & " does not import naylib":
      verify:
        firstViolation(content, "naylib") == ""

    it name & " does not import raylib_console":
      verify:
        firstViolation(content, "raylib_console") == ""

    it name & " does not import inputty":
      verify:
        firstViolation(content, "inputty") == ""

    it name & " does not import backend modules":
      let backendViaBuild = firstViolation(content, "./backend")
      let backendViaPath  = firstViolation(content, "raddy/backend")
      verify:
        backendViaBuild == ""
        backendViaPath  == ""
