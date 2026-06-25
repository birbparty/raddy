## widgets.nim — Nuklear widget family bindings.
##
## Idiomatic Nim wrappers over the core Nuklear widget procs needed for
## game UI overlays and demos. All are thin pass-throughs to C.
##
## Window lifecycle:
##   raddyBegin / raddyEnd
##
## Widgets (call inside raddyBegin/raddyEnd):
##   raddyLabel         — static text (alignment via NK_TEXT_LEFT/CENTERED/RIGHT)
##   raddyButton        — clickable button, returns true on click
##   raddyCheckbox      — labeled checkbox, toggles bool, returns true if changed
##   raddySlider        — float slider between min..max
##   raddyEdit          — single-line text input (see NkEditEvents return)
##   raddyCombo         — dropdown item selector, returns selected index
##   raddyProperty     — numeric property with +/- buttons
##
## Text-edit filter procs (pass to raddyEdit):
##   nkFilterDefault / nkFilterAscii / nkFilterFloat / nkFilterDecimal
##
## Decoupled-core rule: MUST NOT import naylib, raylib_console, inputty, or
## any game-specific module.

import ./types   ## nk_context, nk_bool, nk_flags, nk_rect, nk_vec2, nk_rune
import ./layout  ## NkWindowFlags (nk_panel_flags), NkLayoutFormat
import ./vendor  ## side-effect: compile nuklear_impl.c; inject nk_config.h

export NkWindowFlags  ## re-export so callers import widgets only

{.push raises: [].}

const nkH = "nuklear.h"

# ---------------------------------------------------------------------------
# Additional enums
# ---------------------------------------------------------------------------

type
  NkEditFlags* {.importc: "enum nk_edit_flags", header: nkH,
                  size: sizeof(cint).} = enum
    ## Individual nk_edit flags (combine with `or`).
    NK_EDIT_READ_ONLY          = 1 shl 0
    NK_EDIT_AUTO_SELECT        = 1 shl 1
    NK_EDIT_SIG_ENTER          = 1 shl 2
    NK_EDIT_ALLOW_TAB          = 1 shl 3
    NK_EDIT_NO_CURSOR          = 1 shl 4
    NK_EDIT_SELECTABLE         = 1 shl 5
    NK_EDIT_CLIPBOARD          = 1 shl 6
    NK_EDIT_CTRL_ENTER_NEWLINE = 1 shl 7
    NK_EDIT_NO_HORIZONTAL_SCROLL = 1 shl 8
    NK_EDIT_ALWAYS_INSERT_MODE = 1 shl 9
    NK_EDIT_MULTILINE          = 1 shl 10
    NK_EDIT_GOTO_END_ON_ACTIVATE = 1 shl 11

  NkEditEvents* {.importc: "enum nk_edit_events", header: nkH,
                   size: sizeof(cint).} = enum
    ## Bit flags returned by raddyEdit indicating what happened this frame.
    NK_EDIT_ACTIVE      = 1 shl 0  ## widget is being edited
    NK_EDIT_INACTIVE    = 1 shl 1  ## widget is not active
    NK_EDIT_ACTIVATED   = 1 shl 2  ## transitioned inactive → active this frame
    NK_EDIT_DEACTIVATED = 1 shl 3  ## transitioned active → inactive this frame
    NK_EDIT_COMMITTED   = 1 shl 4  ## Enter pressed; user committed the edit

# ---------------------------------------------------------------------------
# nk_plugin_filter type alias
# ---------------------------------------------------------------------------

type NkPluginFilter* = proc(edit: pointer; unicode: nk_rune): nk_bool {.cdecl.}
  ## Text-input filter callback. Pass nil to accept any character.
  ## Use the nkFilter* procs below for the built-in Nuklear filters.

# ---------------------------------------------------------------------------
# Raw C FFI bindings (private)
# ---------------------------------------------------------------------------

