# Nuklear Command Matrix

This file maps every `NK_COMMAND_*` enum value to its exact raylib draw call(s). Downstream
agents MUST use the formulas below verbatim. Do not approximate, invent alternatives, or
deviate from pinned segment counts.

All types used here refer to the raddy-local aliases defined in
`src/raddy/backend/raylib_api.nim`: `RColor`, `RVec2`, `RRect`, `RFont`, `RTexture`.

---

## Quick Reference Table

| NK_COMMAND | raylib call(s) | Notes |
|---|---|---|
| `NK_COMMAND_NOP` | — | Skip. No draw call. |
| `NK_COMMAND_SCISSOR` | `BeginScissorMode` / `EndScissorMode` | Y-flip required; replace semantics; see frame-order.md for `scissorActive` guard |
| `NK_COMMAND_LINE` | `DrawLineEx` | `cmd.`begin`/`end`` need backtick-escaping in Nim |
| `NK_COMMAND_CURVE` | `DrawLineStrip` (N=20 segments, 21 pts) | Self-tessellate cubic Bézier; backtick-escape `begin`/`end` |
| `NK_COMMAND_RECT` | `DrawRectangleLinesEx` or `DrawRectangleRoundedLines` | Depends on rounding; skip if w≤0 or h≤0 |
| `NK_COMMAND_RECT_FILLED` | `DrawRectangleRec` or `DrawRectangleRounded` | Depends on rounding; skip if w≤0 or h≤0 |
| `NK_COMMAND_RECT_MULTI_COLOR` | `DrawRectangleGradientEx` | 4-corner gradient; no-op if unavailable |
| `NK_COMMAND_CIRCLE` | `DrawEllipseLines` (outline) | rx=w/2, ry=h/2; fallback if unavailable |
| `NK_COMMAND_CIRCLE_FILLED` | `DrawEllipse` (filled) | rx=w/2, ry=h/2; fallback if unavailable |
| `NK_COMMAND_ARC` | `DrawRing` (segments=16) | Radians→degrees; **handedness PROVISIONAL** |
| `NK_COMMAND_ARC_FILLED` | `DrawCircleSector` (segments=16) | Radians→degrees; **handedness PROVISIONAL** |
| `NK_COMMAND_TRIANGLE` | `DrawTriangleLines` | **Winding check PROVISIONAL** — verify empirically |
| `NK_COMMAND_TRIANGLE_FILLED` | `DrawTriangle` | **Winding check PROVISIONAL** — same proc as filled; `DrawTriangleFilled` does NOT exist in raylib |
| `NK_COMMAND_POLYGON` | iterate edges with `DrawLineEx` | |
| `NK_COMMAND_POLYGON_FILLED` | fan tessellation with `DrawTriangle` | Convex polygons only; `point_count < 3` guard required |
| `NK_COMMAND_POLYLINE` | `DrawLineStrip` (stack buffer) | Open path; no per-frame heap alloc |
| `NK_COMMAND_TEXT` | `DrawTextEx` | Stack buf; no Nim string; `fontSize = cmd.height`; `cmd.`string`` needs backtick-escape |
| `NK_COMMAND_IMAGE` | `rDrawTextureRec` | `RTexture`/`RColor` aliases only — no raw `Texture2D`/`WHITE` |
| `NK_COMMAND_CUSTOM` | — (logged no-op) | Do not crash |

---

## Nim Keyword Escaping (Required in Bindings)

Several Nuklear struct fields collide with Nim keywords or built-in type names. In any
`{.importc.}` binding, access these fields with backtick-escaping:

| Struct | Field | Nim escape |
|---|---|---|
| `nk_command_line`, `nk_command_curve` | `begin`, `end` | `` cmd.`begin` ``, `` cmd.`end` `` |
| `nk_command_curve` | `ctrl[2]` | `cmd.ctrl[0]`, `cmd.ctrl[1]` (array access, no escape needed) |
| `nk_command_text` | `string` | `` cmd.`string` `` |

