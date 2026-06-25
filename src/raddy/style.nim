## style.nim — Nuklear theme/style API for raddy.
##
## Provides nk_style_default (Nuklear built-in dark theme) and nk_style_from_table
## for custom palettes.  Call after font init, before any nk_window_begin.
##
## Decoupled-core rule: MUST NOT import naylib, raylib_console, or inputty.
##
## Default palette (from nuklear.h NK_COLOR_MAP):
##   NK_COLOR_TEXT                   175 175 175 255  (medium grey)
##   NK_COLOR_WINDOW                  45  45  45 255  (dark grey background)
##   NK_COLOR_HEADER                  40  40  40 255  (slightly darker header)
##   NK_COLOR_BORDER                  65  65  65 255  (visible but muted border)
##   NK_COLOR_BUTTON                  50  50  50 255
##   NK_COLOR_BUTTON_HOVER            40  40  40 255
##   NK_COLOR_BUTTON_ACTIVE           35  35  35 255
##   NK_COLOR_TOGGLE                 100 100 100 255
##   NK_COLOR_TOGGLE_HOVER           120 120 120 255
##   NK_COLOR_TOGGLE_CURSOR           45  45  45 255
##   NK_COLOR_SELECT                  45  45  45 255
##   NK_COLOR_SELECT_ACTIVE           35  35  35 255
##   NK_COLOR_SLIDER                  38  38  38 255
##   NK_COLOR_SLIDER_CURSOR          100 100 100 255
##   NK_COLOR_SLIDER_CURSOR_HOVER    120 120 120 255
##   NK_COLOR_SLIDER_CURSOR_ACTIVE   150 150 150 255
##   NK_COLOR_PROPERTY                38  38  38 255
##   NK_COLOR_EDIT                    38  38  38 255
##   NK_COLOR_EDIT_CURSOR            175 175 175 255
##   NK_COLOR_COMBO                   45  45  45 255
##   NK_COLOR_CHART                  120 120 120 255
##   NK_COLOR_CHART_COLOR             45  45  45 255
##   NK_COLOR_CHART_COLOR_HIGHLIGHT  255   0   0 255  (red)
##   NK_COLOR_SCROLLBAR               40  40  40 255
##   NK_COLOR_SCROLLBAR_CURSOR       100 100 100 255
##   NK_COLOR_SCROLLBAR_CURSOR_HOVER 120 120 120 255
##   NK_COLOR_SCROLLBAR_CURSOR_ACTIVE 150 150 150 255
##   NK_COLOR_TAB_HEADER              40  40  40 255
##   NK_COLOR_KNOB                    38  38  38 255
##   NK_COLOR_KNOB_CURSOR            100 100 100 255
##   NK_COLOR_KNOB_CURSOR_HOVER      120 120 120 255
##   NK_COLOR_KNOB_CURSOR_ACTIVE     150 150 150 255

import ./types  ## nk_context, nk_color

{.push raises: [].}

const nkH = "nuklear.h"

# ---------------------------------------------------------------------------
# nk_style_colors enum
# ---------------------------------------------------------------------------

type NkStyleColors* {.importc: "enum nk_style_colors", header: nkH,
                      size: sizeof(cint).} = enum
  ## Index into the nk_color table passed to nk_style_from_table.
  NK_COLOR_TEXT                   = 0
  NK_COLOR_WINDOW                 = 1
  NK_COLOR_HEADER                 = 2
  NK_COLOR_BORDER                 = 3
  NK_COLOR_BUTTON                 = 4
  NK_COLOR_BUTTON_HOVER           = 5
  NK_COLOR_BUTTON_ACTIVE          = 6
  NK_COLOR_TOGGLE                 = 7
  NK_COLOR_TOGGLE_HOVER           = 8
  NK_COLOR_TOGGLE_CURSOR          = 9
  NK_COLOR_SELECT                 = 10
  NK_COLOR_SELECT_ACTIVE          = 11
  NK_COLOR_SLIDER                 = 12
  NK_COLOR_SLIDER_CURSOR          = 13
  NK_COLOR_SLIDER_CURSOR_HOVER    = 14
  NK_COLOR_SLIDER_CURSOR_ACTIVE   = 15
  NK_COLOR_PROPERTY               = 16
  NK_COLOR_EDIT                   = 17
  NK_COLOR_EDIT_CURSOR            = 18
  NK_COLOR_COMBO                  = 19
  NK_COLOR_CHART                  = 20
  NK_COLOR_CHART_COLOR            = 21
  NK_COLOR_CHART_COLOR_HIGHLIGHT  = 22
  NK_COLOR_SCROLLBAR              = 23
  NK_COLOR_SCROLLBAR_CURSOR       = 24
  NK_COLOR_SCROLLBAR_CURSOR_HOVER = 25
  NK_COLOR_SCROLLBAR_CURSOR_ACTIVE = 26
  NK_COLOR_TAB_HEADER             = 27
  NK_COLOR_KNOB                   = 28
  NK_COLOR_KNOB_CURSOR            = 29
  NK_COLOR_KNOB_CURSOR_HOVER      = 30
  NK_COLOR_KNOB_CURSOR_ACTIVE     = 31
  NK_COLOR_COUNT                  = 32

# ---------------------------------------------------------------------------
# Style API — raw C bindings (private; use raddy* wrappers below)
# ---------------------------------------------------------------------------

proc nk_style_default(ctx: ptr nk_context)
    {.importc: "nk_style_default", header: nkH, sideEffect.}

proc nk_style_from_table(ctx: ptr nk_context; colors: ptr nk_color)
    {.importc: "nk_style_from_table", header: nkH, sideEffect.}

proc nk_style_get_color_by_name(c: NkStyleColors): cstring
    {.importc: "nk_style_get_color_by_name", header: nkH.}
  ## NOTE: c must be in 0..<NK_COLOR_COUNT. Passing NK_COLOR_COUNT itself
  ## indexes nk_color_names[32] one past the end — C UB. Use raddyColorName.

{.pop.}

# ---------------------------------------------------------------------------
# Convenience wrappers (public surface)
# ---------------------------------------------------------------------------

proc raddyStyleDefault*(ctx: ptr nk_context) {.inline, raises: [].} =
  ## Apply the Nuklear default dark theme to ctx.
  ## ctx must be non-nil and initialised via raddyBundleCreate / raddyCtxInit.
  ## Call once after init, before the first nk_window_begin.
  nk_style_default(ctx)

proc raddyStyleFromTable*(ctx: ptr nk_context;
                          palette: array[ord(NK_COLOR_COUNT), nk_color])
    {.inline, raises: [].} =
  ## Apply a custom palette to ctx. palette must have exactly NK_COLOR_COUNT (32)
  ## entries indexed by NkStyleColors ordinals. The array size is checked at
  ## compile time — a shorter array is a type error.
  ## ctx must be non-nil and initialised via raddyBundleCreate / raddyCtxInit.
  nk_style_from_table(ctx, cast[ptr nk_color](unsafeAddr palette[0]))

proc raddyColorName*(c: NkStyleColors): cstring {.inline, raises: [].} =
  ## Return the C-string name for a NkStyleColors value (e.g. "NK_COLOR_TEXT").
  ## Returns nil for NK_COLOR_COUNT (sentinel, not a valid color index).
  ## Guarded wrapper around nk_style_get_color_by_name; safe for all enum values.
  if ord(c) >= ord(NK_COLOR_COUNT): return nil
  nk_style_get_color_by_name(c)
