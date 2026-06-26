## verify_vita_switch.nim — Vita CI compile-and-link gate for the font-SWITCH path.
##
## Companion to vita_surface_check.nim, but for the multi-size font-switch surface
## added by the raddy-8an epic: setRaddyFont (core), RaddyFont/raddyMakeFont/
## raddyFontHandle (backend/font), raddyBundleCreate/raddyBundleSetFont
## (backend/ctx_bundle), and raddyFontLoaded (backend/raylib_api).
##
## Why this exists beyond `nimble check_vita`: check_vita only TYPE-CHECKS
## src/raddy.nim. This file forces Nim to CODEGEN (emit C for) the whole switch
## path under -d:vita --mm:arc — catching codegen-only breakage that type-checking
## misses (e.g. the raddyBundleCreate fixed-buffer alignment arithmetic, importc
## emission, when-defined(vita) branches in ctx_bundle).
##
## {.exportc.} prevents dead-code elimination so every referenced proc — and its
## transitive importc dependencies — must be emitted into the generated C, which
## then #includes raylib.h / nuklear.h and is syntax-checked against tests/stubs/.
##
## Compile (see scripts/verify.sh for the exact invocation):
##   nim c --compileOnly --mm:arc --hints:off --path:src -d:vita
##     --os:linux --cpu:amd64 --nimcache:/tmp/raddy_vita_switch_check
##     tests/stubs/verify_vita_switch.nim
##   # then gcc -std=c99 -fsyntax-only against the emitted ctx_bundle/font/raylib_api .c
##
## --os:linux --cpu:amd64: avoids arm-vita-eabi-gcc (not on CI) while still firing
##   every -d:vita Nim branch; nimbase.h's sizeof(NI)==sizeof(void*) assert passes
##   on the 64-bit host. Runtime correctness on real hardware is raddy-tzc.
##
## This is NOT a runnable test — it asserts nothing. It proves the switch surface
## generates valid C under the Vita configuration and pulls in no host-game symbols.

import raddy                       ## setRaddyFont (re-exported core), nk_context, types
import raddy/backend/raylib_api    ## RFont, raddyFontLoaded
import raddy/backend/font          ## RaddyFont, raddyMakeFont, raddyFontHandle
import raddy/backend/ctx_bundle    ## RaddyCtxBundle, raddyBundleCreate, raddyBundleSetFont

## vitaSwitchSurface: forces the entire font-switch path into the generated C.
## fontPtr is a caller-supplied stable RFont address (never dereferenced here).
proc vitaSwitchSurface*(ctx: ptr nk_context; fontPtr: ptr RFont) {.exportc.} =
  ## raddyFontLoaded — texture.id load-failure probe (raylib_api).
  if not raddyFontLoaded(fontPtr):
    return

  ## raddyMakeFont + raddyFontHandle + setRaddyFont — the core caller-owned switch.
  ## (Plain var: this proc is a codegen surface and never runs, so the RaddyFont
  ## stable-address lifetime contract is irrelevant here — see real callers.)
  var rf = raddyMakeFont(fontPtr, 16.0f)
  setRaddyFont(ctx, raddyFontHandle(rf))

  ## raddyBundleCreate + raddyBundleSetFont — the bundle switch helper. This also
  ## drags in the fixed-buffer alignment arithmetic (when-defined(vita) branch).
  let bundle = raddyBundleCreate(fontPtr, 16.0f)
  raddyBundleSetFont(bundle, rf)
