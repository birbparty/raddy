# Host Draw & Input Symbol Surface

raddy's renderer calls ONLY its own normalized adapter procs in `src/raddy/backend/raylib_api.nim` — never raw naylib/console names. This file enumerates exactly what that adapter must provide, and the verification result against the actual `raylib_console.nim` in topdown and clckr.

## raddy's Normalized Type Aliases

Defined in `raylib_api.nim`, NOT imported from naylib/console:

```nim
RColor   = object r, g, b, a: uint8
RVec2    = object x, y: float32
RRect    = object x, y, width, height: float32
RFont    # opaque ref to the host Font object (holds a ptr Font from the host binding)
RTexture # opaque ref to a Texture2D
```

## Required Draw Procs

All called via raddy's adapter, never directly:

```nim
proc rDrawRectangleRec(rect: RRect, color: RColor)
proc rDrawRectangleLinesEx(rect: RRect, thick: float32, color: RColor)
proc rDrawRectangleRounded(rect: RRect, roundness: float32, segs: int32, color: RColor)
proc rDrawRectangleRoundedLines(rect: RRect, roundness: float32, segs: int32, thick: float32, color: RColor)
proc rDrawRectangleGradientEx(rect: RRect, c1, c2, c3, c4: RColor)
proc rDrawLineEx(start, end: RVec2, thick: float32, color: RColor)
proc rDrawLineStrip(pts: ptr RVec2, count: int32, color: RColor)
proc rDrawTriangle(v1, v2, v3: RVec2, color: RColor)
proc rDrawTriangleFilled(v1, v2, v3: RVec2, color: RColor)  # = DrawTriangle filled
proc rDrawCircleSector(center: RVec2, radius, startDeg, endDeg: float32, segs: int32, color: RColor)
proc rDrawEllipse(cx, cy: int32, rx, ry: float32, color: RColor)
proc rDrawTextEx(font: RFont, text: cstring, pos: RVec2, fontSize, spacing: float32, color: RColor)
proc rDrawTextureRec(tex: RTexture, src: RRect, pos: RVec2, tint: RColor)
proc rBeginScissorMode(x, y, w, h: int32)
proc rEndScissorMode()
```

## Required Input Procs

Optional naylib pump, desktop only:

```nim
proc rIsMouseButtonDown(button: int32): bool
proc rIsMouseButtonPressed(button: int32): bool
proc rGetMousePosition(): RVec2
proc rGetMouseWheelMove(): float32
proc rIsKeyDown(key: int32): bool
proc rIsKeyPressed(key: int32): bool
proc rGetCharPressed(): int32
```

## Verification Result Against topdown's raylib_console.nim

Status as of planning date:

| Symbol | Status |
|---|---|
| DrawRectangle | PRESENT (verified) |
| DrawRectangleLinesEx | PRESENT (verified) |
| DrawRectangleRounded | PRESENT (verified) |
| DrawRectangleRoundedLines | PRESENT (verified) |
| DrawRectangleGradientEx | CHECK MANUALLY — add to integration notes if missing; use no-op + log fallback |
| DrawLineEx | PRESENT |
| DrawLine | PRESENT |
| DrawTriangle | PRESENT (verify winding; see command-matrix.md) |
| DrawCircleSector | PRESENT |
| DrawEllipse | VERIFY — may be DrawEllipseLines only; check topdown console binding |
| DrawTextEx | PRESENT |
| BeginScissorMode | PRESENT (verify Y-flip applies to framebuffer height) |
| EndScissorMode | PRESENT (verify Y-flip applies to framebuffer height) |
| DrawTexture / DrawTextureRec | PRESENT |

## Missing Host Symbols Policy

If a required proc is absent from the host console binding, raddy:

1. Documents it as a gap in this file or integration notes
2. Emits a one-time debug log on first encounter
3. No-ops the command

It does NOT crash or assert on Vita for missing procs.
