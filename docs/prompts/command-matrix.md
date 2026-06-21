# Nuklear Command Matrix

This file maps every `NK_COMMAND_*` enum value to its exact raylib draw call(s). Downstream
agents MUST use the formulas below verbatim. Do not approximate, invent alternatives, or
deviate from pinned segment counts.

All types used here refer to the raddy-local aliases defined in
`src/raddy/backend/raylib_api.nim`: `RColor`, `RVec2`, `RRect`, `RFont`.

---

## Quick Reference Table

| NK_COMMAND | raylib call(s) | Notes |
|---|---|---|
| `NK_COMMAND_NOP` | — | Skip. No draw call. |
| `NK_COMMAND_SCISSOR` | `BeginScissorMode` / `EndScissorMode` | Y-flip required; replace semantics |
| `NK_COMMAND_LINE` | `DrawLineEx` | |
| `NK_COMMAND_CURVE` | `DrawLineStrip` (N=20 segments) | Self-tessellate cubic Bézier |
| `NK_COMMAND_RECT` | `DrawRectangleLinesEx` or `DrawRectangleRoundedLines` | Depends on rounding |
| `NK_COMMAND_RECT_FILLED` | `DrawRectangleRec` or `DrawRectangleRounded` | Depends on rounding |
| `NK_COMMAND_RECT_MULTI_COLOR` | `DrawRectangleGradientEx` | 4-corner gradient; no-op if unavailable |
| `NK_COMMAND_CIRCLE` | `DrawEllipse` (outline) | rx=w/2, ry=h/2 |
| `NK_COMMAND_CIRCLE_FILLED` | `DrawEllipse` (filled) | rx=w/2, ry=h/2 |
| `NK_COMMAND_ARC` | `DrawRing` or tessellate (segments=16) | No angle flip needed |
| `NK_COMMAND_ARC_FILLED` | `DrawCircleSector` (segments=16) | No angle flip needed |
| `NK_COMMAND_TRIANGLE` | `DrawTriangle` | Winding check required |
| `NK_COMMAND_TRIANGLE_FILLED` | `DrawTriangleFilled` | Winding check required |
| `NK_COMMAND_POLYGON` | iterate edges with `DrawLineEx` | |
| `NK_COMMAND_POLYGON_FILLED` | `DrawTriangleFan` or fan tessellation | |
| `NK_COMMAND_POLYLINE` | `DrawLineStrip` | Open path, not closed |
| `NK_COMMAND_TEXT` | `DrawTextEx` | No Nim string; explicit len |
| `NK_COMMAND_IMAGE` | `DrawTextureRec` | ptr cast from handle |
| `NK_COMMAND_CUSTOM` | — (logged no-op) | Do not crash |

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
replaces the previous one — do NOT nest scissors. The previous `BeginScissorMode` is implicitly
cancelled by the new one (raylib handles this).

**Cleanup.** Call `EndScissorMode()` once, at the END of the command-queue pass, before
`EndTextureMode()` or `EndDrawing()`. Do not call it per-command.

---

### NK_COMMAND_LINE

```nim
DrawLineEx(
  startPos = RVec2(x: cmd.begin.x.float32, y: cmd.begin.y.float32),
  endPos   = RVec2(x: cmd.end.x.float32,   y: cmd.end.y.float32),
  thick    = cmd.line_thickness.float32,
  color    = toRColor(cmd.color)
)
```

---

### NK_COMMAND_CURVE (cubic Bézier)

Tessellate to N=20 line segments (21 points). Compute via the standard cubic Bézier formula:

```
B(t) = (1-t)³·P0 + 3·(1-t)²·t·P1 + 3·(1-t)·t²·P2 + t³·P3

where:
  P0 = cmd.begin  (start point)
  P1 = cmd.ctrl[0]  (first control point)
  P2 = cmd.ctrl[1]  (second control point)
  P3 = cmd.end    (end point)
  t  = i / N,  for i in 0..N  (N=20)
```

Build an array of 21 `RVec2` points, then:

```nim
DrawLineStrip(pts, color = toRColor(cmd.color))
```

Pinned: N=20 segments. Do not make this configurable. Do not use de Casteljau unless you
verify it produces identical results.

---

### NK_COMMAND_RECT

Branch on `cmd.rounding`:

