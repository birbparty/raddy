## pump_naylib.nim — Desktop naylib input → Nuklear pump.
##
## Convenience wrapper that translates one frame of naylib (raylib) input into
## Nuklear's raw feed API. Wraps raddyInputBegin..raddyInputEnd internally —
## do NOT call those separately when using this pump.
##
## MAPPING (desktop, when not defined(vita)):
##   Mouse position      → nk_input_motion every frame
##   Left / Right / Middle button pressed/released → nk_input_button
##   Mouse wheel (vertical) → nk_input_scroll (dy)
##   Shift / Ctrl held   → NK_KEY_SHIFT / NK_KEY_CTRL every frame
##   Nav keys held       → NK_KEY_BACKSPACE, DEL, ENTER, TAB, arrows, Home, End
##   Ctrl+C/X/V/A        → NK_KEY_COPY / CUT / PASTE / TEXT_SELECT_ALL (press-only)
##   GetCharPressed loop → raddyInputUnicode (drains all chars queued this frame)
##
## This module is an OPTIONAL helper. The decoupled core (input.nim) is still
## the only thing that imports Nuklear; hosts may feed raw events directly.
##
## NOTE: unlike pump_vita.nim (which is called BETWEEN begin/end), this pump
## wraps raddyInputBegin and raddyInputEnd internally. The two pumps are NOT
## interchangeable as drop-in replacements for each other.
##
## Desktop-only: guarded so vita builds fail fast on accidental import.

when defined(vita):
  {.error: "pump_naylib.nim is desktop-only — do not import under -d:vita".}

import ../types   ## nk_context, NkButtons, NkKeys
import ../input   ## raddyInputBegin/End/Motion/Button/Key/Scroll/Unicode

# ---------------------------------------------------------------------------
# Raylib constants (match raylib's MouseButton / KeyboardKey enums)
# ---------------------------------------------------------------------------

const raylibH = "raylib.h"

const
  # MouseButton enum ordinals
  MouseLeft   = 0.cint
  MouseRight  = 1.cint
  MouseMiddle = 2.cint

  # KeyboardKey enum ordinals
  KeyEnter    = 257.cint
  KeyTab      = 258.cint
  KeyBackspace= 259.cint
  KeyDelete   = 261.cint
  KeyRight    = 262.cint
  KeyLeft     = 263.cint
  KeyDown     = 264.cint
  KeyUp       = 265.cint
  KeyHome     = 268.cint
  KeyEnd      = 269.cint
  KeyShiftL   = 340.cint
  KeyCtrlL    = 341.cint
  KeyShiftR   = 344.cint
  KeyCtrlR    = 345.cint
  KeyA        = 65.cint
  KeyC        = 67.cint
  KeyV        = 86.cint
  KeyX        = 88.cint

# ---------------------------------------------------------------------------
# Raylib C bindings — mouse, keyboard, scroll
# ---------------------------------------------------------------------------

proc getMouseX(): cint {.importc: "GetMouseX", header: raylibH, sideEffect.}
proc getMouseY(): cint {.importc: "GetMouseY", header: raylibH, sideEffect.}

proc isMouseButtonPressed(button: cint): bool
    {.importc: "IsMouseButtonPressed", header: raylibH, sideEffect.}
proc isMouseButtonReleased(button: cint): bool
    {.importc: "IsMouseButtonReleased", header: raylibH, sideEffect.}

proc getMouseWheelMove(): float32
    {.importc: "GetMouseWheelMove", header: raylibH, sideEffect.}

proc isKeyDown(key: cint): bool
    {.importc: "IsKeyDown", header: raylibH, sideEffect.}
proc isKeyPressed(key: cint): bool
    {.importc: "IsKeyPressed", header: raylibH, sideEffect.}

proc getCharPressed(): cint
    {.importc: "GetCharPressed", header: raylibH, sideEffect.}

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

