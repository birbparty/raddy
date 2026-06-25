## test_style.nim — bddy spec for src/raddy/style.nim
##
## Tests: NkStyleColors enum ordinals, raddyStyleDefault does not crash,
## raddyStyleFromTable with default and custom palettes, raddyColorName bounds.
## Actual rendering effects require a display (raddy-bw1 integration tests).

import bddy
import raddy/style
import raddy/types      ## nk_context, nk_color, nk_user_font
import raddy/context    ## raddyCtxInit, raddyCtxFree

## Nuklear implementation for nk_style_default / nk_style_from_table / nk_style_get_color_by_name.
## These live in nuklear_impl.c compiled via vendor.nim → no linker stub needed.

spec "NkStyleColors enum":

  it "NK_COLOR_TEXT is 0":
    verify:
      ord(NK_COLOR_TEXT) == 0

  it "NK_COLOR_WINDOW is 1":
    verify:
      ord(NK_COLOR_WINDOW) == 1

  it "NK_COLOR_COUNT is 32":
    verify:
      ord(NK_COLOR_COUNT) == 32

  it "NK_COLOR_TAB_HEADER is 27":
    ## Spot-check a mid-range value against the nuklear.h enum definition.
    verify:
      ord(NK_COLOR_TAB_HEADER) == 27

  it "NK_COLOR_KNOB_CURSOR_ACTIVE is 31 (last valid color index)":
    verify:
      ord(NK_COLOR_KNOB_CURSOR_ACTIVE) == 31

spec "raddyStyleDefault":

  it "applies without crash on a live context":
    ## nk_style_default does not call the font width callback — zeroed nkFont is safe.
    var nkFont: nk_user_font
    var ctx: nk_context
    let ok = raddyCtxInit(addr ctx, addr nkFont)
    doAssert ok, "raddyCtxInit must succeed before testing raddyStyleDefault"
    raddyStyleDefault(addr ctx)
    raddyCtxFree(addr ctx)
    verify:
      true  ## reached teardown without crash

spec "raddyStyleFromTable":

  it "applies nil-equivalent default palette without crash":
    ## nk_style_from_table with all-zero colors is valid — zeroed nk_color
    ## is {r=0,g=0,b=0,a=0}. Nuklear accepts it without crash.
    var nkFont: nk_user_font
    var ctx: nk_context
    let ok = raddyCtxInit(addr ctx, addr nkFont)
    doAssert ok, "raddyCtxInit must succeed before testing raddyStyleFromTable"
    var palette: array[ord(NK_COLOR_COUNT), nk_color]  ## all zero-initialised
    raddyStyleFromTable(addr ctx, palette)
    raddyCtxFree(addr ctx)
    verify:
      true  ## reached teardown without crash

  it "compile-time array size is NK_COLOR_COUNT (32)":
    ## Verify the palette array type has exactly 32 entries.
    var palette: array[ord(NK_COLOR_COUNT), nk_color]
    verify:
      palette.len == 32

spec "raddyColorName":

  it "returns non-nil for NK_COLOR_TEXT (first valid index)":
    let name = raddyColorName(NK_COLOR_TEXT)
    verify:
      name != nil

  it "returns non-nil for NK_COLOR_KNOB_CURSOR_ACTIVE (last valid index, ord 31)":
    let name = raddyColorName(NK_COLOR_KNOB_CURSOR_ACTIVE)
    verify:
      name != nil

  it "returns nil for NK_COLOR_COUNT (sentinel, out-of-bounds guard)":
    ## nk_style_get_color_by_name(NK_COLOR_COUNT) would read nk_color_names[32]
    ## one past the end (C UB). raddyColorName guards this and returns nil.
    let name = raddyColorName(NK_COLOR_COUNT)
    verify:
      name == nil