proc nk_begin(ctx: ptr nk_context; title: cstring; bounds: nk_rect;
              flags: nk_flags): nk_bool
    {.importc: "nk_begin", header: nkH, sideEffect.}

proc nk_end(ctx: ptr nk_context)
    {.importc: "nk_end", header: nkH, sideEffect.}

proc nk_label(ctx: ptr nk_context; str: cstring; align: nk_flags)
    {.importc: "nk_label", header: nkH, sideEffect.}

proc nk_button_label(ctx: ptr nk_context; title: cstring): nk_bool
    {.importc: "nk_button_label", header: nkH, sideEffect.}

proc nk_checkbox_label(ctx: ptr nk_context; label: cstring; active: ptr nk_bool): nk_bool
    {.importc: "nk_checkbox_label", header: nkH, sideEffect.}

proc nk_slider_float(ctx: ptr nk_context; minVal: float32; val: ptr float32;
                     maxVal: float32; step: float32): nk_bool
    {.importc: "nk_slider_float", header: nkH, sideEffect.}

proc nk_edit_string(ctx: ptr nk_context; flags: nk_flags; buffer: cstring;
                    len: ptr cint; maxLen: cint; filter: NkPluginFilter): nk_flags
    {.importc: "nk_edit_string", header: nkH, sideEffect.}

proc nk_combo(ctx: ptr nk_context; items: ptr cstring; count: cint;
              selected: cint; itemHeight: cint; size: nk_vec2): cint
    {.importc: "nk_combo", header: nkH, sideEffect.}

proc nk_property_float(ctx: ptr nk_context; name: cstring; minVal: float32;
                        val: ptr float32; maxVal: float32; step: float32;
                        incPerPixel: float32)
    {.importc: "nk_property_float", header: nkH, sideEffect.}

# Built-in filter procs — cdecl, match NkPluginFilter signature
proc nk_filter_default(edit: pointer; unicode: nk_rune): nk_bool
    {.importc: "nk_filter_default", header: nkH, cdecl.}
proc nk_filter_ascii(edit: pointer; unicode: nk_rune): nk_bool
    {.importc: "nk_filter_ascii", header: nkH, cdecl.}
proc nk_filter_float(edit: pointer; unicode: nk_rune): nk_bool
    {.importc: "nk_filter_float", header: nkH, cdecl.}
proc nk_filter_decimal(edit: pointer; unicode: nk_rune): nk_bool
    {.importc: "nk_filter_decimal", header: nkH, cdecl.}

# ---------------------------------------------------------------------------
# Convenience NK_EDIT_* flag constants (as nk_flags)
# ---------------------------------------------------------------------------

const
  NK_EDIT_SIMPLE_FLAGS*: nk_flags = 1 shl 9          ## NK_EDIT_ALWAYS_INSERT_MODE
  NK_EDIT_FIELD_FLAGS*: nk_flags  = (1 shl 9) or     ## NK_EDIT_SIMPLE | SELECTABLE | CLIPBOARD
                                     (1 shl 5) or
                                     (1 shl 6)

# ---------------------------------------------------------------------------
# Public filter proc accessors (avoid exposing raw pointer equality)
# ---------------------------------------------------------------------------

proc nkFilterDefault*(): NkPluginFilter {.inline, raises: [].} = nk_filter_default
proc nkFilterAscii*():   NkPluginFilter {.inline, raises: [].} = nk_filter_ascii
proc nkFilterFloat*():   NkPluginFilter {.inline, raises: [].} = nk_filter_float
proc nkFilterDecimal*(): NkPluginFilter {.inline, raises: [].} = nk_filter_decimal

# ---------------------------------------------------------------------------
# Public Nim wrappers
# ---------------------------------------------------------------------------

