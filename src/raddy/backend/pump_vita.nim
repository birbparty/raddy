## pump_vita.nim — PS Vita gamepad → Nuklear input pump.
##
## Translates PS Vita hardware input into the raddy decoupled input API
## (input.nim). Maintains a virtual cursor driven by the left analogue stick
## and the D-pad; maps face buttons to Nuklear mouse events.
##
## COMMITTED MAPPING (raddy-hyc):
##   D-pad / left-stick → virtual cursor position
##   Cross  (right face down) → NK_BUTTON_LEFT  (confirm / click)
##   Circle (right face right)→ NK_BUTTON_RIGHT (cancel / dismiss popup)
##   Others → unmapped in this pump layer; handle above the pump if needed.
##
## Typical host usage (every frame):
##   raddyInputBegin(ctx)
##   raddyVitaPump(ctx, canvasW, canvasH)
##   raddyInputEnd(ctx)
##   # build Nuklear UI here
##   raddyRender(ctx, canvasH, overflow)
##
## Compilation guard: this file must not be imported on desktop builds.

when not defined(vita):
  {.error: "pump_vita.nim is Vita-only — import only under -d:vita".}

import std/math   ## round (float32 → int32 without truncation bias)
import ../types   ## nk_context, NkButtons
import ../input   ## raddyInputMotion, raddyInputButton

# ---------------------------------------------------------------------------
# Raylib gamepad constants (match raylib's GamepadButton / GamepadAxis enums)
# ---------------------------------------------------------------------------

const raylibH = "raylib.h"

const
  VPad = 0.cint  ## gamepad index (PS Vita has one controller)

  # GamepadButton ordinals
  BtnDpadUp    = 1.cint
  BtnDpadRight = 2.cint
  BtnDpadDown  = 3.cint
  BtnDpadLeft  = 4.cint
  BtnCross     = 7.cint  ## right-face-down (Cross = confirm)
  BtnCircle    = 6.cint  ## right-face-right (Circle = cancel)

  # GamepadAxis ordinals
  AxisLX = 0.cint
  AxisLY = 1.cint

  # Dead-zone for analogue stick (0..1 scale)
  StickDeadzone = 0.15f32

# ---------------------------------------------------------------------------
# Raylib C bindings — gamepad query procs
# ---------------------------------------------------------------------------

proc isGamepadButtonDown(gamepad, button: cint): bool
    {.importc: "IsGamepadButtonDown", header: raylibH, sideEffect.}

proc isGamepadButtonPressed(gamepad, button: cint): bool
    {.importc: "IsGamepadButtonPressed", header: raylibH, sideEffect.}

proc isGamepadButtonReleased(gamepad, button: cint): bool
    {.importc: "IsGamepadButtonReleased", header: raylibH, sideEffect.}

proc getGamepadAxisMovement(gamepad, axis: cint): float32
    {.importc: "GetGamepadAxisMovement", header: raylibH, sideEffect.}

# ---------------------------------------------------------------------------
# Pump state — virtual cursor position (module-level; one pump per process)
# ---------------------------------------------------------------------------

var
  cursorX* = 0'i32  ## current virtual cursor X (canvas pixels); host may read
  cursorY* = 0'i32  ## current virtual cursor Y (canvas pixels); host may read

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

proc raddyVitaPump*(ctx: ptr nk_context; canvasW, canvasH: int32;
                    dpadStep: int32 = 4; stickScale: float32 = 6.0f32) {.raises: [].} =
  ## Feed PS Vita gamepad events into the Nuklear input queue.
  ##
  ## Call between raddyInputBegin and raddyInputEnd, once per frame.
  ##
  ## Parameters:
  ##   dpadStep   — cursor pixels moved per frame when a D-pad direction is held
  ##   stickScale — max cursor pixels moved per frame at full stick deflection
  ##
  ## The cursor is clamped to [0, canvasW-1] × [0, canvasH-1].
  if canvasW <= 0 or canvasH <= 0: return

  # -- Cursor movement: D-pad (digital) -------------------------------------
  if isGamepadButtonDown(VPad, BtnDpadLeft):  cursorX = max(0'i32, cursorX - dpadStep)
  if isGamepadButtonDown(VPad, BtnDpadRight): cursorX = min(canvasW - 1, cursorX + dpadStep)
  if isGamepadButtonDown(VPad, BtnDpadUp):    cursorY = max(0'i32, cursorY - dpadStep)
  if isGamepadButtonDown(VPad, BtnDpadDown):  cursorY = min(canvasH - 1, cursorY + dpadStep)

  # -- Cursor movement: left analogue stick (analogue, with dead-zone) ------
  let ax = getGamepadAxisMovement(VPad, AxisLX)
  let ay = getGamepadAxisMovement(VPad, AxisLY)
  if abs(ax) > StickDeadzone:
    cursorX = clamp(cursorX + int32(round(ax * stickScale)), 0'i32, canvasW - 1)
  if abs(ay) > StickDeadzone:
    cursorY = clamp(cursorY + int32(round(ay * stickScale)), 0'i32, canvasH - 1)

  # Feed updated cursor position every frame (Nuklear needs it for hit-tests)
  raddyInputMotion(ctx, cursorX, cursorY)

  # -- Cross (confirm) → NK_BUTTON_LEFT -------------------------------------
  if isGamepadButtonPressed(VPad, BtnCross):
    raddyInputButton(ctx, NK_BUTTON_LEFT, cursorX, cursorY, true)
  if isGamepadButtonReleased(VPad, BtnCross):
    raddyInputButton(ctx, NK_BUTTON_LEFT, cursorX, cursorY, false)

  # -- Circle (cancel) → NK_BUTTON_RIGHT ------------------------------------
  ## NK_BUTTON_RIGHT in Nuklear dismisses context menus and popup overlays —
  ## the closest semantic match to a "cancel/back" face button.
  if isGamepadButtonPressed(VPad, BtnCircle):
    raddyInputButton(ctx, NK_BUTTON_RIGHT, cursorX, cursorY, true)
  if isGamepadButtonReleased(VPad, BtnCircle):
    raddyInputButton(ctx, NK_BUTTON_RIGHT, cursorX, cursorY, false)

proc raddyVitaCursorSet*(x, y: int32) {.inline, raises: [].} =
  ## Override the virtual cursor position (e.g. reset on scene change).
  cursorX = x
  cursorY = y
