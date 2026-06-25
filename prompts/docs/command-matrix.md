# raddy NK_COMMAND_* Coverage Matrix

This document maps every Nuklear command type to its raddy renderer implementation
in `src/raddy/backend/render.nim` (as of iteration 17). It documents the dispatch
strategy, known approximations, vita-specific behavior, and testability classification
for each command.

All 19 command types are handled — no `else:` branch exists in the dispatch.
`static: doAssert ord(NK_COMMAND_CUSTOM) == 18` is a compile-time tripwire
that fires if nuklear.h adds a new type.

---

## Legend

| Column | Meaning |
|--------|---------|
| **raylib call(s)** | Host draw-proc(s) invoked by the handler |
| **Approximation** | Semantic gap between Nuklear's intent and the raylib output |
| **Vita status** | `✓` = confirmed present, `?` = needs raddy-tzc check, `no-op` = disabled |
| **Testable core** | Whether the handler's logic is exercisable without a display |

---

## 1. Control / Meta Commands

| # | NK_COMMAND | raylib call(s) | Notes | Vita | Testable |
|---|-----------|----------------|-------|------|----------|
| 0 | `NOP` | — | `discard` | ✓ | yes |
| 1 | `SCISSOR` | `BeginScissorMode` `EndScissorMode` | Y-flip applied: `y' = framebufferH - y - h` (RenderTexture FBO is bottom-up). Replace semantics: closes current region before opening the new one. | ✓ | yes¹ |

¹ `scissorYFlip` in `scissor.nim` is a pure function; the replace logic is visual.

---

## 2. Lines and Curves

| # | NK_COMMAND | raylib call(s) | Notes | Vita | Testable |
|---|-----------|----------------|-------|------|----------|
| 2 | `LINE` | `DrawLineEx` | Single thick line between two points. | ✓ | visual |
| 3 | `CURVE` | `DrawLineStrip` or `DrawLineEx` | Cubic Bézier tessellated into `BezierSegs=20` segments on the stack. `thickness ≤ 1` → `DrawLineStrip` (fast); `thickness > 1` → per-segment `DrawLineEx` (correct thickness). | `?` (DrawLineStrip) | yes² |

² `bezierTessellate` in `geom.nim` is a pure function producing an `array[BezierSegs+1, RVec2]`.

---

## 3. Rectangles

| # | NK_COMMAND | raylib call(s) | Notes | Vita | Testable |
|---|-----------|----------------|-------|------|----------|
| 4 | `RECT` | `DrawRectangleLinesEx` / `DrawRectangleRoundedLinesEx` | `rounding==0` → sharp corners; else rounded with `rectRoundness()`. Zero-extent rounded rects are skipped (protects divisor in `rectRoundness`). | `✓` / `?`³ | visual |
| 5 | `RECT_FILLED` | `DrawRectangleRec` / `DrawRectangleRounded` | Same rounding branch as `RECT`. | `✓` / likely | visual |
| 6 | `RECT_MULTI_COLOR` | `DrawRectangleGradientEx` | **Approximation**: Nuklear provides per-edge colors (`left`, `top`, `bottom`, `right`); raylib takes per-corner colors. Mapping: `topLeft=left`, `bottomLeft=bottom`, `bottomRight=right`, `topRight=top`. A 2×2 bi-linear blend is not achievable in command mode (no vertex data). Zero-extent skipped. | `?`⁴ | visual |

³ `DrawRectangleRoundedLinesEx` added in raylib 4.5; verify vita port version.
⁴ Corner-color parameter order may differ on some vita ports; verify against console `raylib.h`.

---

## 4. Circles and Ellipses

