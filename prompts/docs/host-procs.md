# raddy Host Proc Surface

This document enumerates every symbol that the raddy library requires from the
host platform (naylib on desktop; a raylib_console-compatible layer on PS Vita).

**Two surfaces are described:**
1. **Draw surface** — C functions called by `src/raddy/backend/render.nim` via
   `raylib_api.nim`. These must be present at link time for any build that calls
   `raddyRender`.
2. **Input surface** — C functions or Nim procs that raddy's platform pump helpers
   will need to translate host input events into Nuklear calls. The pumps are
   not yet implemented (see beads raddy-1vh and raddy-hyc); this section
   documents the anticipated surface.

---

## 1. Draw Surface

All symbols are imported via `{.importc, header: "raylib.h".}` in
`src/raddy/backend/raylib_api.nim`. The "Vita status" column reflects
confirmed/estimated availability as of 2026-06-25; actual verification
happens in bead **raddy-tzc** (external repo check).

### Types

| Nim alias | C struct          | Layout fields                       | Vita status        |
|-----------|-------------------|-------------------------------------|--------------------|
| `RColor`  | `Color`           | `r,g,b,a: uint8`                    | Confirmed present  |
| `RVec2`   | `Vector2`         | `x,y: float32`                      | Confirmed present  |
| `RRect`   | `rlRectangle`     | `x,y,width,height: float32`         | **Needs check** ¹  |
| `RFont`   | `Font`            | partial view (passed by value)       | Needs check        |
| `RTexture`| `Texture2D`       | `id,width,height,mipmaps,format`    | Confirmed present  |

¹ **rlRectangle naming**: naylib (desktop) renames `Rectangle → rlRectangle` to
avoid the Win32 `RECT` collision. The vita raylib_console port likely uses the
original `Rectangle` name. If so, add a vita guard in `raylib_api.nim`:
```nim
when defined(vita):
  type RRect* {.importc: "Rectangle", header: raylibH, completeStruct.} = object
    x*, y*, width*, height*: float32
```

### Geometry — filled rectangles

| C symbol                      | Nim wrapper              | Notes                  | Vita status        |
|-------------------------------|--------------------------|------------------------|--------------------|
| `DrawRectangleRec`            | `rDrawRectangleRec`      |                        | Confirmed          |
| `DrawRectangleLinesEx`        | `rDrawRectangleLinesEx`  |                        | Confirmed          |
| `DrawRectangleRounded`        | `rDrawRectangleRounded`  |                        | Likely present     |
| `DrawRectangleRoundedLinesEx` | `rDrawRectangleRoundedLinesEx` | Added in raylib 4.5 | **Needs check** ²  |
| `DrawRectangleGradientEx`     | `rDrawRectangleGradientEx` | Corner-color order: `topLeft,bottomLeft,bottomRight,topRight` | **Needs check** ³ |

² If absent on vita, NK_COMMAND_RECT with rounding falls back to the no-rounding path (sharp corners).

³ Parameter order may differ on some vita ports. Verify against the console `raylib.h`.

### Geometry — lines

| C symbol       | Nim wrapper        | Notes                             | Vita status       |
|----------------|--------------------|-----------------------------------|-------------------|
| `DrawLineEx`   | `rDrawLineEx`      | Thick line between two points     | Confirmed         |
| `DrawLineStrip`| `rDrawLineStrip`   | `Vector2*` array, open path       | **Needs check** ⁴ |

⁴ `DrawLineStrip` may be absent on older vita raylib ports. If missing,
POLYGON and POLYLINE commands fall back to sequential `DrawLineEx` calls (not
yet implemented; log a warning and no-op for now).

### Geometry — triangles

| C symbol            | Nim wrapper           | Notes                        | Vita status |
|---------------------|-----------------------|------------------------------|-------------|
| `DrawTriangle`      | `rDrawTriangle`       | CCW winding (Y-down screen)  | Confirmed   |
| `DrawTriangleLines` | `rDrawTriangleLines`  | CCW winding                  | Confirmed   |

### Geometry — arcs and circles

| C symbol           | Nim wrapper          | Notes                               | Vita status       |
|--------------------|----------------------|-------------------------------------|-------------------|
| `DrawRing`         | `rDrawRing`          | Signature: `(center, innerR, outerR, startDeg, endDeg, segs, color)` | **Needs check** ⁵ |
| `DrawCircleSector` | `rDrawCircleSector`  | Signature: `(center, radius, startDeg, endDeg, segs, color)` | Likely present |

⁵ `DrawRing` may be absent on some vita ports. If missing, NK_COMMAND_ARC falls
back to DrawCircleSector with innerR ignored (filled ring renders as sector).

### Geometry — ellipses (vita NO-OP)

