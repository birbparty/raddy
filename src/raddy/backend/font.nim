## font.nim — nk_user_font setup and raddyMeasureWidth cdecl callback.
##
## Does NOT pin the Font — lifetime is the caller's responsibility.
## The callback retrieves the font via handle.ptr (cast to ptr RFont).
##
## Critical constraints:
##   - Width callback MUST NOT allocate, raise, or call raddyLog.
##   - Nuklear passes a NON-null-terminated char* + len; we copy to a stack
##     buffer, null-terminate, then call MeasureTextEx.
##   - spacing = RaddyMeasureSpacing (2.0) — MUST match DrawTextEx spacing
##     used in render.nim.
##   - nk_user_font.userdata.ptr holds a raw ptr RFont set by the CALLER.
##     font.nim does NOT own or pin the font.

import ../types        ## nk_handle, nk_user_font, nk_text_width_f
import ./raylib_api    ## RFont, RVec2

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const RaddyMeasureSpacing* = 2.0f32
  ## Text spacing passed to MeasureTextEx and DrawTextEx. Both must use the
  ## same value or glyph positions will not match layout measurements.

# ---------------------------------------------------------------------------
# C import: MeasureTextEx
# ---------------------------------------------------------------------------

proc measureTextEx(font: RFont; text: cstring; fontSize, spacing: float32): RVec2
    {.importc: "MeasureTextEx", header: "raylib.h", sideEffect.}
  ## Returns Vector2 { x = pixel width, y = pixel height }.

# ---------------------------------------------------------------------------
# Width callback — registered as nk_user_font.width
# ---------------------------------------------------------------------------

proc raddyMeasureWidth*(handle: nk_handle; h: cfloat; text: cstring; len: cint): cfloat
    {.cdecl, gcsafe, raises: [].} =
  ## Called by Nuklear to measure text width.
  ## Input: NON-null-terminated char* of byte length `len`.
  ## Must not raise, allocate, or call raddyLog (cdecl callback rule).
  if text == nil or len <= 0: return 0.0f32
  let fontPtr = cast[ptr RFont](handle.`ptr`)
  if fontPtr == nil: return 0.0f32
  const BufMax = 1024
  var buf: array[BufMax, char]
  let copyLen = min(int(len), BufMax - 1)
  copyMem(addr buf[0], text, copyLen)
  buf[copyLen] = '\0'
  let measured = measureTextEx(fontPtr[], cast[cstring](addr buf[0]), float32(h), RaddyMeasureSpacing)
  return cfloat(measured.x)

# ---------------------------------------------------------------------------
# Font setup proc
# ---------------------------------------------------------------------------

proc raddyInitFont*(nkFont: var nk_user_font; fontPtr: ptr RFont;
                    fontPixelHeight: float32) {.raises: [].} =
  ## Initialize an nk_user_font from a pre-loaded raylib Font (via fontPtr).
  ##
  ## fontPtr must point to a pinned RFont with lifetime >= the nk_context.
  ## The caller is responsible for verifying the font loaded successfully
  ## (e.g., font.texture.id != 0) before calling this proc — font.nim has
  ## only a partial view of RFont and cannot access its texture field.
  ##
  ## fontPixelHeight: pixel size the font was loaded at (e.g., font.baseSize).
  nkFont.userdata.`ptr` = cast[pointer](fontPtr)
  nkFont.height = cfloat(fontPixelHeight)
  nkFont.width  = raddyMeasureWidth
