## test_import_purity.nim — Core module import purity gate.
##
## Verifies that core modules (src/raddy/*.nim, excluding backend/) contain
## no Nim-level imports of naylib, raylib_console, inputty, or any backend
## submodule. Fails the test suite (runtime) if a violation is found.
##
## "Core" means the 8 modules that `import raddy` re-exports. Backend modules
## under src/raddy/backend/ are explicitly excluded — they may use platform FFI.
##
## Forbidden at the Nim module import level ({.importc.} is fine):
##   import/include naylib
##   import/include raylib_console
##   import/include inputty
##   import/include ./backend/...
##   import/include raddy/backend/...
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

## Each entry is (display-label, keyword). keyword is matched as an exact
## module name OR a path prefix (when it starts with "./" or contains "/").
## Adding a new forbidden module here automatically extends all 8-module checks.
const forbidden = [
  ("naylib",            "naylib"),
  ("raylib_console",    "raylib_console"),
  ("inputty",           "inputty"),
  ("./backend/...",     "./backend"),
  ("raddy/backend/...", "raddy/backend"),
]

proc stripTrailingComment(line: string): string =
  ## Remove everything from the first unquoted `#` onward.
  var inStr = false
  for i, c in line:
    if c == '"': inStr = not inStr
    elif not inStr and c == '#': return line[0..<i]
  line

proc importedModules(line: string): seq[string] =
  ## Return the module names referenced by a single import/include/from line.
  ## Handles: `import a, b/c`, `include a`, `from a import x`.
  ## Call after stripping the trailing comment.
  let s = line.strip()
  if s.startsWith("from "):
    # from MODULE import SYMBOLS — only the module name matters for purity
    let rest = s[5..^1]
    let idx = rest.find(" import ")
    if idx >= 0: return @[rest[0..<idx].strip()]
  elif s.startsWith("import ") or s.startsWith("include "):
    let rest = if s.startsWith("import "): s[7..^1] else: s[8..^1]
    for tok in rest.split(','):
      let t = tok.strip()
      if t.len > 0: result.add(t)

proc isMatch(module, keyword: string): bool =
  ## True when the imported module `module` matches the forbidden `keyword`.
  ## Path patterns (containing "/" or starting with "./") match as a prefix;
  ## bare names require an exact match so "inputty_helpers" != "inputty".
  if keyword.startsWith("./") or "/" in keyword:
    module == keyword or module.startsWith(keyword & "/")
  else:
    module == keyword

proc firstViolation(content, keyword: string): string =
  ## Return the first import/from/include line in `content` that imports a
  ## module matching `keyword`, or "" if none found.
  for rawLine in content.splitLines():
    let line = stripTrailingComment(rawLine).strip()
    if line.len == 0: continue
    let isImportLike = line.startsWith("import ") or line.startsWith("include ")
    let isFrom = line.startsWith("from ")
    if not (isImportLike or isFrom): continue
    for m in importedModules(line):
      if isMatch(m, keyword):
        return line
  return ""

spec "core module import purity":
  for module in coreModules:
    let content = readFile(repoRoot / module)
    let name = module.splitPath().tail
    for (label, kw) in forbidden:
      it name & " does not import " & label:
        verify:
          firstViolation(content, kw) == ""