| C symbol          | Nim wrapper          | Vita behavior                         |
|-------------------|----------------------|---------------------------------------|
| `DrawEllipse`     | `rDrawEllipse`       | **No-op discard** (guarded by `when not defined(vita)`) |
| `DrawEllipseLines`| `rDrawEllipseLines`  | **No-op discard** (guarded by `when not defined(vita)`) |

NK_COMMAND_CIRCLE and NK_COMMAND_CIRCLE_FILLED with `w != h` (non-square ellipses)
draw nothing on vita. A one-time `raddyLog` warn is emitted (added in iteration 16).
Fallback options: inscribed circle using `min(rx, ry)`, or polygon tessellation.

### Text

| C symbol      | Nim wrapper   | Notes                                        | Vita status       |
|---------------|---------------|----------------------------------------------|-------------------|
| `rlDrawTextEx`| `rDrawTextEx` | naylib renames `DrawTextEx → rlDrawTextEx`. Vita may use `DrawTextEx`. | **Needs check** ⁶ |

⁶ If vita uses `DrawTextEx` (not `rlDrawTextEx`), add to `raylib_api.nim`:
```nim
when defined(vita):
  proc rDrawTextEx*(font: RFont; text: cstring; pos: RVec2;
                    fontSize, spacing: float32; color: RColor)
      {.importc: "DrawTextEx", header: raylibH, sideEffect.}
```

### Textures

| C symbol         | Nim wrapper         | Notes                  | Vita status |
|------------------|---------------------|------------------------|-------------|
| `DrawTextureRec` | `rDrawTextureRec`   | Sub-region source rect | Likely present |

### Scissor

| C symbol           | Nim wrapper          | Notes | Vita status |
|--------------------|----------------------|-------|-------------|
| `BeginScissorMode` | `rBeginScissorMode`  | `(x, y, w, h: int32)` | Confirmed |
| `EndScissorMode`   | `rEndScissorMode`    |       | Confirmed   |

---

## 2. Input Surface (Anticipated — pumps not yet implemented)

The following symbols are needed by future platform pump modules
(beads **raddy-1vh**: desktop naylib pump, **raddy-hyc**: vita gamepad pump).
They are listed here to inform the vita host-proc surface verification.

These are NOT currently imported by any raddy module.

### Desktop input (naylib / SDL-style)

| Anticipated C symbol        | Purpose                              |
|-----------------------------|--------------------------------------|
| `IsKeyPressed(key)`         | Detect keyboard key-down event       |
| `IsKeyReleased(key)`        | Detect keyboard key-up event         |
| `IsKeyDown(key)`            | Query held key state                 |
| `GetMouseX()`, `GetMouseY()`| Mouse position (absolute)            |
| `IsMouseButtonPressed(btn)` | Mouse button down event              |
| `IsMouseButtonReleased(btn)`| Mouse button up event                |
| `GetMouseWheelMoveV()`      | Scroll delta (Vector2 x/y)           |
| `GetCharPressed()`          | Unicode codepoint from char queue    |

### Vita input (gamepad / touch-style)

| Anticipated C symbol              | Purpose                            |
|-----------------------------------|------------------------------------|
| `IsGamepadButtonPressed(pad, btn)`| Detect vita button press           |
| `IsGamepadButtonReleased(pad, btn)`| Detect vita button release        |
| `IsGamepadButtonDown(pad, btn)`   | Query held vita button             |
| `GetGamepadAxisMovement(pad, ax)` | Analog stick delta                 |
| `GetTouchX()`, `GetTouchY()`      | Touch position (front/rear)        |
| `GetTouchPointCount()`            | Number of active touch points      |

Nuklear mapping for vita gamepad: see bead **raddy-hyc** for the committed
mapping (D-pad → cursor, Cross → click, etc.).

---

## 3. Stub / CI Gate

`tests/stubs/raylib.h` is a minimal C header stub providing all types and
function prototypes from §1. It is used by the vita compile-only gate in
`scripts/verify.sh`:

```bash
nim c --compileOnly --mm:arc --hints:off --path:src -d:vita \
  --passC:"-Itests/stubs" \
  src/raddy/backend/render.nim
```

This gate verifies that:
- The Nim type checker resolves all symbols against the expected C surface
- No backend-only symbol leaks into the decoupled core
- The generated C code compiles against the stub header (syntax-only; no link)

**What this does NOT verify:**
- Symbol naming on the real vita console (see beads raddy-5ce / raddy-tzc)
- Runtime correctness of vita draw calls
- Presence of `DrawRectangleRoundedLinesEx`, `DrawRing`, `DrawLineStrip`
  on the actual vita port (marked "Needs check" above)

---

## 4. Revision History

| Date       | Author        | Change                                       |
|------------|---------------|----------------------------------------------|
| 2026-06-25 | ralph/raddy   | Initial enumeration (iterations 15–16)       |
