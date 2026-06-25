# raddy Vita Input Model

Documents the committed PS Vita gamepad → Nuklear input mapping implemented in
`src/raddy/backend/pump_vita.nim` (bead raddy-hyc).

---

## Committed Mapping

| Hardware input | Raylib constant | Nuklear event |
|---------------|-----------------|---------------|
| D-pad up/down/left/right | `GAMEPAD_BUTTON_LEFT_FACE_*` | `nk_input_motion` (cursor step ±4 px/frame) |
| Left analogue stick | `GAMEPAD_AXIS_LEFT_X/Y` | `nk_input_motion` (scaled by 6 px at full deflection, dead-zone 0.15) |
| Cross (×) — right face down | `GAMEPAD_BUTTON_RIGHT_FACE_DOWN` (ordinal 7) | `nk_input_button(NK_BUTTON_LEFT, ...)` confirm/click |
| Circle (○) — right face right | `GAMEPAD_BUTTON_RIGHT_FACE_RIGHT` (ordinal 6) | `nk_input_button(NK_BUTTON_RIGHT, ...)` cancel/dismiss |
| All others | — | unmapped (handle in app layer if needed) |

### Virtual cursor

`pump_vita.nim` maintains module-level `cursorX, cursorY: int32` (exported;
readable by host). On every frame, cursor displacement is applied from D-pad
and stick before `nk_input_motion` is called. Cursor is clamped to
`[0, canvasW-1] × [0, canvasH-1]` passed by the host.

Use `raddyVitaCursorSet(x, y)` to teleport the cursor (e.g. on scene change).

### Default tuning parameters

| Parameter | Default | Override via |
|-----------|---------|--------------|
| D-pad step | 4 px/frame | `raddyVitaPump(ctx, w, h, dpadStep=N)` |
| Stick scale | 6 px/frame (full deflection) | `raddyVitaPump(ctx, w, h, stickScale=N)` |
| Stick dead-zone | 0.15 (±15 % of axis range) | compile-time const in pump_vita.nim |

---

## Host usage pattern

```nim
when defined(vita):
  import raddy/backend/pump_vita

# Every frame:
raddyInputBegin(ctx)
when defined(vita):
  raddyVitaPump(ctx, canvasW, canvasH)  # gamepad → cursor + buttons
else:
  # desktop: feed mouse/keyboard via raddyInputMotion, raddyInputButton, etc.
raddyInputEnd(ctx)
# build Nuklear UI here, then:
raddyRender(ctx, canvasH, overflow)
```

---

## Widget families reachable

With the virtual cursor and Cross=click mapping, the following Nuklear widget
families are fully reachable on Vita:

| Widget family | Reachable | Notes |
|--------------|-----------|-------|
| Buttons (`nk_button_*`) | ✓ | Move cursor over button, press Cross |
| Checkboxes / toggles | ✓ | Click to toggle |
| Sliders / progress bars | ✓ | Click-drag: press Cross, hold while moving D-pad/stick |
| Scrollable panels (`nk_group_*`) | ✓ | Scroll via D-pad inside a group (NK_BUTTON_LEFT on scrollbar track) |
| Combo boxes (drop-down) | ✓ | Click to open, cursor to select item, click to confirm |
| Context menus | ✓ | Circle (NK_BUTTON_RIGHT) dismisses open popups |
| Property fields (`nk_property*`) | partial¹ | Click increments/decrements; no keyboard text entry |
| Text input (`nk_edit_*`) | partial² | Not reachable without a software keyboard layer |
| Popup windows | ✓ | Cursor + Cross; Circle for dismiss |
| Tree nodes (`nk_tree_*`) | ✓ | Click label/arrow to expand |
| Window drag / resize | ✗ | Requires NK_BUTTON_LEFT hold + motion tracking across frames — technically supported by the pump (held button + stick) but UX is poor; not recommended |

¹ `nk_property` click-drag increments/decrements the value. Direct text entry
requires keyboard; omit from Vita UIs or add a pop-up numeric keyboard.

² Text fields (`nk_edit_string`) require `raddyInputUnicode` / `raddyInputKey`
calls. A software keyboard layer (not implemented) would feed these. For now,
text input is disabled on Vita UI layouts.