proc raddyNaylibPump*(ctx: ptr nk_context) {.raises: [].} =
  ## Gather one frame of naylib input and feed it into the Nuklear context.
  ##
  ## Calls raddyInputBegin and raddyInputEnd internally.
  ## Call once per frame before building the Nuklear UI:
  ##
  ##   raddyNaylibPump(ctx)
  ##   # build Nuklear UI here (nk_begin / widgets)
  ##   raddyRender(ctx, canvasH, overflow)

  raddyInputBegin(ctx)

  # -- Mouse position (absolute; fed every frame for widget hit-testing) ----
  let mx = int32(getMouseX())
  let my = int32(getMouseY())
  raddyInputMotion(ctx, mx, my)

  # -- Mouse buttons ---------------------------------------------------------
  if isMouseButtonPressed(MouseLeft):    raddyInputButton(ctx, NK_BUTTON_LEFT,   mx, my, true)
  if isMouseButtonReleased(MouseLeft):   raddyInputButton(ctx, NK_BUTTON_LEFT,   mx, my, false)
  if isMouseButtonPressed(MouseRight):   raddyInputButton(ctx, NK_BUTTON_RIGHT,  mx, my, true)
  if isMouseButtonReleased(MouseRight):  raddyInputButton(ctx, NK_BUTTON_RIGHT,  mx, my, false)
  if isMouseButtonPressed(MouseMiddle):  raddyInputButton(ctx, NK_BUTTON_MIDDLE, mx, my, true)
  if isMouseButtonReleased(MouseMiddle): raddyInputButton(ctx, NK_BUTTON_MIDDLE, mx, my, false)

  # -- Vertical scroll -------------------------------------------------------
  # raylib GetMouseWheelMove: positive = scroll UP (wheel toward user).
  # Nuklear nk_input_scroll: positive dy scrolls content UP. No negation needed.
  let scroll = getMouseWheelMove()
  if scroll != 0.0f32:
    raddyInputScroll(ctx, 0.0f32, scroll)

  # -- Modifier keys (snapshot-fed every frame; Nuklear reads on nk_input_end)
  let ctrl  = isKeyDown(KeyCtrlL)  or isKeyDown(KeyCtrlR)
  let shift = isKeyDown(KeyShiftL) or isKeyDown(KeyShiftR)
  raddyInputKey(ctx, NK_KEY_CTRL,  ctrl)
  raddyInputKey(ctx, NK_KEY_SHIFT, shift)

  # -- Navigation / editing keys (held = repeated every frame) ---------------
  # Nuklear processes each `true` value as one action per frame; there is no
  # built-in key-repeat delay. Hosts wanting OS-style repeat should gate these
  # with IsKeyPressed on the first frame and their own repeat timer after.
  raddyInputKey(ctx, NK_KEY_BACKSPACE,       isKeyDown(KeyBackspace))
  raddyInputKey(ctx, NK_KEY_DEL,             isKeyDown(KeyDelete))
  raddyInputKey(ctx, NK_KEY_ENTER,           isKeyDown(KeyEnter))
  raddyInputKey(ctx, NK_KEY_TAB,             isKeyDown(KeyTab))
  raddyInputKey(ctx, NK_KEY_UP,              isKeyDown(KeyUp))
  raddyInputKey(ctx, NK_KEY_DOWN,            isKeyDown(KeyDown))
  raddyInputKey(ctx, NK_KEY_LEFT,            isKeyDown(KeyLeft))
  raddyInputKey(ctx, NK_KEY_RIGHT,           isKeyDown(KeyRight))
  raddyInputKey(ctx, NK_KEY_TEXT_LINE_START, isKeyDown(KeyHome))
  raddyInputKey(ctx, NK_KEY_TEXT_LINE_END,   isKeyDown(KeyEnd))

  # -- Clipboard shortcuts (single-press-only; Ctrl+C / Ctrl+X / Ctrl+V / Ctrl+A)
  raddyInputKey(ctx, NK_KEY_COPY,        ctrl and isKeyPressed(KeyC))
  raddyInputKey(ctx, NK_KEY_CUT,         ctrl and isKeyPressed(KeyX))
  raddyInputKey(ctx, NK_KEY_PASTE,       ctrl and isKeyPressed(KeyV))
  raddyInputKey(ctx, NK_KEY_TEXT_SELECT_ALL, ctrl and isKeyPressed(KeyA))

  # -- Unicode text input (drain the full GetCharPressed queue this frame) ---
  # GetCharPressed dequeues one codepoint per call; returns 0 when queue empty.
  # Only feed printable codepoints (U+0020+, excluding DEL U+007F) — control
  # codes are already handled as NK_KEY_* events above and must not be fed
  # twice via raddyInputUnicode.
  while true:
    let cp = getCharPressed()
    if cp <= 0: break
    if cp >= 0x20 and cp != 0x7F:
      raddyInputUnicode(ctx, uint32(cp))

  raddyInputEnd(ctx)
