# NK_COMMAND_* Coverage

## Architecture

raddy uses Nuklear's **command-queue API**, not the vertex-buffer API. Each frame, after the UI tree is built, `raddyRender` iterates the command queue using `nk__begin` / `nk__next` and dispatches each `NK_COMMAND_*` record to the corresponding raylib draw call.

```
nk__begin(ctx)
while cmd != nil:
  case cmd.type:
    of NK_COMMAND_RECT:        DrawRectangleLinesEx(...)
    of NK_COMMAND_RECT_FILLED: DrawRectangle(...)
    of NK_COMMAND_TEXT:        DrawTextEx(...)
    # ... etc
  cmd = nk__next(ctx, cmd)
```

## Why command-queue, not vertex-buffer

- **Platform-agnostic dispatch.** `NK_COMMAND_RECT`, `NK_COMMAND_TEXT`, etc. are abstract draw intents. Both naylib (desktop, OpenGL) and raylib_console (PS Vita) expose the same set of raylib draw primitives. The same dispatch table works on both platforms without modification.
- **No geometry shaders or texture atlases required.** Vertex-buffer rendering assumes a shader pipeline and a glyph atlas. raylib_console on Vita does not expose that pipeline. Command-queue sidesteps the requirement entirely.
- **Fits in 64 KiB fixed memory.** The Vita build (`-d:vita` or `-d:raddyFixed`) uses `nk_init_fixed` with a 64 KiB stack buffer. A per-frame vertex buffer would not fit. The command queue is compact: each record is a small tagged struct.
- **Desktop gets the same path.** Desktop defaults to `nk_init_default` (heap), but the render loop is identical. No ifdef, no alternate code path.

## Coverage matrix

| NK_COMMAND | Status | Notes |
|---|---|---|
| NK_COMMAND_NOP | skip | Intentionally ignored. |
| NK_COMMAND_SCISSOR | implemented | Y-flipped (screen coords), replace semantics (not intersect), scissorActive guard to EndScissorMode on deactivation. |
| NK_COMMAND_LINE | implemented | |
| NK_COMMAND_CURVE | implemented | N=20 segments, cubic Bezier, stack-allocated point array. |
| NK_COMMAND_RECT | implemented | Plain + rounded variants. segments=8 for rounded corners. Zero-area guard (skipped if w or h is 0). |
| NK_COMMAND_RECT_FILLED | implemented | Plain + rounded variants. segments=8. Zero-area guard. |
| NK_COMMAND_RECT_MULTI_COLOR | implemented | No-op fallback if the underlying proc is unavailable. |
| NK_COMMAND_CIRCLE | implemented | Outline via DrawEllipseLines. Logged no-op fallback if proc missing. |
| NK_COMMAND_CIRCLE_FILLED | implemented | Filled via DrawEllipse. Logged no-op fallback if proc missing. |
| NK_COMMAND_ARC | implemented | segments=16, converts radians to degrees. Handedness is PROVISIONAL — see note below. |
| NK_COMMAND_ARC_FILLED | implemented | segments=16, converts radians to degrees. Handedness is PROVISIONAL — see note below. |
| NK_COMMAND_TRIANGLE | implemented | Winding check is PROVISIONAL (area > 0 triggers vertex swap). |
| NK_COMMAND_TRIANGLE_FILLED | implemented | Winding check PROVISIONAL. Uses DrawTriangle (not DrawTriangleFilled due to winding). |
| NK_COMMAND_POLYGON | implemented | Edge iteration (DrawLine between consecutive vertices). |
| NK_COMMAND_POLYGON_FILLED | implemented | Fan tessellation from vertex[0]. Convex polygons only. point_count < 3 guard. |
| NK_COMMAND_POLYLINE | implemented | Open polyline via DrawLineStrip. Stack buffer, MaxPolyPts=64. |
| NK_COMMAND_TEXT | implemented | Stack-allocated buffer; font size = `cmd.height`, spacing = `RaddyMeasureSpacing` (2.0). Per-command font read from `cmd.font.userdata.ptr` (nil → skip draw). No Nim string heap allocation. |
| NK_COMMAND_IMAGE | best-effort | Uses RTexture/RColor type aliases. Caller must embed the texture pointer in the nk_image handle. |
| NK_COMMAND_CUSTOM | logged no-op | Logs a warning once per context, then silently skips. Does not crash. |

