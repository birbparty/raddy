# Package

version     = "0.1.0"
author      = "Matt Spurlin"
description = "Nuklear immediate-mode GUI binding for naylib/raylib — desktop + PS Vita"
license     = "MIT"
srcDir      = "src"
skipDirs    = @["tests", "examples", "docs"]

# Dependencies

requires "nim >= 2.0.0"

# Build with 'nim c' directly — 'nimble build' flattens srcDir and breaks
# submodule-relative imports in src/raddy/*.nim (same pitfall as clckr/baggie).

task test, "Run the test suite":
  let home = getEnv("HOME")
  let (bddyRaw, bddyCode) = gorgeEx(
    "find " & home & "/.nimble/pkgs2 -maxdepth 1 -name 'bddy-*' -type d")
  let bddyDirs = bddyRaw.strip().splitLines()
  if bddyCode != 0 or bddyDirs.len == 0 or bddyDirs[0].len == 0:
    quit "raddy test: bddy not found in ~/.nimble/pkgs2 — run: nimble install bddy"
  if bddyDirs.len > 1:
    echo "raddy test: WARNING multiple bddy-* dirs found, using " & bddyDirs[0]
  let bddyDir = bddyDirs[0]
  # Find naylib's raylib/ directory for backend tests that need raylib.h.
  let (naylibRaw, _) = gorgeEx(
    "find " & home & "/.nimble/pkgs2 -maxdepth 1 -name 'naylib-*' -type d")
  let naylibDirs = naylibRaw.strip().splitLines()
  let naylibPassC = if naylibDirs.len > 0 and naylibDirs[0].len > 0:
    " --passC:\"-I" & naylibDirs[0] & "/raylib\""
  else:
    ""
  let flags = "--mm:orc --hints:off --path:src --path:" & bddyDir & naylibPassC
  # Tests live flat in tests/ (no subdirectories); listFiles is non-recursive by design.
  for f in listFiles("tests"):
    if f.endsWith(".nim") and f.contains("test_"):
      exec "nim c " & flags & " -r " & f

task check, "Type-check library entry point":
  exec "nim check --mm:orc --hints:off --path:src src/raddy.nim"

task check_vita, "Type-check for PS Vita (-d:vita)":
  exec "nim check --mm:arc --hints:off --path:src -d:vita src/raddy.nim"
