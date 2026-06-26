## font.nim — nk_user_font setup and raddyMeasureWidth cdecl callback.
##
## Does NOT pin the Font — lifetime is the caller's responsibility.
## The callback retrieves the font via handle.ptr (cast to ptr RFont).
##
## Critical constraints:
##   - Width callback MUST NOT allocate, raise, or call raddyLog.
##   - Nuklear passes a NON-null-terminated char* + len; we copy to a stack
##     buffer, null-terminate, then call MeasureTextEx.
##   - spacing = RaddyMeasureSpacing (2.0) — MUST match the spacing literal
##     passed to rDrawTextEx in render.nim. When render.nim exists, import
##     this constant from font.nim rather than duplicating 2.0f.
##   - nk_user_font.userdata.ptr holds a raw ptr RFont set by the CALLER.
##     font.nim does NOT own or pin the font.

import ../types        ## nk_handle, nk_user_font, nk_text_width_f
import ./raylib_api    ## RFont, RVec2

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const RaddyMeasureSpacing* = 2.0f32
  ## Text spacing passed to MeasureTextEx and rDrawTextEx. Both must use the
  ## same value or glyph positions will not match layout measurements.
  ## render.nim must import and pass this constant — do not duplicate the literal.

const RaddyMaxTextBytes* = 1024
  ## Shared stack-buffer size for NK text payloads. Used by both raddyMeasureWidth
  ## (font.nim) and the NK_COMMAND_TEXT handler (render.nim) so that the measure and
  ## draw paths always agree on the truncation point. Do not duplicate the 1024
  ## literal in either file — change it here if a larger cap is ever needed.

# ---------------------------------------------------------------------------
# C import: MeasureTextEx
# ---------------------------------------------------------------------------

## RFont is a partial importc view (raylib_api.nim declares only the Nim-facing
## handle fields). However, passing RFont by value to an importc proc is safe
## because the C compiler sees the full Font layout via raylib.h at the call
## site — Nim defers to C for the struct's size and copy semantics when both
## sides are importc-typed. The "do NOT copy/move from Nim" rule in raylib_api.nim
## refers to Nim-level operations (sizeof, ARC hooks, Nim-managed arrays) — not
## importc-to-importc calls where C owns the layout throughout.
proc measureTextEx(font: RFont; text: cstring; fontSize, spacing: float32): RVec2
    {.importc: "MeasureTextEx", header: "raylib.h", sideEffect.}

# ---------------------------------------------------------------------------
# Width callback — registered as nk_user_font.width
# ---------------------------------------------------------------------------

proc raddyMeasureWidth*(handle: nk_handle; h: float32; text: cstring; len: cint): float32
    {.cdecl, gcsafe, raises: [].} =
  ## Called by Nuklear to measure text width.
  ## Signature matches nk_text_width_f exactly (float32, not cfloat) so the
  ## assignment nkFont.width = raddyMeasureWidth is provably, not coincidentally,
  ## type-compatible.
  ## Input: NON-null-terminated char* of byte length `len`.
  ## Must not raise, allocate, or call raddyLog (cdecl callback rule).
  if text == nil or len <= 0: return 0.0f32
  ## Guard against degenerate or NaN font height (h != h is the canonical NaN test).
  ## NaN propagated into Nuklear layout arithmetic causes downstream Defects across
  ## the FFI boundary, which surfaces as undefined behavior.
  if h <= 0.0f32 or h != h: return 0.0f32
  let fontPtr = cast[ptr RFont](handle.`ptr`)
  if fontPtr == nil: return 0.0f32
  var buf: array[RaddyMaxTextBytes, char]
  let copyLen = min(int(len), RaddyMaxTextBytes - 1)
  copyMem(addr buf[0], text, copyLen)
  buf[copyLen] = '\0'
  let measured = measureTextEx(fontPtr[], cast[cstring](addr buf[0]), h, RaddyMeasureSpacing)
  return measured.x

# ---------------------------------------------------------------------------
# Font setup proc
# ---------------------------------------------------------------------------

proc raddyInitFont*(nkFont: var nk_user_font; fontPtr: ptr RFont;
                    fontPixelHeight: float32) {.raises: [].} =
  ## Initialize an nk_user_font from a pre-loaded raylib Font (via fontPtr).
  ##
  ## fontPtr must point to a pinned RFont with lifetime >= the nk_context.
  ## The caller is responsible for verifying the font loaded successfully
  ## (use raddyFontLoaded(fontPtr) from raylib_api.nim) before calling this proc;
  ## font.nim deliberately stays agnostic of Font's texture layout.
  ##
  ## fontPixelHeight: pixel size the font was loaded at (e.g., font.baseSize).
  nkFont.userdata.`ptr` = cast[pointer](fontPtr)
  nkFont.height = cfloat(fontPixelHeight)
  nkFont.width  = raddyMeasureWidth

