# Vita Gamepad → Nuklear Input Model

Nuklear is pointer-centric with no built-in focus traversal. The PS Vita has NO mouse. This file commits to the v1 design for Vita input. Agents must implement this model; do NOT invent an alternative.

## v1 Model: Virtual Cursor

A software cursor position `(cursorX, cursorY): float32` is maintained in the raddy context, guarded with `when defined(vita)` (or always present and conditionally updated).

### Per-Frame Update (before `nk_input_begin`)

1. D-pad and left stick move the cursor:
   ```nim
   cursorX += stickX * CURSOR_SPEED * dt
   cursorY += stickY * CURSOR_SPEED * dt
   ```
   Clamp to screen bounds `[0..screenW, 0..screenH]`.
   - `CURSOR_SPEED = 400.0` (pixels/sec). Not configurable in v1.
   - D-pad: treat as ±1.0 on each axis.

2. Call `nk_input_motion(ctx, int(cursorX), int(cursorY))`.

3. Cross button (`NK_VITA_BTN_CROSS = 14` or `GAMEPAD_BUTTON_RIGHT_FACE_DOWN`):
   ```nim
   nk_input_button(ctx, NK_BUTTON_LEFT, int(cursorX), int(cursorY), pressed)
   ```

4. Circle button: `NK_BUTTON_RIGHT` (for context menus / cancel). Same cursor position.

5. No scroll input in v1 — Vita has no scroll wheel. Scroll widgets are reachable only via the virtual cursor dragging the scrollbar track.

## Widget Reachability

| Widget | Status |
|---|---|
| Buttons, labels, checkboxes, sliders | REACHABLE (cursor + Cross to click) |
| Scrolled groups | REACHABLE (click+drag scrollbar track) |
| Combo dropdowns | REACHABLE (open with Cross, navigate with D-pad+Cross, close with Circle) |
| Popups | REACHABLE |
| Text input (nk_edit) | PARTIAL — opens edit mode with Cross; keyboard input requires on-screen keyboard (out of scope v1); edit fields display but cannot receive text on Vita in v1 |

## Known Limitations (Document, Do Not Fix in v1)

- No keyboard input → text edit fields are display-only on Vita
- No mousewheel → programmatic scroll only (`nk_list_view` or application-side control)
- Cursor rendering is the consumer's responsibility — raddy does NOT draw a cursor sprite
- Focus is wherever the cursor happens to be — no tab/D-pad-only widget traversal

## Input Adapter Files

### Vita (`src/raddy/backend/input_vita.nim`)

```nim
proc pumpVitaInput*(ctx: ptr nk_context; raddyCtx: var RaddyCtx; dt: float32) =
  ## Call each frame before nk_input_begin. Updates virtual cursor and feeds
  ## button state. dt is seconds since last frame (for cursor speed).
```

This proc is `backend/`-only and allowed to import the host's gamepad query API.

### Desktop (`src/raddy/backend/input_naylib.nim`)

```nim
proc pumpNaylibInput*(ctx: ptr nk_context) =
  ## Convenience pump: reads naylib mouse + keyboard each frame.
  ## Call between nk_input_begin and nk_input_end.
```

Uses `isMouseButtonDown`, `getMousePosition`, `getMouseWheelMove`, `isKeyDown`, `getCharPressed` from naylib. Optional — consumers can feed input manually via the raw API instead.
