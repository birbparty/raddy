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
  for f in listFiles("tests"):
    if f.endsWith(".nim") and f.contains("/test_"):
      exec "nim c --mm:orc --hints:off --path:src -r " & f

task check, "Type-check library entry point":
  exec "nim check --mm:orc --hints:off --path:src src/raddy.nim"

task check_vita, "Type-check for PS Vita (-d:vita)":
  exec "nim check --mm:arc --hints:off --path:src -d:vita src/raddy.nim"