**No rounding (`cmd.rounding == 0`):**

```nim
DrawRectangleLinesEx(
  rec   = RRect(x: cmd.x.float32, y: cmd.y.float32,
                width: cmd.w.float32, height: cmd.h.float32),
  lineThick = cmd.line_thickness.float32,
  color = toRColor(cmd.color)
)
```

**With rounding (`cmd.rounding > 0`):**

```nim
let roundness = clamp(2.0f * cmd.rounding.float32 / min(cmd.w, cmd.h).float32, 0.0f, 1.0f)
DrawRectangleRoundedLines(
  rec       = RRect(x: cmd.x.float32, y: cmd.y.float32,
                    width: cmd.w.float32, height: cmd.h.float32),
  roundness = roundness,
  segments  = 8,
  lineThick = cmd.line_thickness.float32,
  color     = toRColor(cmd.color)
)
```

Pinned: segments=8.

---

### NK_COMMAND_RECT_FILLED

Branch on `cmd.rounding`:

**No rounding (`cmd.rounding == 0`):**

```nim
DrawRectangleRec(
  rec   = RRect(x: cmd.x.float32, y: cmd.y.float32,
                width: cmd.w.float32, height: cmd.h.float32),
  color = toRColor(cmd.color)
)
```

**With rounding (`cmd.rounding > 0`):**

```nim
let roundness = clamp(2.0f * cmd.rounding.float32 / min(cmd.w, cmd.h).float32, 0.0f, 1.0f)
DrawRectangleRounded(
  rec       = RRect(x: cmd.x.float32, y: cmd.y.float32,
                    width: cmd.w.float32, height: cmd.h.float32),
  roundness = roundness,
  segments  = 8,
  color     = toRColor(cmd.color)
)
```

Pinned: segments=8. Same roundness formula as NK_COMMAND_RECT.

---

### NK_COMMAND_RECT_MULTI_COLOR

```nim
DrawRectangleGradientEx(
  rec         = RRect(x: cmd.x.float32, y: cmd.y.float32,
                      width: cmd.w.float32, height: cmd.h.float32),
  topLeft     = toRColor(cmd.top_left),
  bottomLeft  = toRColor(cmd.bottom_left),
  bottomRight = toRColor(cmd.bottom_right),
  topRight    = toRColor(cmd.top_right)
)
```

`DrawRectangleGradientEx` is a required host proc. If `raylib_console.nim` does not expose it,
emit a logged no-op: log once at debug level "NK_COMMAND_RECT_MULTI_COLOR: DrawRectangleGradientEx
not available on this platform" and skip the draw. Do not crash.

---

### NK_COMMAND_CIRCLE

```nim
let cx = cmd.x.float32 + cmd.w.float32 / 2.0f
let cy = cmd.y.float32 + cmd.h.float32 / 2.0f
let rx = cmd.w.float32 / 2.0f
let ry = cmd.h.float32 / 2.0f
DrawEllipseLines(cx.int32, cy.int32, rx, ry, toRColor(cmd.color))
```

Note: NK_COMMAND_CIRCLE is the OUTLINE variant. Use `DrawEllipseLines` (outline), not
`DrawEllipse` (filled).

---

### NK_COMMAND_CIRCLE_FILLED

```nim
let cx = cmd.x.float32 + cmd.w.float32 / 2.0f
let cy = cmd.y.float32 + cmd.h.float32 / 2.0f
let rx = cmd.w.float32 / 2.0f
let ry = cmd.h.float32 / 2.0f
DrawEllipse(cx.int32, cy.int32, rx, ry, toRColor(cmd.color))
```

---

### NK_COMMAND_ARC (outline)

Convert angles from radians to degrees:

```
startDeg = cmd.a[0] * 180.0 / PI
endDeg   = cmd.a[1] * 180.0 / PI
```

**Handedness note.** Nuklear arcs are clockwise in Y-down screen space. raylib
`DrawCircleSector` and `DrawRing` also use clockwise in Y-down. No additional angle
flip or negation is needed.

```nim
DrawRing(
  center      = RVec2(x: cmd.cx.float32, y: cmd.cy.float32),
  innerRadius = cmd.r.float32 - cmd.line_thickness.float32 / 2.0f,
  outerRadius = cmd.r.float32 + cmd.line_thickness.float32 / 2.0f,
  startAngle  = startDeg,
  endAngle    = endDeg,
  segments    = 16,
  color       = toRColor(cmd.color)
)
```

