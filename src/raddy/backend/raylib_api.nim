## raylib_api.nim — Platform seam between raddy's renderer and the host draw API.
##
## Provides raddy-local type aliases and normalized draw procs. render.nim and
## font.nim call ONLY these r* procs — never raw naylib or console names.
##
## Both desktop and vita bind the underlying raylib C API via {.importc.}. This
## avoids a hard dep on either naylib or raylib_console as Nim module paths.
## The host game's build (naylib on desktop, vita console SDK on Vita) provides
## raylib.h on the C include path.
##
## NOTE on rlRectangle: naylib's raylib.h renames Rectangle→rlRectangle to avoid
## the Win32 DrawText/RECT namespace collision. RRect is bound to rlRectangle here.
## The vita console port may use the original Rectangle name — verify in raddy-5ce
## and guard with `when defined(vita): {.importc: "Rectangle".}` if needed.
##
## Decoupled-core exception: backend/ is allowed to reference platform types.
## All other src/raddy/ modules MUST NOT import this file.

const raylibH = "raylib.h"

# ---------------------------------------------------------------------------
# Raddy-local type aliases
# These map to the corresponding raylib C structs by importc name.
# Nim generates `obj.field` accesses in C — field names must match the C struct.
# For RColor/RVec2/RRect: full layout bound (completeStruct for correct sizeof).
# For RFont/RTexture: PARTIAL VIEW — do NOT sizeof, copy, or move from Nim.
# ---------------------------------------------------------------------------

type
  RColor* {.importc: "Color", header: raylibH, completeStruct.} = object
    r*, g*, b*, a*: uint8

  RVec2* {.importc: "Vector2", header: raylibH, completeStruct.} = object
    x*, y*: float32

  RRect* {.importc: "rlRectangle", header: raylibH, completeStruct.} = object
    x*, y*, width*, height*: float32

  RFont* {.importc: "Font", header: raylibH.} = object
    ## PARTIAL VIEW. rlDrawTextEx receives Font by value (C ABI: stack copy).
    ## Nuklear stores only a pointer to the underlying font data — raddy's
    ## font.nim owns the RFont and must outlive the nk_context.

  RTexture* {.importc: "Texture2D", header: raylibH.} = object
    ## PARTIAL VIEW. Only id/width/height are accessed by raddy.
    id*:      uint32
    width*:   int32
    height*:  int32
    mipmaps*: int32
    format*:  int32

# ---------------------------------------------------------------------------
# Filled and outlined geometry
# All proc names match raylib C API exactly (case-sensitive).
# ---------------------------------------------------------------------------

proc rDrawRectangleRec*(rect: RRect; color: RColor)
    {.importc: "DrawRectangleRec", header: raylibH, sideEffect.}

proc rDrawRectangleLinesEx*(rect: RRect; thick: float32; color: RColor)
    {.importc: "DrawRectangleLinesEx", header: raylibH, sideEffect.}

proc rDrawRectangleRounded*(rect: RRect; roundness: float32; segs: int32; color: RColor)
    {.importc: "DrawRectangleRounded", header: raylibH, sideEffect.}

## DrawRectangleRoundedLinesEx (with thickness) — verify presence on vita (raddy-5ce).
proc rDrawRectangleRoundedLinesEx*(rect: RRect; roundness: float32; segs: int32; thick: float32; color: RColor)
    {.importc: "DrawRectangleRoundedLinesEx", header: raylibH, sideEffect.}

proc rDrawRectangleGradientEx*(rect: RRect; topLeft, bottomLeft, bottomRight, topRight: RColor)
    {.importc: "DrawRectangleGradientEx", header: raylibH, sideEffect.}
  ## C parameter order: topLeft, bottomLeft, bottomRight, topRight (CCW quad winding).
  ## Vita: may be absent — verify in raddy-5ce; no-op + log once if missing.

proc rDrawLineEx*(start, `end`: RVec2; thick: float32; color: RColor)
    {.importc: "DrawLineEx", header: raylibH, sideEffect.}

## DrawLineStrip: verify vita presence in raddy-5ce. `pts` is the first element
## of a contiguous RVec2 array. The caller must ensure lifetime >= the call.
proc rDrawLineStrip*(pts: ptr RVec2; count: int32; color: RColor)
    {.importc: "DrawLineStrip", header: raylibH, sideEffect.}

proc rDrawTriangle*(v1, v2, v3: RVec2; color: RColor)
    {.importc: "DrawTriangle", header: raylibH, sideEffect.}
  ## CCW winding (counter-clockwise). NK_COMMAND_TRIANGLE winding: verify in
  ## command-matrix.md — may need CW→CCW flip if Nuklear emits CW.

proc rDrawTriangleLines*(v1, v2, v3: RVec2; color: RColor)
    {.importc: "DrawTriangleLines", header: raylibH, sideEffect.}
  ## CCW winding.

proc rDrawRing*(center: RVec2; innerR, outerR, startDeg, endDeg: float32; segs: int32; color: RColor)
    {.importc: "DrawRing", header: raylibH, sideEffect.}
  ## Vita: verify presence in raddy-5ce.

proc rDrawCircleSector*(center: RVec2; radius, startDeg, endDeg: float32; segs: int32; color: RColor)
    {.importc: "DrawCircleSector", header: raylibH, sideEffect.}

when not defined(vita):
  proc rDrawEllipse*(cx, cy: int32; rx, ry: float32; color: RColor)
      {.importc: "DrawEllipse", header: raylibH, sideEffect.}

  proc rDrawEllipseLines*(cx, cy: int32; rx, ry: float32; color: RColor)
      {.importc: "DrawEllipseLines", header: raylibH, sideEffect.}
else:
  ## Vita: DrawEllipse/DrawEllipseLines unverified. No-op until raddy-5ce confirms.
  ## If absent, render.nim can fall back to DrawCircleV when rx ≈ ry.
  proc rDrawEllipse*(cx, cy: int32; rx, ry: float32; color: RColor) = discard
  proc rDrawEllipseLines*(cx, cy: int32; rx, ry: float32; color: RColor) = discard

# ---------------------------------------------------------------------------
# Text and texture
# ---------------------------------------------------------------------------

proc rDrawTextEx*(font: RFont; text: cstring; pos: RVec2; fontSize, spacing: float32; color: RColor)
    {.importc: "rlDrawTextEx", header: raylibH, sideEffect.}
  ## C name is rlDrawTextEx (naylib's raylib renames DrawTextEx to avoid Win32 collision).
  ## Vita console port may use DrawTextEx — verify in raddy-5ce.

proc rDrawTextureRec*(tex: RTexture; src: RRect; pos: RVec2; tint: RColor)
    {.importc: "DrawTextureRec", header: raylibH, sideEffect.}

# ---------------------------------------------------------------------------
# Scissor
# ---------------------------------------------------------------------------

proc rBeginScissorMode*(x, y, w, h: int32)
    {.importc: "BeginScissorMode", header: raylibH, sideEffect.}

proc rEndScissorMode*()
    {.importc: "EndScissorMode", header: raylibH, sideEffect.}
