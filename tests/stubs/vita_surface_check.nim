## vita_surface_check.nim — Vita CI compile gate (types/stubs check only).
##
## Forces Nim to emit raddyRender and raddyMeasureWidth so that the generated C
## includes every importc draw proc from raylib_api.nim and font.nim.
##
## {.exportc.} prevents dead-code elimination: Nim must emit the proc body and
## all transitive importc dependencies to satisfy the C export. This causes the
## generated C to contain #include "raylib.h", which the C compiler then parses
## against tests/stubs/raylib.h.
##
## Compile with (see scripts/verify.sh for the exact invocation):
##   nim c --compileOnly --mm:arc --hints:off --path:src -d:vita
##     --os:linux --cpu:amd64 --nimcache:/tmp/raddy_vita_surface_check
##     tests/stubs/vita_surface_check.nim
##   # then: gcc -std=c99 -fsyntax-only -Itests/stubs ... /tmp/.../@praddy@s*.nim.c
##
## --os:linux --cpu:amd64: avoids arm-vita-eabi-gcc (not on CI); nimbase.h's
##   sizeof(NI)==sizeof(void*) static assert passes on 64-bit host gcc.
##   All -d:vita Nim conditional branches still fire normally.
##
## This is NOT a test — it does not run, it does not assert anything. Its
## sole purpose is to prove the vita draw/measure surface resolves against the
## stub header at the C level. Runtime correctness is verified by raddy-tzc.

import raddy/types
import raddy/backend/render
import raddy/backend/font

## vitaRenderSurface: exported to C so Nim cannot DCE it.
## The export name is in the stub to ensure the symbol resolves cleanly.
proc vitaRenderSurface*(ctx: ptr nk_context; framebufferH: int32;
                         overflow: var bool) {.exportc.} =
  ## Forces raddyRender — and all importc procs it transitively calls — to be
  ## emitted into the generated C.
  raddyRender(ctx, framebufferH, overflow)

## vitaMeasureSurface: forces font.nim's MeasureTextEx importc to be emitted.
proc vitaMeasureSurface*(handle: nk_handle; h: float32;
                          text: cstring; len: cint): float32 {.exportc.} =
  raddyMeasureWidth(handle, h, text, len)