# ---------------------------------------------------------------------------
# RaddyFont — caller-owned value type for multi-size / font-switching use
# ---------------------------------------------------------------------------

type RaddyFont* = object
  ## A caller-owned font handle pairing a Nuklear nk_user_font with the pinned
  ## RFont it measures and the pixel size it was built at. This is the value the
  ## caller switches to via `setRaddyFont(ctx, addr myFont.nkFont)` to render at a
  ## given size; build several (one per size) to support multi-size UIs.
  ##
  ## LIFETIME CONTRACT (two pointers escape into C, both caller-owned):
  ##   1. `fontPtr` — Nuklear stores it in nkFont.userdata.ptr and the width
  ##      callback dereferences it during text layout. The RFont it points at MUST
  ##      outlive every frame this font is active. `fontPtr` must be a STABLE
  ##      address (a module global or a long-lived field), never `addr` of a local
  ##      or a seq element that may move.
  ##   2. `addr self.nkFont` — `setRaddyFont`/`nk_style_set_font` does
  ##      `style.font = &nkFont` with NO copy, and raddyRender dereferences that
  ##      pointer during the command walk. So the RaddyFont VALUE itself must stay
  ##      alive AT A STABLE ADDRESS from the moment it is set until AFTER
  ##      raddyRender consumes that frame's command queue. Because RaddyFont is a
  ##      value type, a copy/move relocates nkFont — store it once (global or
  ##      long-lived field) and do not move it while it is the active font.
  ##
  ## Canonical usage (font + RaddyFont both at stable {.global.} addresses):
  ##   var smallRf {.global.} = raddyMakeFont(addr smallFont, 16.0f)
  ##   # per frame, inside nk_begin/nk_end:
  ##   setRaddyFont(ctx, raddyFontHandle(smallRf))   ## then emit widgets
  nkFont*:    nk_user_font  ## the Nuklear font handle (width callback + raw fontPtr)
  fontPtr*:   ptr RFont     ## borrowed raw ptr to the caller-owned RFont (stable)
  pixelSize*: float32       ## pixel height the font was built at (e.g., font.baseSize)

proc raddyMakeFont*(fontPtr: ptr RFont; pixelSize: float32): RaddyFont
    {.raises: [], gcsafe.} =
  ## Build a RaddyFont from a pre-loaded, pinned RFont and its pixel size.
  ##
  ## fontPtr: stable address of a caller-owned RFont (see RaddyFont lifetime
  ##   contract). The caller is responsible for verifying the font loaded
  ##   successfully (use raddyFontLoaded(fontPtr) from raylib_api.nim) before
  ##   calling — font.nim deliberately stays agnostic of Font's texture layout.
  ## pixelSize: pixel height the font was loaded at; used as nk_user_font.height.
  ##
  ## A nil `fontPtr` still produces a usable RaddyFont: raddyInitFont wires the
  ## self-guarding width callback (raddyMeasureWidth returns 0 for a nil handle),
  ## so layout will not crash — text simply will not render. This mirrors
  ## raddyBundleCreate's always-init-the-callback behaviour.
  ##
  ## Returns BY VALUE. Assign the result into stable storage before taking
  ## `addr result.nkFont` (or calling raddyFontHandle) for setRaddyFont — a copy
  ## relocates the nk_user_font.
  result.fontPtr = fontPtr
  result.pixelSize = pixelSize
  raddyInitFont(result.nkFont, fontPtr, pixelSize)

proc raddyFontHandle*(font: var RaddyFont): ptr nk_user_font {.inline, raises: [].} =
  ## The single sanctioned way to obtain the `ptr nk_user_font` to pass to
  ## `setRaddyFont`/`raddyBundleSetFont`. Centralizing `addr font.nkFont` here keeps
  ## the lifetime-sensitive address-taking in one documented place.
  ##
  ## Takes `var RaddyFont` so the argument must be a mutable, addressable location
  ## — which nudges callers toward stable storage (a global or long-lived field)
  ## rather than a temporary. The returned pointer is only valid while `font` lives
  ## at this address and is not moved/copied (see RaddyFont's lifetime contract).
  addr font.nkFont
