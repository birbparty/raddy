## input.nim — Nuklear input-feed API (decoupled core).
##
## Binds nk_input_begin / nk_input_end and the five raw event feeders:
##   raddyInputMotion, raddyInputButton, raddyInputKey,
##   raddyInputScroll, raddyInputUnicode.
##
## Text input: raddyInputUnicode (UTF-32) is the only sanctioned path.
## nk_input_char (single byte) and nk_input_glyph (UTF-8 multi-byte) are
## intentionally not bound — they share the same NK_INPUT_MAX buffer and
## raddyInputUnicode covers all Unicode planes for both desktop and Vita.
##
## This module is decoupled-core: it MUST NOT import naylib, raylib_console,
## inputty, or any backend/ module. Platform input pumps (naylib / vita) that
## translate device events into these calls live under src/raddy/backend/.
##
## Usage pattern (every frame):
##   raddyInputBegin(ctx)
##   raddyInputMotion(ctx, mouseX, mouseY)         ## current cursor pos
##   raddyInputButton(ctx, NK_BUTTON_LEFT, mx, my, pressed)
##   raddyInputKey(ctx, NK_KEY_CTRL, held)
##   raddyInputScroll(ctx, 0.0, scrollDelta)
##   raddyInputUnicode(ctx, codepoint)             ## for text-entry events
##   raddyInputEnd(ctx)
##   ## build layout here, then call raddyRender

import ./types   ## nk_context, NkButtons, NkKeys, nk_bool, nk_vec2, nk_rune

const nkH = "nuklear.h"

# ---------------------------------------------------------------------------
# Raw C FFI bindings
# All are sideEffect: each call mutates nk_context's internal input state.
# Raw begin/end are private — callers use raddyInputBegin/raddyInputEnd.
# ---------------------------------------------------------------------------

proc nk_input_begin(ctx: ptr nk_context)
    {.importc: "nk_input_begin", header: nkH, sideEffect.}
  ## Marks the start of the input-gathering phase. MUST be called before any
  ## nk_input_* event feeder and MUST be matched by nk_input_end.

proc nk_input_end(ctx: ptr nk_context)
    {.importc: "nk_input_end", header: nkH, sideEffect.}
  ## Marks the end of the input-gathering phase. After this, the layout API
  ## (nk_begin / widgets) reads the snapshotted input state.

proc nk_input_motion(ctx: ptr nk_context; x, y: cint)
    {.importc: "nk_input_motion", header: nkH, sideEffect.}

proc nk_input_button(ctx: ptr nk_context; id: NkButtons; x, y: cint; down: nk_bool)
    {.importc: "nk_input_button", header: nkH, sideEffect.}

proc nk_input_key(ctx: ptr nk_context; key: NkKeys; down: nk_bool)
    {.importc: "nk_input_key", header: nkH, sideEffect.}

proc nk_input_scroll(ctx: ptr nk_context; val: nk_vec2)
    {.importc: "nk_input_scroll", header: nkH, sideEffect.}

proc nk_input_unicode(ctx: ptr nk_context; codepoint: nk_rune)
    {.importc: "nk_input_unicode", header: nkH, sideEffect.}

# ---------------------------------------------------------------------------
# Nim wrappers — exported, type-safe, raises-free
# ---------------------------------------------------------------------------

proc raddyInputBegin*(ctx: ptr nk_context) {.inline, raises: [].} =
  ## Open an input-gathering frame. Must be matched by raddyInputEnd.
  ## Call once per frame before feeding any input events.
  nk_input_begin(ctx)

proc raddyInputEnd*(ctx: ptr nk_context) {.inline, raises: [].} =
  ## Close the input-gathering frame. Call once per frame after all events.
  ## After this, build the UI layout (nk_begin / widgets), then raddyRender.
  nk_input_end(ctx)

proc raddyInputMotion*(ctx: ptr nk_context; x, y: int32) {.inline, raises: [].} =
  ## Feed the current pointer/cursor position in GUI canvas pixels.
  ## Call every frame with the current position, even if the cursor did not move
  ## — Nuklear uses the position to hit-test widgets.
  nk_input_motion(ctx, cint(x), cint(y))

proc raddyInputButton*(ctx: ptr nk_context; id: NkButtons;
                       x, y: int32; down: bool) {.inline, raises: [].} =
  ## Feed a mouse (or mapped gamepad) button state change.
  ## x, y: pointer position at the moment of the button event.
  ## down: true when the button transitions to pressed, false on release.
  ## NK_BUTTON_MAX is a sentinel (= array length), not a valid button —
  ## passing it writes one past the end of nk_context.mouse.buttons[].
  assert id != NK_BUTTON_MAX, "raddyInputButton: NK_BUTTON_MAX is a sentinel, not a valid button"
  nk_input_button(ctx, id, cint(x), cint(y), nk_bool(down))

proc raddyInputKey*(ctx: ptr nk_context; key: NkKeys;
                    down: bool) {.inline, raises: [].} =
  ## Feed a keyboard key state change.
  ## down: true when the key transitions to pressed, false on release.
  ## Modifier keys (NK_KEY_SHIFT, NK_KEY_CTRL, NK_KEY_ALT) are fed separately
  ## — call this for each modifier whenever its state changes.
  ## NK_KEY_MAX is a sentinel (= array length), not a valid key —
  ## passing it writes one past the end of nk_context.keyboard.keys[].
  assert key != NK_KEY_MAX, "raddyInputKey: NK_KEY_MAX is a sentinel, not a valid key"
  nk_input_key(ctx, key, nk_bool(down))

proc raddyInputScroll*(ctx: ptr nk_context; dx, dy: float32) {.inline, raises: [].} =
  ## Feed a scroll delta in GUI canvas units.
  ## dy is the primary axis (vertical scroll); dx is horizontal.
  ## A typical mouse wheel step is dy = ±1.0.
  ## Scroll accumulates (+=) within a begin/end frame and is zeroed only by a
  ## consuming scrollbar — unlike raddyInputMotion which sets absolute position.
  ## Do not call with nonzero dy on every frame expecting last-write-wins.
  nk_input_scroll(ctx, nk_vec2(x: dx, y: dy))

proc raddyInputUnicode*(ctx: ptr nk_context; codepoint: uint32) {.inline, raises: [].} =
  ## Feed a Unicode text input event. codepoint is a UTF-32 code unit.
  ## Only feed printable codepoints (U+0020 and above) — control characters
  ## (newline, tab, backspace) are fed as NK_KEY_* events via raddyInputKey.
  ## Per-frame cap: Nuklear's text buffer holds NK_INPUT_MAX (~16) bytes.
  ## Excess codepoints in a single begin/end frame are silently dropped.
  ## For IME commits or large pastes, spread codepoints across frames.
  nk_input_unicode(ctx, nk_rune(codepoint))
