## geom.nim — Pure geometric conversion procs for the raddy renderer.
##
## No side effects. No heap allocation. All procs are testable with doAssert.
## Decoupled-core: this module is in backend/ and is allowed to import raylib_api.

import ../types        ## nk_color, nk_byte, etc.
import ./raylib_api    ## RColor, RVec2

# ---------------------------------------------------------------------------
# Constants — all pinned; do not make configurable.
# ---------------------------------------------------------------------------

const BezierSegs*       = 20  ## Pinned. Do not make configurable.
const ArcSegs*          = 16  ## Pinned segment count for DrawRing/DrawCircleSector.
const RoundedRectSegs*  = 8   ## Pinned for DrawRectangleRounded/RoundedLinesEx.
const PolyLineMax*      = 64  ## Max polyline points. Truncate longer with debug log.
const PI* = 3.14159265358979323846f32

# ---------------------------------------------------------------------------
# Internal helpers (not exported)
# ---------------------------------------------------------------------------

proc clampF(v, lo, hi: float32): float32 {.inline.} =
  if v < lo: lo elif v > hi: hi else: v

# ---------------------------------------------------------------------------
# Exported procs
# ---------------------------------------------------------------------------

proc toRColor*(c: nk_color): RColor {.inline.} =
  ## Convert nk_color to raddy RColor.
  result.r = c.r
  result.g = c.g
  result.b = c.b
  result.a = c.a

proc rectRoundness*(rounding: float32; w, h: float32): float32 =
  ## Compute Nuklear roundness as a 0..1 float for raylib's DrawRectangleRounded.
  ## Guard: returns 0.0 if w <= 0 or h <= 0 (avoids division by zero).
  if w <= 0.0f or h <= 0.0f:
    return 0.0f
  let minSide = if w < h: w else: h
  clampF(2.0f * rounding / minSide, 0.0f, 1.0f)

proc fixTriWinding*(a, b, c: var RVec2) =
  ## Check triangle winding and swap b,c if needed so DrawTriangle (CCW) renders correctly.
  ## Y-down screen space: signed area = (b-a)×(c-a). Positive area = CW. Swap when positive.
  let area = (b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)
  if area > 0.0f:
    let tmp = b
    b = c
    c = tmp

proc radToDeg*(rad: float32): float32 {.inline.} =
  ## Convert radians to degrees (float32 version for Nuklear arc angles).
  rad * (180.0f / PI)

proc bezierTessellate*(P0, P1, P2, P3: RVec2; pts: var array[21, RVec2]) =
  ## Tessellate a cubic Bézier curve into N=20 segments (21 points, stack array).
  ## P0=start, P1=ctrl[0], P2=ctrl[1], P3=end.
  ## Sets pts[0..20] in place.
  for i in 0..20:
    let t = float32(i) / 20.0f
    let mt = 1.0f - t
    pts[i].x = mt*mt*mt*P0.x + 3.0f*mt*mt*t*P1.x + 3.0f*mt*t*t*P2.x + t*t*t*P3.x
    pts[i].y = mt*mt*mt*P0.y + 3.0f*mt*mt*t*P1.y + 3.0f*mt*t*t*P2.y + t*t*t*P3.y
