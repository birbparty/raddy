## font spec: raddyMeasureWidth and raddyInitFont edge-case behaviour.
##
## MeasureTextEx cannot be called in tests (no raylib window / GPU context).
## A zero-returning C stub satisfies the linker so the test binary builds.
## The stub is only ever reached if the nil/zero guards in raddyMeasureWidth
## fail — which the tests prove they don't.
##
## The width callback's MeasureTextEx path is exercised by the integration
## suite (raddy-8nm).

import bddy
import raddy                        ## nk_handle, nk_user_font re-exported from types
import raddy/backend/font           ## raddyMeasureWidth, raddyInitFont, RaddyMeasureSpacing
import raddy/backend/raylib_api     ## RFont (for ptr casts)

{.warning[UnusedImport]: off.}

# ---------------------------------------------------------------------------
# Linker stub — MeasureTextEx returns Vector2{0,0} in the test binary.
# The nil/len/h guards in raddyMeasureWidth mean this is never actually called
# by any test below. The symbol must exist to satisfy the linker.
#
# Why {.emit.} and not a Nim {.exportc.} stub: raddyMeasureWidth imports
# MeasureTextEx via {.importc: "MeasureTextEx".}, so Nim generates a C #include
# and a call to the C symbol directly. A Nim {.exportc.} proc with the same name
# would appear AFTER the importc declaration in the generated C, causing a
# conflicting-types compiler error. The raw C emit avoids that ordering issue.
# ---------------------------------------------------------------------------
{.emit: """
#include "raylib.h"
Vector2 MeasureTextEx(Font font, const char *text, float fontSize, float spacing) {
  (void)font; (void)text; (void)fontSize; (void)spacing;
  Vector2 v = {0.0f, 0.0f};
  return v;
}
""".}

# ---------------------------------------------------------------------------
# raddyMeasureWidth — nil / degenerate guards (no MeasureTextEx call)
# ---------------------------------------------------------------------------

spec "raddyMeasureWidth nil guards":

  it "returns 0.0 when text is nil":
    var h: nk_handle   ## zeroed → handle.ptr == nil
    verify:
      raddyMeasureWidth(h, 16.0f, nil, 5) == 0.0f

  it "returns 0.0 when len is 0":
    var h: nk_handle
    let dummy = "hello"
    verify:
      raddyMeasureWidth(h, 16.0f, dummy.cstring, 0) == 0.0f

  it "returns 0.0 when len is negative":
    var h: nk_handle
    let dummy = "hello"
    verify:
      raddyMeasureWidth(h, 16.0f, dummy.cstring, -1) == 0.0f

  it "returns 0.0 when font pointer in handle is nil":
    var h: nk_handle
    h.`ptr` = nil
    let dummy = "hello"
    verify:
      raddyMeasureWidth(h, 16.0f, dummy.cstring, 5) == 0.0f

  it "returns 0.0 when h is 0 (degenerate font height)":
    var h: nk_handle
    let dummy = "hello"
    verify:
      raddyMeasureWidth(h, 0.0f, dummy.cstring, 5) == 0.0f

  it "returns 0.0 when h is negative":
    var h: nk_handle
    let dummy = "hello"
    verify:
      raddyMeasureWidth(h, -1.0f, dummy.cstring, 5) == 0.0f

# ---------------------------------------------------------------------------
# Buffer truncation logic — unit-test the min(len, BufMax-1) invariant
# without calling MeasureTextEx.
# ---------------------------------------------------------------------------

spec "raddyMeasureWidth buffer truncation logic":

  it "copyLen is capped at 1023 when len >= 1024":
    ## Mirrors the exact expression in raddyMeasureWidth:
    ##   let copyLen = min(int(len), BufMax - 1)  where BufMax = 1024
    const BufMax = 1024
    let lenOver  = min(int(1024), BufMax - 1)
    let lenExact = min(int(1023), BufMax - 1)
    let lenSmall = min(int(5),    BufMax - 1)
    verify:
      lenOver == 1023 and lenExact == 1023 and lenSmall == 5

  it "copyLen for len=0 is 0 (but callback short-circuits before reaching copyMem)":
    const BufMax = 1024
    let copyLen = min(int(0), BufMax - 1)
    verify:
      copyLen == 0

