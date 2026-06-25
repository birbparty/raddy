## test_style.nim — bddy spec for src/raddy/style.nim
##
## Tests: NkStyleColors enum ordinals, raddyStyleDefault does not crash,
## palette size constant, get-color-by-name binding.
## Actual rendering effects require a display (raddy-bw1 integration tests).

import bddy
import raddy/style
import raddy/types      ## nk_context, nk_color
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

  it "NK_COLOR_KNOB_CURSOR_ACTIVE is 31":
    verify:
      ord(NK_COLOR_KNOB_CURSOR_ACTIVE) == 31

spec "raddyStyleDefault":

  it "applies without crash on a live context":
    var nkFont: nk_user_font  ## zeroed — nk_style_default does not call the width fn
    var ctx: nk_context
    let ok = raddyCtxInit(addr ctx, addr nkFont)
    raddyStyleDefault(addr ctx)
    raddyCtxFree(addr ctx)
    verify:
      ok == true  ## reached teardown without crash

spec "nk_style_get_color_by_name":

  it "returns non-nil for NK_COLOR_TEXT":
    let name = nk_style_get_color_by_name(NK_COLOR_TEXT)
    verify:
      name != nil

  it "returns non-nil for NK_COLOR_COUNT":
    let name = nk_style_get_color_by_name(NK_COLOR_COUNT)
    verify:
      name != nil
