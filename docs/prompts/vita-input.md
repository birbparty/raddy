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
   - `CURSOR_SPEED = 400.0` (pixels/sec). Not configurable in v1.
   - D-pad: treat as ±1.0 on each axis.
   - **Cursor bounds** — clamp to the Nuklear UI's coordinate space, NOT the physical screen:
     - topdown path: `[0..320, 0..180]` (the 320×180 RenderTexture)
     - clckr path: `[0..GetScreenWidth(), 0..GetScreenHeight()]` (native resolution)
   - `nk_input_motion` coordinates must match the UI coordinate space. If you clamp to the
     physical screen but Nuklear's panels live in 320×180 texture space, clicks will miss.

2. Call `nk_input_motion(ctx, int(cursorX), int(cursorY))`.

3. Cross button — use the **raylib console canonical constant** `GAMEPAD_BUTTON_RIGHT_FACE_DOWN`
   (or its naylib equivalent). Do NOT use the bare magic number `14` — it is the raw HID
   value and may differ across SDK versions. If the console binding only exposes raw codes,
   document the pinned value as `VITA_CROSS_RAW = 14` with a comment referencing the SDK.
   ```nim
   let pressed = isGamepadButtonDown(0, GAMEPAD_BUTTON_RIGHT_FACE_DOWN)
   nk_input_button(ctx, NK_BUTTON_LEFT, int(cursorX), int(cursorY), pressed.nk_bool)
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
  ## Call each frame between nk_input_begin and nk_input_end. Updates virtual cursor and feeds
  ## button state into Nuklear. dt is seconds since last frame (for cursor speed).
```

This proc is `backend/`-only and allowed to import the host's gamepad query API.

### Desktop (`src/raddy/backend/input_naylib.nim`)

```nim
proc pumpNaylibInput*(ctx: ptr nk_context) =
  ## Convenience pump: reads naylib mouse + keyboard each frame.
  ## Call between nk_input_begin and nk_input_end.
```

Uses `isMouseButtonDown`, `getMousePosition`, `getMouseWheelMove`, `isKeyDown`, `getCharPressed` from naylib. Optional — consumers can feed input manually via the raw API instead.