| # | NK_COMMAND | raylib call(s) | Notes | Vita | Testable |
|---|-----------|----------------|-------|------|----------|
| 7 | `CIRCLE` | `DrawRing` (circle) / `DrawEllipseLines` (ellipse) | `w==h` → true circle using `DrawRing` (innerR respects `line_thickness`). `w!=h` → ellipse outline via `DrawEllipseLines`; **no-op on vita** (guarded in `raylib_api.nim`). One-time log warn emitted on vita. | circle: `?` (DrawRing) / ellipse: **no-op** | visual |
| 8 | `CIRCLE_FILLED` | `DrawCircleSector` (circle) / `DrawEllipse` (ellipse) | `w==h` → `DrawCircleSector` with 0–360°. `w!=h` → `DrawEllipse`; **no-op on vita**. | circle: likely / ellipse: **no-op** | visual |

---

## 5. Arcs

| # | NK_COMMAND | raylib call(s) | Notes | Vita | Testable |
|---|-----------|----------------|-------|------|----------|
| 9 | `ARC` | `DrawRing` | Nuklear arc angles are absolute radians CCW+. raylib uses degrees CW+ in Y-down screen. The Y-flip and CW sign cancel, so NO negation is applied. `innerR = max(0, outerR - line_thickness)`. Angle normalization: if `endAngle < startAngle`, add 360° (Nuklear does not guarantee ordering). | `?` (DrawRing) | yes⁵ |
| 10 | `ARC_FILLED` | `DrawCircleSector` | Same angle conversion and normalization as `ARC`. No thickness concept (sector = filled). | likely | yes⁵ |

⁵ `radToDeg` and angle normalization logic are pure; the angle cancellation reasoning
is documented inline at `render.nim:249–255`.

---

## 6. Triangles

| # | NK_COMMAND | raylib call(s) | Notes | Vita | Testable |
|---|-----------|----------------|-------|------|----------|
| 11 | `TRIANGLE` | `DrawTriangleLines` | `fixTriWinding` from `geom.nim` ensures CCW winding for raylib's Y-down convention. | ✓ | yes⁶ |
| 12 | `TRIANGLE_FILLED` | `DrawTriangle` | Same winding fix as `TRIANGLE`. | ✓ | yes⁶ |

⁶ `fixTriWinding` is a pure function testable without a display.

---

## 7. Polygons and Polylines

All three polygon handlers share a single truncation latch (`polyTruncWarnEmitted`):
the first polygon/polyline family truncation in the process emits one log message,
then silences. This avoids log spam in animation loops.

Points are accessed via FAM (Flexible Array Member) cast:
`cast[ptr UncheckedArray[nk_vec2i]](addr cmd.points[0])`.

| # | NK_COMMAND | raylib call(s) | Notes | Vita | Testable |
|---|-----------|----------------|-------|------|----------|
| 13 | `POLYGON` | `DrawLineStrip` (closed) | Stack buffer capped at `PolyLineMax=64` points. Closing: first point appended to the array → `point_count+1` passed to `DrawLineStrip`. Min 2 points required. | `?` | visual |
| 14 | `POLYGON_FILLED` | `DrawTriangle` × N | Fan triangulation from vertex 0: triangles `(0,i,i+1)` for `i` in `1..count-2`. **Valid only for convex polygons** — concave inputs draw a wrong shape. Nuklear's widget layer always emits convex polygons. Stack cap `PolyLineMax`. Min 3 points required. | ✓ | yes⁷ |
| 15 | `POLYLINE` | `DrawLineStrip` (open) | Same stack cap as `POLYGON`. Open path: no loop closure. Min 2 points required. | `?` | visual |

⁷ Fan triangulation point arithmetic is exercisable without a display (see `fixTriWinding`
calls which produce deterministic outputs).

---

## 8. Text

| # | NK_COMMAND | raylib call(s) | Notes | Vita | Testable |
|---|-----------|----------------|-------|------|----------|
| 16 | `TEXT` | `DrawTextEx` (via `rlDrawTextEx`) | Text is NOT null-terminated in the command — `copyMem` + manual null terminator into a stack buffer (`RaddyMaxTextBytes=1024`). Font nil-checked (`nk_user_font.userdata.ptr` holds the `ptr RFont` set by `raddyInitFont`). Oversize payloads truncated to 1023 bytes with a one-time log. UTF-8 truncation at an arbitrary byte can split multi-byte codepoints (i18n follow-up). `tc.background` is intentionally ignored — Nuklear pre-fills it as a `RECT_FILLED` command. | `?` (naming: rlDrawTextEx / DrawTextEx) | yes⁸ |

