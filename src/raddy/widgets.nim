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

type NkPluginFilter* {.importc: "nk_plugin_filter", header: nkH.} =
  proc(edit: pointer; unicode: nk_rune): nk_bool {.cdecl.}
  ## Text-input filter callback. `edit` is an OPAQUE `const nk_text_edit*` —
  ## do NOT dereference or write through it. Custom filters should decide based
  ## on `unicode` alone. Prefer the built-in nkFilter* accessors.
  ##
  ## Bound to Nuklear's `nk_plugin_filter` typedef
  ## (`nk_bool(*)(const struct nk_text_edit*, nk_rune)`) via importc so the
  ## emitted C function-pointer type carries the `const` qualifier and matches
  ## Nuklear at the C level — no fn-ptr-compat compiler flag needed. The Nim
  ## `edit: pointer` shape is the type-check view only; the C type comes from
  ## the header.
  ## Pass nil to accept any character (Nuklear substitutes nk_filter_default).

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
                        incPerPixel: float32): nk_bool
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
  NK_EDIT_SIMPLE_FLAGS*: nk_flags = NK_EDIT_ALWAYS_INSERT_MODE.nk_flags
  NK_EDIT_FIELD_FLAGS*: nk_flags  = NK_EDIT_ALWAYS_INSERT_MODE.nk_flags or
                                     NK_EDIT_SELECTABLE.nk_flags or
                                     NK_EDIT_CLIPBOARD.nk_flags

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
  ## `maxLen` = maximum editable character count. One extra byte is allocated
  ## internally as Nuklear's NUL terminator (Nuklear uses `max-1` usable chars).
  ## Input longer than `maxLen` is silently truncated on return.
  ## `filter` limits input characters; nil accepts any character.
  ## Returns a bitmask of NkEditEvents (NK_EDIT_COMMITTED etc.).
  let cap = maxLen + 1            # +1 so exactly maxLen chars actually fit
  var length = cint(min(buf.len, maxLen))
  if buf.len < cap:
    buf.setLen(cap)               # setLen guarantees cap+1 allocated bytes (hidden NUL);
                                  # Nuklear writes up to max-1 chars + NUL, stays in bounds
  let events = nk_edit_string(ctx, flags, buf.cstring, addr length, cap.cint, filter)
  buf.setLen(max(0, int(length)))
  events

proc raddyCombo*(ctx: ptr nk_context; items: openArray[string]; selected: int;
                 itemHeight: int; size: nk_vec2): int {.inline, raises: [].} =
  ## Draw a dropdown combo box. Returns the index of the selected item.
  ## `items` is the option list; `selected` is clamped to a valid index.
  ## Returns `selected` unchanged (clamped) when `items` is empty.
  ## `itemHeight` is the height of each item row in pixels.
  ## `size` is the width/height of the popup panel.
  ## Note: allocates a seq[cstring] on every call — avoid in tight per-frame loops.
  if items.len == 0:
    return selected
  let sel = clamp(selected, 0, items.len - 1)
  var cstrs = newSeq[cstring](items.len)
  for i, s in items:
    cstrs[i] = s.cstring
  int(nk_combo(ctx, cast[ptr cstring](addr cstrs[0]), cstrs.len.cint,
               sel.cint, itemHeight.cint, size))

proc raddyProperty*(ctx: ptr nk_context; name: string; minVal: float32;
                    val: var float32; maxVal: float32; step: float32;
                    incPerPixel: float32 = 1.0): bool {.inline, raises: [].} =
  ## Draw a numeric property widget with +/- drag buttons.
  ## Returns true if the value changed this frame.
  ## `name` is the label shown next to the widget.
  ## `incPerPixel` controls how much the value changes per dragged pixel.
  bool(nk_property_float(ctx, name.cstring, minVal, addr val, maxVal, step, incPerPixel))

{.pop.}