proc raddyBegin*(ctx: ptr nk_context; title: string; bounds: nk_rect;
                 flags: nk_flags = 0): bool {.inline, raises: [].} =
  ## Open a Nuklear window. Returns true if the window is visible this frame.
  ## You MUST call raddyEnd every frame, regardless of the return value.
  ##
  ## Combine NkWindowFlags for `flags`:
  ##   NK_WINDOW_BORDER.nk_flags or NK_WINDOW_MOVABLE.nk_flags
  bool(nk_begin(ctx, title.cstring, bounds, flags))

proc raddyEnd*(ctx: ptr nk_context) {.inline, raises: [].} =
  ## Close the current window. Must be called once per raddyBegin, even if
  ## raddyBegin returned false.
  nk_end(ctx)

proc raddyLabel*(ctx: ptr nk_context; text: string;
                 align: nk_flags = NK_TEXT_LEFT) {.inline, raises: [].} =
  ## Draw a static text label. Use NK_TEXT_LEFT / NK_TEXT_CENTERED / NK_TEXT_RIGHT
  ## from types.nim for the align parameter.
  nk_label(ctx, text.cstring, align)

proc raddyButton*(ctx: ptr nk_context; label: string): bool {.inline, raises: [].} =
  ## Draw a push button. Returns true on the frame the button is clicked.
  bool(nk_button_label(ctx, label.cstring))

proc raddyCheckbox*(ctx: ptr nk_context; label: string;
                    active: var bool): bool {.inline, raises: [].} =
  ## Draw a labeled checkbox. Toggles `active` on click.
  ## Returns true if the state changed this frame.
  var nkActive = nk_bool(active)
  let changed = bool(nk_checkbox_label(ctx, label.cstring, addr nkActive))
  active = bool(nkActive)
  changed

proc raddySlider*(ctx: ptr nk_context; minVal: float32; val: var float32;
                  maxVal: float32; step: float32): bool {.inline, raises: [].} =
  ## Draw a float slider in the range [minVal..maxVal] with the given step size.
  ## Returns true if the value changed this frame.
  bool(nk_slider_float(ctx, minVal, addr val, maxVal, step))

proc raddyEdit*(ctx: ptr nk_context; flags: nk_flags; buf: var string;
                maxLen: int; filter: NkPluginFilter = nil): nk_flags {.inline, raises: [].} =
  ## Draw a text-edit field. `buf` is modified in-place.
  ## `flags` is typically NK_EDIT_FIELD_FLAGS.
  ## `maxLen` is the maximum number of characters (capacity of `buf`).
  ## `filter` limits input characters; nil accepts all.
  ## Returns a bitmask of NkEditEvents (NK_EDIT_COMMITTED etc.).
  var length = cint(buf.len)
  if buf.len < maxLen:
    buf.setLen(maxLen)
  let events = nk_edit_string(ctx, flags, buf.cstring, addr length,
                               maxLen.cint, filter)
  buf.setLen(max(0, int(length)))
  events

proc raddyCombo*(ctx: ptr nk_context; items: openArray[string]; selected: int;
                 itemHeight: int; size: nk_vec2): int {.inline, raises: [].} =
  ## Draw a dropdown combo box. Returns the index of the selected item.
  ## `items` is a fixed array of option strings.
  ## `itemHeight` is the height of each item row in pixels.
  ## `size` is the width/height of the popup panel.
  var cstrs = newSeq[cstring](items.len)
  for i, s in items:
    cstrs[i] = s.cstring
  int(nk_combo(ctx, cast[ptr cstring](addr cstrs[0]), cstrs.len.cint,
               selected.cint, itemHeight.cint, size))

proc raddyProperty*(ctx: ptr nk_context; name: string; minVal: float32;
                    val: var float32; maxVal: float32; step: float32;
                    incPerPixel: float32 = 1.0) {.inline, raises: [].} =
  ## Draw a numeric property widget with +/- drag buttons.
  ## `name` is the label shown next to the widget.
  ## `incPerPixel` controls how much the value changes per dragged pixel.
  nk_property_float(ctx, name.cstring, minVal, addr val, maxVal, step, incPerPixel)

{.pop.}