⁸ The copyMem+null-termination logic and font nil-guard are testable in `tests/test_render.nim`.

---

## 9. Image

| # | NK_COMMAND | raylib call(s) | Notes | Vita | Testable |
|---|-----------|----------------|-------|------|----------|
| 17 | `IMAGE` | `DrawTextureRec` | `nk_image.handle.ptr` must hold a `ptr RTexture` (integer handle `handle.id` is not supported). `region[0..3]` = `[x, y, w, h]` sub-rectangle; zero `w` or `h` falls back to full texture dimension. texPtr nil-checked. | likely | yes⁸ |

---

## 10. Custom

| # | NK_COMMAND | raylib call(s) | Notes | Vita | Testable |
|---|-----------|----------------|-------|------|----------|
| 18 | `CUSTOM` | — | `discard`. Nuklear custom commands carry a C function pointer for host-provided drawing. raddy does not invoke it — the host handles custom rendering outside `raddyRender`. | ✓ | yes |

---

## Summary

| Category | Commands | Desktop | Vita |
|----------|----------|---------|------|
| Implemented, full fidelity | NOP, SCISSOR, LINE, RECT, RECT_FILLED, TRIANGLE, TRIANGLE_FILLED, POLYLINE, TEXT, IMAGE, CUSTOM | ✓ | ✓ or ? |
| Implemented with approximation | CURVE (tessellated Bézier), RECT_MULTI_COLOR (edge→corner), POLYGON_FILLED (fan, convex-only) | ✓ | ? |
| Implemented, vita partial | CIRCLE/CIRCLE_FILLED (ellipse branch is no-op), ARC/ARC_FILLED (DrawRing needs check), POLYGON (DrawLineStrip needs check) | ✓ | see above |
| Intentional no-op | — | — | — |

### Constants referenced

| Constant | Value | Location | Purpose |
|----------|-------|----------|---------|
| `BezierSegs` | 20 | `geom.nim` | Bézier tessellation subdivisions |
| `ArcSegs` | 16 | `geom.nim` | Arc/circle tessellation segments |
| `RoundedRectSegs` | 8 | `geom.nim` | Rounded rect corner segments |
| `PolyLineMax` | 64 | `geom.nim` | Stack cap for polygon/polyline point arrays |
| `RaddyMaxTextBytes` | 1024 | `font.nim` | Stack buffer for NK_COMMAND_TEXT payloads |
| `nkCmdCount` | 19 | `render.nim` | Sentinel checked by `doAssert` tripwire |

### Known degradations (documented, not bugs)

1. **`RECT_MULTI_COLOR`**: edge-to-corner color mapping is an approximation. Exact
   vertex-mode gradient requires the vertex buffer path (`nk_convert`), which is
   not compiled in raddy.
2. **`POLYGON_FILLED`**: fan triangulation is correct only for convex polygons.
   Nuklear's widget layer never emits concave polygons, so this is safe.
3. **`TEXT` UTF-8 truncation**: truncating at 1023 bytes may split a multi-byte
   codepoint. Correct truncation at a codepoint boundary is planned for the i18n pass.
4. **Vita ellipse no-op**: `DrawEllipse` / `DrawEllipseLines` are absent on the vita
   raylib_console port. Non-square CIRCLE / CIRCLE_FILLED commands draw nothing.
   A one-time `raddyLog` warn is emitted per process.
5. **`IMAGE` integer handle**: `nk_image.handle.id` (integer texture IDs) are not
   mapped. Only `handle.ptr` (direct `ptr RTexture`) is supported.

---

## Revision History

| Date       | Iteration | Change |
|------------|-----------|--------|
| 2026-06-25 | 17        | Initial coverage matrix (all 19 commands) |