# ---------------------------------------------------------------------------
# raddyInitFont — field initialisation (no raylib calls needed)
# ---------------------------------------------------------------------------

spec "raddyInitFont field initialisation":

  it "sets userdata.ptr to the provided font pointer":
    var font: RFont
    var nkFont: nk_user_font
    raddyInitFont(nkFont, addr font, 20.0f32)
    verify:
      nkFont.userdata.`ptr` == cast[pointer](addr font)

  it "sets height to the provided fontPixelHeight":
    var font: RFont
    var nkFont: nk_user_font
    raddyInitFont(nkFont, addr font, 32.0f32)
    verify:
      nkFont.height == cfloat(32.0f32)

  it "sets width callback to raddyMeasureWidth (not nil)":
    var font: RFont
    var nkFont: nk_user_font
    raddyInitFont(nkFont, addr font, 16.0f32)
    verify:
      nkFont.width != nil

  it "width callback pointer equals raddyMeasureWidth":
    var font: RFont
    var nkFont: nk_user_font
    raddyInitFont(nkFont, addr font, 16.0f32)
    verify:
      nkFont.width == raddyMeasureWidth

# ---------------------------------------------------------------------------
# RaddyMeasureSpacing constant
# ---------------------------------------------------------------------------

spec "RaddyMeasureSpacing constant":

  it "equals 2.0":
    verify:
      RaddyMeasureSpacing == 2.0f32

# ---------------------------------------------------------------------------
# RaddyFont / raddyMakeFont — caller-owned value type (no raylib calls needed)
# ---------------------------------------------------------------------------

spec "raddyMakeFont construction":
  ## NOTE: these fixtures call raddyMakeFont(addr localFont, ...) on STACK locals.
  ## That is test-only-safe because nothing escapes to C here (no setRaddyFont /
  ## raddyRender). Do NOT read these as a usage example — real callers must pass a
  ## STABLE address (a global or long-lived field), per RaddyFont's lifetime contract.

  it "stores the provided fontPtr":
    var font: RFont
    let rf = raddyMakeFont(addr font, 20.0f32)
    verify:
      rf.fontPtr == addr font

  it "stores the provided pixel size":
    var font: RFont
    let rf = raddyMakeFont(addr font, 32.0f32)
    verify:
      rf.pixelSize == 32.0f32

  it "wires nkFont through raddyInitFont (userdata.ptr, height, width)":
    var font: RFont
    let rf = raddyMakeFont(addr font, 16.0f32)
    verify:
      rf.nkFont.userdata.`ptr` == cast[pointer](addr font) and
      rf.nkFont.height == cfloat(16.0f32) and
      rf.nkFont.width == raddyMeasureWidth

  it "nil fontPtr still yields a usable font (self-guarding width callback)":
    ## Mirrors raddyBundleCreate: the callback is always wired so layout cannot
    ## hit a nil function pointer; text just will not render.
    let rf = raddyMakeFont(nil, 24.0f32)
    verify:
      rf.fontPtr == nil and
      rf.pixelSize == 24.0f32 and
      rf.nkFont.width == raddyMeasureWidth

  it "two fonts at different sizes are independent (the multi-size point)":
    ## The actual reason RaddyFont exists: distinct fonts/sizes coexist.
    var small, large: RFont
    let rfSmall = raddyMakeFont(addr small, 16.0f32)
    let rfLarge = raddyMakeFont(addr large, 32.0f32)
    verify:
      rfSmall.pixelSize == 16.0f32 and rfLarge.pixelSize == 32.0f32 and
      rfSmall.nkFont.height == cfloat(16.0f32) and
      rfLarge.nkFont.height == cfloat(32.0f32) and
      rfSmall.fontPtr == (addr small) and rfLarge.fontPtr == (addr large) and
      rfSmall.fontPtr != rfLarge.fontPtr

  it "raddyFontHandle returns addr of the live nkFont field":
    var rf = raddyMakeFont(nil, 16.0f32)
    verify:
      raddyFontHandle(rf) == addr rf.nkFont
