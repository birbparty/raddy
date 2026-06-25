## test_ctx_bundle.nim — bddy spec for src/raddy/backend/ctx_bundle.nim
##
## Tests the bundle's pinning invariants and nil-safety.
## Actual Nuklear draw calls require a display context — those are integration tests (raddy-bw1).
## We test: init succeeds with non-nil font ptr, fontOk reflects nil detection,
## nkFont fields wired correctly, ctx is usable (nk_window_begin would need display;
## we only verify the ptr is non-nil), per-frame helpers don't crash on degenerate state.

import bddy
import raddy/backend/raylib_api
import raddy/backend/ctx_bundle
import raddy/types  ## nk_user_font, nk_context
import raddy/backend/font  ## raddyMeasureWidth

# MeasureTextEx linker stub — ctx_bundle → font → measureTextEx (importc).
# None of our tests reach the actual callback; the nil/h guards short-circuit first.
# See test_font.nim for the reason we use {.emit.} rather than a Nim {.exportc.} stub.
{.emit: """
#include "raylib.h"
Vector2 MeasureTextEx(Font font, const char *text, float fontSize, float spacing) {
  (void)font; (void)text; (void)fontSize; (void)spacing;
  Vector2 v = {0.0f, 0.0f};
  return v;
}
""".}

spec "raddyBundleCreate":

  it "returns a non-nil bundle on nil fontPtr (graceful degradation)":
    var bundle = raddyBundleCreate(nil, 32.0f)
    verify:
      bundle != nil

  it "fontOk is false when fontPtr is nil":
    var bundle = raddyBundleCreate(nil, 32.0f)
    verify:
      bundle.fontOk == false

  it "fontOk is true when fontPtr is non-nil":
    var dummyFont: RFont
    var bundle = raddyBundleCreate(addr dummyFont, 32.0f)
    verify:
      bundle.fontOk == true

  it "nkFont.height matches fontPixelSize":
    var dummyFont: RFont
    var bundle = raddyBundleCreate(addr dummyFont, 24.0f)
    verify:
      bundle.nkFont.height == cfloat(24.0f)

  it "ctxOk is true after successful init":
    var dummyFont: RFont
    var bundle = raddyBundleCreate(addr dummyFont, 32.0f)
    verify:
      bundle.ctxOk == true

  it "nkFont.width is raddyMeasureWidth":
    var dummyFont: RFont
    var bundle = raddyBundleCreate(addr dummyFont, 32.0f)
    ## Comparing cdecl proc addresses: valid on current Nim/C backends (Nim emits a
    ## stable single symbol per {.cdecl.} proc). If this ever flakes across compilers,
    ## weaken to `bundle.nkFont.width != nil`.
    verify:
      bundle.nkFont.width == raddyMeasureWidth

  it "nkFont.userdata.ptr points to the provided fontPtr":
    var dummyFont: RFont
    var bundle = raddyBundleCreate(addr dummyFont, 32.0f)
    verify:
      bundle.nkFont.userdata.`ptr` == cast[pointer](addr dummyFont)

spec "raddyBundleCtx":

  it "returns non-nil ctx pointer":
    var dummyFont: RFont
    var bundle = raddyBundleCreate(addr dummyFont, 32.0f)
    let ctxPtr = raddyBundleCtx(bundle)
    verify:
      ctxPtr != nil

  it "ctx pointer points into the bundle (stable ref address)":
    var dummyFont: RFont
    var bundle = raddyBundleCreate(addr dummyFont, 32.0f)
    let ctxPtr = raddyBundleCtx(bundle)
    ## The ctx ptr must equal the address of bundle.ctx — the ref's interior is stable.
    verify:
      ctxPtr == addr bundle.ctx

spec "raddyBundleClear":

  it "clears without overflow on fresh init (no commands pushed)":
    var dummyFont: RFont
    var bundle = raddyBundleCreate(addr dummyFont, 32.0f)
    var overflow = true
    raddyBundleClear(bundle, overflow)
    verify:
      overflow == false

spec "raddyBundleFree":

  it "is safe to call with nil bundle":
    var bundle: RaddyCtxBundle = nil
    raddyBundleFree(bundle)
    verify:
      true  ## reached without crash

  it "frees a live bundle without crash":
    var dummyFont: RFont
    var bundle = raddyBundleCreate(addr dummyFont, 32.0f)
    raddyBundleFree(bundle)
    verify:
      true  ## reached without crash

  it "is idempotent — double free does not crash":
    var dummyFont: RFont
    var bundle = raddyBundleCreate(addr dummyFont, 32.0f)
    raddyBundleFree(bundle)
    raddyBundleFree(bundle)  ## second call must be a no-op (freed sentinel)
    verify:
      true  ## reached without crash

when defined(raddyFixed):
  spec "raddyBundleCreate (raddyFixed path — embedded cmdBuf)":

    it "initialises on the fixed-buffer path and returns non-nil bundle":
      var dummyFont: RFont
      var bundle = raddyBundleCreate(addr dummyFont, 32.0f)
      verify:
        bundle != nil
        bundle.ctxOk == true

    it "clears without overflow on fresh init (no commands pushed)":
      var dummyFont: RFont
      var bundle = raddyBundleCreate(addr dummyFont, 32.0f)
      var overflow = true
      raddyBundleClear(bundle, overflow)
      verify:
        overflow == false