---

## Known limitations

1. **No hover state**: Nuklear uses the cursor position for hover — the virtual
   cursor always "hovers" at its current tile. Tooltip or hover-highlight
   behaviours will activate whenever the cursor is over a widget, even if the
   user hasn't moved recently. This is expected Vita UX (no separate pointer
   distinction from physical mouse).

2. **No keyboard text input**: `raddyInputUnicode` and `raddyInputKey` are not
   fed by this pump. Widgets relying on keyboard (`nk_edit_*`, `nk_property`
   direct entry) are unavailable without a separate software keyboard layer
   (planned as a follow-up bead).

3. **Click-drag UX**: Dragging a slider requires holding Cross while moving the
   stick or D-pad. The pump does feed the held-button state correctly, so the
   Nuklear internals handle it, but the UX is awkward. Prefer discrete step
   controls or combo boxes on Vita.

4. **No multi-touch**: Touch input (`GetTouchX`, `GetTouchY`) is not handled
   by this pump. Touch could supplement the gamepad cursor — a follow-up bead
   may add a `raddyVitaTouchPump` once the front/rear touch surface contract
   is defined for topdown and clckr.

5. **Raylib button ordinals**: The pump hardcodes `GAMEPAD_BUTTON_*` ordinals
   matching standard raylib. The vita raylib_console port uses these same
   values (PS Vita hardware maps cleanly onto raylib's GamepadButton enum).
   Verify against the actual `raylib_console.nim` header in bead raddy-tzc.

6. **Cursor wrap / bounds**: Cursor is clamped (not wrapped) at canvas edges.
   A widget at the far edge of a large canvas may require many D-pad taps.
   Hosts can set `dpadStep` higher for larger canvases.

---

## What Circle (cancel) does in Nuklear

`NK_BUTTON_RIGHT` in Nuklear:

- Closes open context menus (if clicked inside the menu area)
- Has no effect on regular widgets — it is not globally "go back"
- Is not connected to window close buttons (those are separate NK_BUTTON_CLOSE logic)

For a "back/cancel" flow, the application layer should check
`nk_input_is_mouse_pressed(&ctx->input, NK_BUTTON_RIGHT)` to implement its
own scene-transition logic, separate from the Nuklear widget system.

---

## Raylib gamepad ordinals reference

| PS Vita button | raylib name | Ordinal |
|----------------|-------------|---------|
| D-pad up | `GAMEPAD_BUTTON_LEFT_FACE_UP` | 1 |
| D-pad right | `GAMEPAD_BUTTON_LEFT_FACE_RIGHT` | 2 |
| D-pad down | `GAMEPAD_BUTTON_LEFT_FACE_DOWN` | 3 |
| D-pad left | `GAMEPAD_BUTTON_LEFT_FACE_LEFT` | 4 |
| Triangle (△) | `GAMEPAD_BUTTON_RIGHT_FACE_UP` | 5 |
| Circle (○) | `GAMEPAD_BUTTON_RIGHT_FACE_RIGHT` | 6 |
| Cross (×) | `GAMEPAD_BUTTON_RIGHT_FACE_DOWN` | 7 |
| Square (□) | `GAMEPAD_BUTTON_RIGHT_FACE_LEFT` | 8 |
| L (shoulder) | `GAMEPAD_BUTTON_LEFT_TRIGGER_1` | 9 |
| R (shoulder) | `GAMEPAD_BUTTON_RIGHT_TRIGGER_1` | 10 |

| PS Vita axis | raylib name | Ordinal |
|-------------|-------------|---------|
| Left stick X | `GAMEPAD_AXIS_LEFT_X` | 0 |
| Left stick Y | `GAMEPAD_AXIS_LEFT_Y` | 1 |
| Right stick X | `GAMEPAD_AXIS_RIGHT_X` | 2 |
| Right stick Y | `GAMEPAD_AXIS_RIGHT_Y` | 3 |

---

## Revision History

| Date | Bead | Change |
|------|------|--------|
| 2026-06-25 | raddy-hyc | Initial vita gamepad model and pump implementation |