Pinned: segments=16.

---

### NK_COMMAND_ARC_FILLED

```nim
let startDeg = cmd.a[0] * 180.0f / PI
let endDeg   = cmd.a[1] * 180.0f / PI
DrawCircleSector(
  center     = RVec2(x: cmd.cx.float32, y: cmd.cy.float32),
  radius     = cmd.r.float32,
  startAngle = startDeg,
  endAngle   = endDeg,
  segments   = 16,
  color      = toRColor(cmd.color)
)
```

Pinned: segments=16. No angle flip.

---

### NK_COMMAND_TRIANGLE and NK_COMMAND_TRIANGLE_FILLED

**Winding check is required.** raylib's triangle rasterizer culls clockwise (CW) triangles.
Nuklear emits CW triangles for internal widgets (scrollbar arrows, combo arrows). Failure to
correct winding causes those arrows to be invisible.

Compute signed area in Y-down screen space:

```
area = (b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)
```

If `area < 0`, the triangle is CW. Swap `b` and `c` to make it CCW before calling the draw proc.

**NK_COMMAND_TRIANGLE (outline):**

```nim
var a = RVec2(x: cmd.a.x.float32, y: cmd.a.y.float32)
var b = RVec2(x: cmd.b.x.float32, y: cmd.b.y.float32)
var c = RVec2(x: cmd.c.x.float32, y: cmd.c.y.float32)
let area = (b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)
if area < 0.0f: swap(b, c)
DrawTriangleLines(a, b, c, toRColor(cmd.color))
```

**NK_COMMAND_TRIANGLE_FILLED:**

```nim
var a = RVec2(x: cmd.a.x.float32, y: cmd.a.y.float32)
var b = RVec2(x: cmd.b.x.float32, y: cmd.b.y.float32)
var c = RVec2(x: cmd.c.x.float32, y: cmd.c.y.float32)
let area = (b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)
if area < 0.0f: swap(b, c)
DrawTriangle(a, b, c, toRColor(cmd.color))
```

---

### NK_COMMAND_POLYGON (outline)

Iterate edges and draw each as a line:

```nim
for i in 0 ..< cmd.point_count:
  let a = RVec2(x: cmd.points[i].x.float32, y: cmd.points[i].y.float32)
  let b = RVec2(x: cmd.points[(i + 1) mod cmd.point_count].x.float32,
                y: cmd.points[(i + 1) mod cmd.point_count].y.float32)
  DrawLineEx(a, b, cmd.line_thickness.float32, toRColor(cmd.color))
```

The last edge closes from `points[point_count-1]` back to `points[0]`.

---

### NK_COMMAND_POLYGON_FILLED

Fan-tessellate from the first vertex:

```nim
for i in 1 ..< cmd.point_count - 1:
  let a = RVec2(x: cmd.points[0].x.float32,     y: cmd.points[0].y.float32)
  let b = RVec2(x: cmd.points[i].x.float32,     y: cmd.points[i].y.float32)
  let c = RVec2(x: cmd.points[i + 1].x.float32, y: cmd.points[i + 1].y.float32)
  # Apply winding check (same formula as triangle section):
  let area = (b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)
  if area < 0.0f:
    DrawTriangle(a, c, b, toRColor(cmd.color))
  else:
    DrawTriangle(a, b, c, toRColor(cmd.color))
```

Alternatively use `DrawTriangleFan` if the platform binding exposes it, passing all points
and the fill color.

---

### NK_COMMAND_POLYLINE

Open polyline (NOT closed). Use `DrawLineStrip`:

```nim
var pts = newSeq[RVec2](cmd.point_count)
for i in 0 ..< cmd.point_count:
  pts[i] = RVec2(x: cmd.points[i].x.float32, y: cmd.points[i].y.float32)
DrawLineStrip(pts, toRColor(cmd.color))
```

Do not connect the last point back to the first — this is NOT a closed polygon.

---

### NK_COMMAND_TEXT