### NK_COMMAND_TEXT under multi-size font switching

The `fontSize = cmd.height, spacing = 2.0` rule **still holds** after the
multi-size switch API (`setRaddyFont` / `raddyBundleSetFont`). Nuklear stamps the
**active** font and its height into each text command at emit time, so under
switching `cmd.height` simply *varies per command group* instead of being one
global value. The handler stays correct because it reads size and font
**per command**: `cmd.height` for the draw size and `cmd.font.userdata.ptr` for
the `RFont` (skipping the draw when that pointer is nil). Spacing remains the
shared `RaddyMeasureSpacing` constant (2.0) used by both measure and draw — see
`font-contract.md`.

## Popup / combo / tooltip scissor model

Combo dropdowns, `nk_popup`, and tooltips emit **no special command type** — their output is the same 19-element set as any other widget (RECT, RECT_FILLED, TEXT, TRIANGLE_FILLED, SCISSOR, etc.). There is no `NK_COMMAND_POPUP` or `NK_COMMAND_COMBO`. All 19 types are already handled by `raddyRender`.

### Scissor semantics for popups

Nuklear uses a **flat, replace-not-nest** scissor model, which is exactly what raddy implements:

- **Collapsed combo / closed popup**: emits normal per-window scissor rects. Standard path.
- **Open combo dropdown / open popup**: Nuklear pushes `nk_null_rect = {x:-8192, y:-8192, w:16384, h:16384}` so the dropdown can draw outside the parent window's bounds. Nuklear's `nk_push_scissor` applies `NK_MAX(0, w)` / `NK_MAX(0, h)`, so w/h are always non-negative. After the Y-flip (`y' = H - y - h = H - (-8192) - 16384 = H + 8192 - 16384 = H - 8192`), the result is `{x:-8192, y:H-8192, w:16384, h:16384}` — a huge rect with large-negative x and y. OpenGL's `glScissor` (called via `BeginScissorMode → rlScissor → glScissor`) intersects this with the viewport at the driver level; the popup is visible everywhere on screen. On close, Nuklear restores the parent's clip rect with another SCISSOR command. The Y-flip math is verified by static assertions in `src/raddy/backend/scissor.nim`.
- There is **no intersecting/nesting** of scissor regions in Nuklear's command-queue path. Each `NK_COMMAND_SCISSOR` is an absolute replacement. `raddyRender`'s `EndScissorMode` + `BeginScissorMode` pattern is exactly right.

The `nk_null_rect` → `scissorYFlip` math is covered by static assertions in `src/raddy/backend/scissor.nim`.

### v1 scope

| Feature | Status | Notes |
|---|---|---|
| Combo header (collapsed) | **validated** | Covered by `examples/demo.nim` and `tests/test_smoke_headless.nim` |
| Scissor replace semantics | **validated** | Static assertions in `scissor.nim`, including the `nk_null_rect` case |
| Open combo dropdown | **in scope but headless-only** | Open-popup path requires synthetic mouse input across frames; not in smoke test. Visual sign-off deferred to human QA (raddy-bdz). |
| `nk_popup_begin` / `nk_popup_end` | **not wrapped** | No `raddyPopupBegin/End` proc exists in v1. Out of scope; document if needed. |
| Tooltips (`nk_tooltip`) | **not wrapped** | No `raddyTooltip` proc in v1. Out of scope. |

## Provisional items

The following commands are implemented but carry PROVISIONAL notes:

**ARC / ARC_FILLED** — The mapping from Nuklear's arc angles (radians, CCW from +X) to raylib's angle convention (degrees, CW from +X) has not been validated against a ground-truth reference. The current conversion inverts direction and shifts by 90 degrees, but edge cases (angles crossing 0/2π) have not been stress-tested.

**TRIANGLE / TRIANGLE_FILLED** — Nuklear does not guarantee winding order for triangles. The current implementation checks the signed area and swaps two vertices if the area is positive (assuming CCW winding is expected by raylib). This heuristic passes current tests but has not been verified across all Nuklear versions.

For full derivation details and the formulas used, see `docs/prompts/command-matrix.md`.
