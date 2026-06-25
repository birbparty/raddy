## layout.nim — Nuklear layout API (rows, groups, spacing).
##
## Thin Nim wrappers over the Nuklear row-layout and group primitives.
## Call these inside an nk_begin/nk_end block (see widgets.nim / raddy-m0r).
##
## Row layouts (pick one per row):
##   raddyLayoutRowDynamic  — equal-width columns, auto-sized to window width
##   raddyLayoutRowStatic   — fixed-pixel-width columns
##   raddyLayoutRowBegin /  — custom per-widget widths (ratio or pixel)
##   raddyLayoutRowPush /
##   raddyLayoutRowEnd
##
## Groups — scrollable sub-containers inside a window:
##   raddyGroupBegin / raddyGroupEnd
##
## Spacing — advance the layout cursor without drawing anything:
##   raddySpacing
##
## Decoupled-core rule: MUST NOT import naylib, raylib_console, inputty, or
## any game-specific module.

import ./types   ## nk_context, nk_bool, nk_flags
import ./vendor  ## side-effect: compile nuklear_impl.c; inject nk_config.h

{.push raises: [].}

const nkH = "nuklear.h"

# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

type
  NkLayoutFormat* {.importc: "enum nk_layout_format", header: nkH,
                    size: sizeof(cint).} = enum
    ## Column-width interpretation used by row-begin / row-push.
    NK_DYNAMIC = 0  ## values are fractions (0.0–1.0) of available width
    NK_STATIC  = 1  ## values are absolute pixel widths

  NkWindowFlags* {.importc: "enum nk_window_flags", header: nkH,
                   size: sizeof(cint).} = enum
    ## Window / group feature flags (combine with `or`).
    NK_WINDOW_BORDER          = 1 shl 0
    NK_WINDOW_MOVABLE         = 1 shl 1
    NK_WINDOW_SCALABLE        = 1 shl 2
    NK_WINDOW_CLOSABLE        = 1 shl 3
    NK_WINDOW_MINIMIZABLE     = 1 shl 4
    NK_WINDOW_NO_SCROLLBAR    = 1 shl 5
    NK_WINDOW_TITLE           = 1 shl 6
    NK_WINDOW_SCROLL_AUTO_HIDE = 1 shl 7
    NK_WINDOW_BACKGROUND      = 1 shl 8
    NK_WINDOW_SCALE_LEFT      = 1 shl 9
    NK_WINDOW_NO_INPUT        = 1 shl 10

# ---------------------------------------------------------------------------
# Raw C FFI bindings (private to this module)
# ---------------------------------------------------------------------------

proc nk_layout_row_dynamic(ctx: ptr nk_context; height: float32; cols: cint)
    {.importc: "nk_layout_row_dynamic", header: nkH, sideEffect.}

proc nk_layout_row_static(ctx: ptr nk_context; height: float32;
                           item_width: cint; cols: cint)
    {.importc: "nk_layout_row_static", header: nkH, sideEffect.}

proc nk_layout_row_begin(ctx: ptr nk_context; fmt: NkLayoutFormat;
                          row_height: float32; cols: cint)
    {.importc: "nk_layout_row_begin", header: nkH, sideEffect.}

proc nk_layout_row_push(ctx: ptr nk_context; value: float32)
    {.importc: "nk_layout_row_push", header: nkH, sideEffect.}

proc nk_layout_row_end(ctx: ptr nk_context)
    {.importc: "nk_layout_row_end", header: nkH, sideEffect.}

proc nk_group_begin(ctx: ptr nk_context; title: cstring; flags: nk_flags): nk_bool
    {.importc: "nk_group_begin", header: nkH, sideEffect.}

proc nk_group_end(ctx: ptr nk_context)
    {.importc: "nk_group_end", header: nkH, sideEffect.}

proc nk_spacing(ctx: ptr nk_context; cols: cint)
    {.importc: "nk_spacing", header: nkH, sideEffect.}

# ---------------------------------------------------------------------------
# Public Nim wrappers
# ---------------------------------------------------------------------------

proc raddyLayoutRowDynamic*(ctx: ptr nk_context; height: float32;
                             cols: int) {.inline.} =
  ## Set the next row to use `cols` equal-width columns, each `height` pixels tall.
  ## Pass height=0 to use the widget's natural height.
  nk_layout_row_dynamic(ctx, height, cols.cint)

proc raddyLayoutRowStatic*(ctx: ptr nk_context; height: float32;
                            itemWidth: int; cols: int) {.inline.} =
  ## Set the next row to use `cols` columns of fixed `itemWidth` pixels each,
  ## `height` pixels tall.
  nk_layout_row_static(ctx, height, itemWidth.cint, cols.cint)

proc raddyLayoutRowBegin*(ctx: ptr nk_context; fmt: NkLayoutFormat;
                           rowHeight: float32; cols: int) {.inline.} =
  ## Begin a manual row with `cols` slots.
  ## Follow with raddyLayoutRowPush for each slot, then raddyLayoutRowEnd.
  ##   NK_DYNAMIC: push values are ratios (0.0–1.0) of row width
  ##   NK_STATIC:  push values are absolute pixel widths
  nk_layout_row_begin(ctx, fmt, rowHeight, cols.cint)

proc raddyLayoutRowPush*(ctx: ptr nk_context; value: float32) {.inline.} =
  ## Advance to the next slot in a raddyLayoutRowBegin block.
  ## Value is a ratio (NK_DYNAMIC) or pixel width (NK_STATIC).
  nk_layout_row_push(ctx, value)

proc raddyLayoutRowEnd*(ctx: ptr nk_context) {.inline.} =
  ## End a raddyLayoutRowBegin block.
  nk_layout_row_end(ctx)

proc raddyGroupBegin*(ctx: ptr nk_context; title: string;
                      flags: nk_flags = 0): bool {.inline.} =
  ## Open a scrollable group sub-container with the given title and window flags.
  ## Returns true if the group is visible; you MUST call raddyGroupEnd when true.
  ##
  ## Combine NkWindowFlags values with `or` for the flags parameter:
  ##   NK_WINDOW_BORDER.nk_flags or NK_WINDOW_NO_SCROLLBAR.nk_flags
  bool(nk_group_begin(ctx, title.cstring, flags))

proc raddyGroupEnd*(ctx: ptr nk_context) {.inline.} =
  ## Close a group opened by raddyGroupBegin. Must be called when raddyGroupBegin
  ## returned true.
  nk_group_end(ctx)

proc raddySpacing*(ctx: ptr nk_context; cols: int) {.inline.} =
  ## Advance `cols` widget slots in the current row without drawing anything.
  nk_spacing(ctx, cols.cint)

{.pop.}