The C struct field *order* is `begin, end, ctrl[2]` for `nk_command_curve` — this matters only
if someone writes a manual struct binding (name-based importc access is order-independent).

---

## Detailed Formulas

### NK_COMMAND_NOP

Skip. Emit no draw call. Continue to the next command.

---

### NK_COMMAND_SCISSOR

```
H = current framebuffer height
  (RenderTexture.texture.height when inside BeginTextureMode,
   GetScreenHeight() otherwise)

BeginScissorMode(cmd.x, H - cmd.y - cmd.h, cmd.w, cmd.h)
```

**Y-flip is required.** Nuklear uses top-left Y-down coordinates. OpenGL framebuffers
(and raylib's RenderTexture) store rows bottom-up, so the Y axis is flipped relative to
Nuklear's coordinate system. The formula `H - y - h` corrects for this.

**Replace semantics.** Only one scissor rect is active at a time. A new `NK_COMMAND_SCISSOR`
replaces the previous one — do NOT nest scissors.

**Cleanup with `scissorActive` guard.** See `frame-order.md` for the required tracking
pattern. Do NOT call `EndScissorMode()` unconditionally — closing a scissor that was never
opened is undefined behavior. The `scissorActive: bool` flag in `raddyRender` controls this.

---

### NK_COMMAND_LINE

```nim
# Note: `begin` and `end` are Nim keywords — backtick-escape required in the binding.
DrawLineEx(
  startPos = RVec2(x: cmd.`begin`.x.float32, y: cmd.`begin`.y.float32),
  endPos   = RVec2(x: cmd.`end`.x.float32,   y: cmd.`end`.y.float32),
  thick    = cmd.line_thickness.float32,
  color    = toRColor(cmd.color)
)
```

---

### NK_COMMAND_CURVE (cubic Bézier)

Tessellate to N=20 line segments (21 points). Use a fixed stack array — no heap allocation.

```nim
# Note: `begin` and `end` are Nim keywords — backtick-escape required.
# Nuklear struct field order: begin, end, ctrl[2]
let P0 = RVec2(x: cmd.`begin`.x.float32, y: cmd.`begin`.y.float32)
let P1 = RVec2(x: cmd.ctrl[0].x.float32, y: cmd.ctrl[0].y.float32)
let P2 = RVec2(x: cmd.ctrl[1].x.float32, y: cmd.ctrl[1].y.float32)
let P3 = RVec2(x: cmd.`end`.x.float32,   y: cmd.`end`.y.float32)

var pts: array[21, RVec2]  # N=20 segments → 21 endpoints
for i in 0..20:
  let t  = float32(i) / 20.0f
  let mt = 1.0f - t
  pts[i] = RVec2(
    x: mt*mt*mt*P0.x + 3.0f*mt*mt*t*P1.x + 3.0f*mt*t*t*P2.x + t*t*t*P3.x,
    y: mt*mt*mt*P0.y + 3.0f*mt*mt*t*P1.y + 3.0f*mt*t*t*P2.y + t*t*t*P3.y
  )
rDrawLineStrip(addr pts[0], 21, toRColor(cmd.color))
```

Pinned: N=20 segments. Do not make configurable. Stack array avoids per-frame allocation.

---

### NK_COMMAND_RECT

Branch on `cmd.rounding`. **Guard against zero-area rects before any division.**

**No rounding (`cmd.rounding == 0`):**

```nim
rDrawRectangleLinesEx(
  rect  = RRect(x: cmd.x.float32, y: cmd.y.float32,
                width: cmd.w.float32, height: cmd.h.float32),
  thick = cmd.line_thickness.float32,
  color = toRColor(cmd.color)
)
```

**With rounding (`cmd.rounding > 0`):**

```nim
# Skip zero-area rects — min(0,x) = 0 → division by zero in roundness formula.
if cmd.w <= 0 or cmd.h <= 0: return
let roundness = clamp(2.0f * cmd.rounding.float32 / min(cmd.w, cmd.h).float32, 0.0f, 1.0f)
rDrawRectangleRoundedLines(
  rect      = RRect(x: cmd.x.float32, y: cmd.y.float32,
                    width: cmd.w.float32, height: cmd.h.float32),
  roundness = roundness,
  segs      = 8,
  thick     = cmd.line_thickness.float32,
  color     = toRColor(cmd.color)
)
```

Pinned: segments=8.

---

### NK_COMMAND_RECT_FILLED

Branch on `cmd.rounding`. **Same zero-area guard.**

**No rounding (`cmd.rounding == 0`):**

```nim
rDrawRectangleRec(
  rect  = RRect(x: cmd.x.float32, y: cmd.y.float32,
                width: cmd.w.float32, height: cmd.h.float32),
  color = toRColor(cmd.color)
)
```

**With rounding (`cmd.rounding > 0`):**

```nim
if cmd.w <= 0 or cmd.h <= 0: return
let roundness = clamp(2.0f * cmd.rounding.float32 / min(cmd.w, cmd.h).float32, 0.0f, 1.0f)
rDrawRectangleRounded(
  rect      = RRect(x: cmd.x.float32, y: cmd.y.float32,
                    width: cmd.w.float32, height: cmd.h.float32),
  roundness = roundness,
  segs      = 8,
  color     = toRColor(cmd.color)
)
```

Pinned: segments=8.

---

### NK_COMMAND_RECT_MULTI_COLOR

```nim
rDrawRectangleGradientEx(
  rect        = RRect(x: cmd.x.float32, y: cmd.y.float32,
                      width: cmd.w.float32, height: cmd.h.float32),
  c1          = toRColor(cmd.top_left),
  c2          = toRColor(cmd.bottom_left),
  c3          = toRColor(cmd.bottom_right),
  c4          = toRColor(cmd.top_right)
)
```

`rDrawRectangleGradientEx` is in the required host proc list. If absent from the console
binding, emit a logged no-op (once per session) and skip. Do not crash.

---

### NK_COMMAND_CIRCLE (outline)

```nim
let cx = cmd.x.float32 + cmd.w.float32 / 2.0f
let cy = cmd.y.float32 + cmd.h.float32 / 2.0f
let rx = cmd.w.float32 / 2.0f
let ry = cmd.h.float32 / 2.0f
# Note: DrawEllipseLines takes integer center coords — sub-pixel truncation is accepted.
rDrawEllipseLines(cx.int32, cy.int32, rx, ry, toRColor(cmd.color))
```

`NK_COMMAND_CIRCLE` is the **outline** variant. Use `DrawEllipseLines`, NOT `DrawEllipse`.
If `DrawEllipseLines` is absent from the console binding, emit a logged no-op. A
`DrawCircleLines`-based fallback is acceptable for the common w==h (circular) case.

---

### NK_COMMAND_CIRCLE_FILLED

```nim
let cx = cmd.x.float32 + cmd.w.float32 / 2.0f
let cy = cmd.y.float32 + cmd.h.float32 / 2.0f
let rx = cmd.w.float32 / 2.0f
let ry = cmd.h.float32 / 2.0f
rDrawEllipse(cx.int32, cy.int32, rx, ry, toRColor(cmd.color))
```

---

### NK_COMMAND_ARC (outline) — ⚠️ HANDEDNESS PROVISIONAL

Convert angles from radians to degrees:

```
startDeg = cmd.a[0] * 180.0 / PI
endDeg   = cmd.a[1] * 180.0 / PI
```

**⚠️ HANDEDNESS NOTE — VERIFY EMPIRICALLY before shipping.** The claim that raylib
`DrawRing` / `DrawCircleSector` sweep direction matches Nuklear's radian arc without
angle negation has NOT been confirmed against the actual console binding. raylib
`DrawCircleSector` sweeps clockwise from `startAngle` to `endAngle` in screen space
(Y-down). Verify a quarter-arc from 0 to π/2 renders correctly before marking verified.

```nim
let startDeg = cmd.a[0] * 180.0f / PI
let endDeg   = cmd.a[1] * 180.0f / PI
rDrawRing(
  center      = RVec2(x: cmd.cx.float32, y: cmd.cy.float32),
  innerRadius = max(0.0f, cmd.r.float32 - cmd.line_thickness.float32 / 2.0f),
  outerRadius = cmd.r.float32 + cmd.line_thickness.float32 / 2.0f,
  startAngle  = startDeg,
  endAngle    = endDeg,
  segs        = 16,
  color       = toRColor(cmd.color)
)
```

Pinned: segments=16.

---

### NK_COMMAND_ARC_FILLED — ⚠️ HANDEDNESS PROVISIONAL

```nim
let startDeg = cmd.a[0] * 180.0f / PI
let endDeg   = cmd.a[1] * 180.0f / PI
rDrawCircleSector(
  center     = RVec2(x: cmd.cx.float32, y: cmd.cy.float32),
  radius     = cmd.r.float32,
  startDeg   = startDeg,
  endDeg     = endDeg,
  segs       = 16,
  color      = toRColor(cmd.color)
)
```

**⚠️ Same PROVISIONAL warning as NK_COMMAND_ARC.** Verify sweep direction empirically.

Pinned: segments=16.

---

### NK_COMMAND_TRIANGLE and NK_COMMAND_TRIANGLE_FILLED — ⚠️ WINDING PROVISIONAL

> **⚠️ WINDING CHECK — PROVISIONAL. Verify empirically before shipping.**
>
> The winding correction below is based on analysis of the Y-down signed-area formula.
> In Y-down screen space, the cross product `(b-a)×(c-a)` is **positive for CW triangles**
> and **negative for CCW triangles** (opposite of Y-up math convention). raylib's
> `DrawTriangle` expects CCW order to render the visible face.
>
> Therefore: **swap when `area > 0`** (CW in Y-down = positive area).
>
> Note: if raylib's 2D renderer has backface culling disabled (the OpenGL default), the
> winding check is a no-op and both orderings render. Verify by rendering a known arrow
> (scrollbar or combo) and checking it is visible. Update this PROVISIONAL marker once
> confirmed.
>
> **`DrawTriangleFilled` does NOT exist in raylib.** Both outline and filled triangles
> use `DrawTriangleLines` and `DrawTriangle` respectively.

**NK_COMMAND_TRIANGLE (outline):**

```nim
var a = RVec2(x: cmd.a.x.float32, y: cmd.a.y.float32)
var b = RVec2(x: cmd.b.x.float32, y: cmd.b.y.float32)
var c = RVec2(x: cmd.c.x.float32, y: cmd.c.y.float32)
# Y-down: positive area = CW (raylib culls CW). Swap b,c to make CCW.
let area = (b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)
if area > 0.0f: swap(b, c)
rDrawTriangleLines(a, b, c, toRColor(cmd.color))
```

**NK_COMMAND_TRIANGLE_FILLED:**

```nim
var a = RVec2(x: cmd.a.x.float32, y: cmd.a.y.float32)
var b = RVec2(x: cmd.b.x.float32, y: cmd.b.y.float32)
var c = RVec2(x: cmd.c.x.float32, y: cmd.c.y.float32)
let area = (b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)
if area > 0.0f: swap(b, c)
rDrawTriangle(a, b, c, toRColor(cmd.color))
```

---

### NK_COMMAND_POLYGON (outline)

Iterate edges and draw each as a line:

```nim
for i in 0 ..< int(cmd.point_count):
  let a = RVec2(x: cmd.points[i].x.float32, y: cmd.points[i].y.float32)
  let b = RVec2(x: cmd.points[(i + 1) mod int(cmd.point_count)].x.float32,
                y: cmd.points[(i + 1) mod int(cmd.point_count)].y.float32)
  rDrawLineEx(a, b, cmd.line_thickness.float32, toRColor(cmd.color))
```

The last edge closes from `points[point_count-1]` back to `points[0]`.

---

### NK_COMMAND_POLYGON_FILLED

Fan-tessellate from the first vertex. **Correct only for convex polygons.** Nuklear's
filled polygon commands (rounded rect corners, arrows) are convex — document this
assumption; do NOT add per-triangle winding flips (they are inconsistent for fans).

```nim
# Unsigned underflow guard: point_count is nk_uint. Cast before arithmetic.
if int(cmd.point_count) < 3: return

let n = int(cmd.point_count)
for i in 1 ..< n - 1:
  let a = RVec2(x: cmd.points[0].x.float32,     y: cmd.points[0].y.float32)
  let b = RVec2(x: cmd.points[i].x.float32,     y: cmd.points[i].y.float32)
  let c = RVec2(x: cmd.points[i + 1].x.float32, y: cmd.points[i + 1].y.float32)
  rDrawTriangle(a, b, c, toRColor(cmd.color))
```

**Note:** No per-triangle winding check here — for a convex fan all triangles share the
same winding as the source polygon. If the source polygon needs winding correction, apply
it once to the fan's vertex order, not per-triangle.

---

### NK_COMMAND_POLYLINE

Open polyline (NOT closed). Use a fixed stack array — no per-frame heap allocation.

```nim
const MaxPolyPts = 64  # cap; truncate longer polylines with a debug log
var pts: array[MaxPolyPts, RVec2]
let n = min(int(cmd.point_count), MaxPolyPts)
if int(cmd.point_count) > MaxPolyPts:
  # log once at debug level: "NK_COMMAND_POLYLINE: truncated to MaxPolyPts points"
  discard
for i in 0 ..< n:
  pts[i] = RVec2(x: cmd.points[i].x.float32, y: cmd.points[i].y.float32)
rDrawLineStrip(addr pts[0], n.int32, toRColor(cmd.color))
```

Do not connect the last point back to the first — this is NOT a closed polygon.

---

### NK_COMMAND_TEXT

```nim
# cmd.font is ptr nk_user_font; cmd.font.userdata.ptr is the raw ptr RFont stored at init.
let fontPtr = cast[ptr RFont](cmd.font.userdata.ptr)

# Build a fixed stack buffer. NK text is NOT null-terminated.
# cmd.length is the byte count. `cmd.`string`` needs backtick-escape in Nim binding.
const MaxTextBytes = 1024
var buf: array[MaxTextBytes, char]
let copyLen = min(cmd.length, MaxTextBytes - 1)
copyMem(addr buf[0], cmd.`string`, copyLen)
buf[copyLen] = '\0'

rDrawTextEx(
  font     = fontPtr[],
  text     = cast[cstring](addr buf[0]),
  pos      = RVec2(x: cmd.x.float32, y: cmd.y.float32),
  fontSize = cmd.height,    # per-command height field — equals cmd.font.height under pinned font contract
  spacing  = 2.0f,
  color    = toRColor(cmd.foreground)
)
```

**Critical rules:**
- NEVER do `$cmd.`string`` or construct a Nim `string` from the text pointer.
  The Nuklear text buffer is NOT null-terminated. `$ptr` reads past valid memory.
- `fontSize = cmd.height` (the per-command field), NOT `cmd.font.height`. They are equal
  under the pinned font contract, but `cmd.height` is the conventional field and supports
  future multi-size text correctly.
- `spacing = 2.0f` is the pinned default. Must match `MeasureTextEx` spacing in the width
  callback — if they diverge, text overflows its bounding box.
- `cmd.background`, `cmd.w`, `cmd.h` are intentionally ignored. Nuklear pre-fills the text
  background with a separate `NK_COMMAND_RECT_FILLED` command. Do NOT draw a background
  rect here — it would double-paint.

---

### NK_COMMAND_IMAGE

```nim
# cmd.img.handle.ptr is a ptr RTexture stored by the caller at image-handle creation time.
# The consumer is responsible for keeping the texture alive for the frame's duration.
if cmd.img.handle.ptr == nil:
  # log once at debug level: "NK_COMMAND_IMAGE: nil texture handle — skipping"
  return

let texPtr = cast[ptr RTexture](cmd.img.handle.ptr)

# Use full texture dimensions as source rect.
# Note: cmd.w/cmd.h carry the destination size but rDrawTextureRec does not scale.
# If scaling is needed, the adapter must be extended with rDrawTexturePro.
let srcRect = RRect(x: 0, y: 0,
                    width:  float32(texPtr[].width),
                    height: float32(texPtr[].height))
let destPos = RVec2(x: cmd.x.float32, y: cmd.y.float32)

rDrawTextureRec(texPtr[], srcRect, destPos, RColor(r: 255, g: 255, b: 255, a: 255))
```

**Platform-agnostic rule.** Use ONLY `RTexture` and `rDrawTextureRec` — never raw
`Texture2D`, `WHITE`, or any host-specific type name. `WHITE` may not exist in
`raylib_console.nim`; use the `RColor` literal above instead.

**Scoping note.** IMAGE support is best-effort. Requires the consumer to:
1. Load a texture whose lifetime exceeds all Nuklear frames that reference it.
2. Store `addr texture` (cast as `pointer`) in `nk_image.handle.ptr` when creating `nk_image`.

If `rDrawTextureRec` is absent from the console binding, emit a logged no-op.

---

### NK_COMMAND_CUSTOM

Documented no-op. Log once (debug builds only):

```
"NK_COMMAND_CUSTOM encountered — not implemented in raddy"
```

Gate behind a `var customWarnEmitted = false` module-level flag. Do not log every frame.
Do not crash. Do not call any draw proc.

---

## Coverage Summary

| Command | Status |
|---|---|
| NK_COMMAND_NOP | skip |
| NK_COMMAND_SCISSOR | implemented (Y-flip, replace semantics, scissorActive guard) |
| NK_COMMAND_LINE | implemented |
| NK_COMMAND_CURVE | implemented (N=20 segments, cubic Bézier, stack array) |
| NK_COMMAND_RECT | implemented (plain + rounded, segments=8, zero-area guard) |
| NK_COMMAND_RECT_FILLED | implemented (plain + rounded, segments=8, zero-area guard) |
| NK_COMMAND_RECT_MULTI_COLOR | implemented (no-op fallback if proc missing) |
| NK_COMMAND_CIRCLE | implemented (outline via DrawEllipseLines; logged no-op fallback) |
| NK_COMMAND_CIRCLE_FILLED | implemented (filled via DrawEllipse; logged no-op fallback) |
| NK_COMMAND_ARC | implemented (segments=16, radians→degrees; handedness **PROVISIONAL**) |
| NK_COMMAND_ARC_FILLED | implemented (segments=16, radians→degrees; handedness **PROVISIONAL**) |
| NK_COMMAND_TRIANGLE | implemented (winding check **PROVISIONAL**, area>0→swap) |
| NK_COMMAND_TRIANGLE_FILLED | implemented (same winding check; `DrawTriangle`, not `DrawTriangleFilled`) |
| NK_COMMAND_POLYGON | implemented (edge iteration) |
| NK_COMMAND_POLYGON_FILLED | implemented (fan tessellation, convex-only, point_count<3 guard) |
| NK_COMMAND_POLYLINE | implemented (open, DrawLineStrip, stack buffer, MaxPolyPts=64) |
| NK_COMMAND_TEXT | implemented (stack buf, `cmd.height`, spacing=2.0, no Nim string) |
| NK_COMMAND_IMAGE | best-effort (RTexture/RColor aliases; requires caller to embed ptr) |
| NK_COMMAND_CUSTOM | logged no-op (warn once, no crash) |