```nim
# cmd.font is ptr nk_user_font; cmd.font.userdata.ptr is the raw ptr Font we stored at init.
let fontPtr = cast[ptr RFont](cmd.font.userdata.ptr)

# Build a fixed stack buffer to hold the text. NK text is NOT null-terminated.
# cmd.length is the byte count.
const MaxTextBytes = 1024
var buf: array[MaxTextBytes, char]
let copyLen = min(cmd.length, MaxTextBytes - 1)
copyMem(addr buf[0], cmd.string, copyLen)
buf[copyLen] = '\0'

DrawTextEx(
  font     = fontPtr[],
  text     = cast[cstring](addr buf[0]),
  position = RVec2(x: cmd.x.float32, y: cmd.y.float32),
  fontSize = cmd.font.height,
  spacing  = 2.0f,
  tint     = toRColor(cmd.foreground)
)
```

**Critical rules:**
- NEVER do `$cmd.string` or construct a Nim `string` from the text pointer. The Nuklear text
  buffer is NOT null-terminated. Doing so reads past the end of valid memory.
- The 1024-byte stack buffer is the correct pattern. Text that exceeds 1023 bytes is safely
  truncated (a debug log is acceptable but not required).
- `spacing = 2.0f` is the pinned default. Do not use 0 or 1.
- `fontSize` comes from `cmd.font.height`, not from a separate field.

---

### NK_COMMAND_IMAGE

```nim
# cmd.img.handle.ptr is a raw ptr Texture2D stored by the caller at image creation time.
let texPtr = cast[ptr Texture2D](cmd.img.handle.ptr)

let srcRect  = RRect(x: 0, y: 0,
                     width: texPtr[].width.float32,
                     height: texPtr[].height.float32)
let destPos  = RVec2(x: cmd.x.float32, y: cmd.y.float32)

DrawTextureRec(texPtr[], srcRect, destPos, WHITE)
```

**Scoping note.** IMAGE support is best-effort. It requires the consumer to:
1. Load a `Texture2D` whose lifetime exceeds all Nuklear frames that reference it.
2. Store `addr texture` in `nk_image.handle.ptr` when creating the `nk_image`.

If `cmd.img.handle.ptr` is nil, skip and log once at debug level. Do not crash.
`DrawTextureRec` is in the required host-proc list. If the console binding lacks it, emit a
logged no-op.

---

### NK_COMMAND_CUSTOM

Documented no-op. Log once (debug builds only) on the first encounter:

```
"NK_COMMAND_CUSTOM encountered — not implemented in raddy"
```

Do not log on every frame (gate behind a `var customWarnEmitted = false` module-level flag).
Do not crash. Do not attempt to call any draw proc.

---

## Coverage Summary

| Command | Status |
|---|---|
| NK_COMMAND_NOP | skip |
| NK_COMMAND_SCISSOR | implemented (Y-flip, replace semantics) |
| NK_COMMAND_LINE | implemented |
| NK_COMMAND_CURVE | implemented (N=20 segments, cubic Bézier) |
| NK_COMMAND_RECT | implemented (plain + rounded, segments=8) |
| NK_COMMAND_RECT_FILLED | implemented (plain + rounded, segments=8) |
| NK_COMMAND_RECT_MULTI_COLOR | implemented (no-op fallback if proc missing) |
| NK_COMMAND_CIRCLE | implemented (outline via DrawEllipseLines) |
| NK_COMMAND_CIRCLE_FILLED | implemented (filled via DrawEllipse) |
| NK_COMMAND_ARC | implemented (segments=16, no angle flip) |
| NK_COMMAND_ARC_FILLED | implemented (segments=16, no angle flip) |
| NK_COMMAND_TRIANGLE | implemented (winding check + swap) |
| NK_COMMAND_TRIANGLE_FILLED | implemented (winding check + swap) |
| NK_COMMAND_POLYGON | implemented (edge iteration) |
| NK_COMMAND_POLYGON_FILLED | implemented (fan tessellation, winding per triangle) |
| NK_COMMAND_POLYLINE | implemented (open, DrawLineStrip) |
| NK_COMMAND_TEXT | implemented (stack buf, no Nim string, spacing=2.0) |
| NK_COMMAND_IMAGE | best-effort (requires caller to embed ptr Texture2D) |
| NK_COMMAND_CUSTOM | logged no-op (warn once, no crash) |
