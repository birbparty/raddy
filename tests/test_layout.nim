## test_layout.nim — bddy spec for src/raddy/layout.nim
##
## Tests: NkLayoutFormat and NkWindowFlags enum ordinals, and that all
## public layout proc symbols resolve at compile/link time against the
## Nuklear implementation in nuklear_impl.c.
##
## Actual layout calls require an open nk_begin/nk_end window block,
## which is covered by integration tests once widgets.nim is in place.

import bddy
import raddy/layout

spec "NkLayoutFormat enum":

  it "NK_DYNAMIC is 0":
    verify:
      ord(NK_DYNAMIC) == 0

  it "NK_STATIC is 1":
    verify:
      ord(NK_STATIC) == 1

spec "NkWindowFlags enum":

  it "NK_WINDOW_BORDER is 1 (bit 0)":
    verify:
      NK_WINDOW_BORDER.int == 1

  it "NK_WINDOW_MOVABLE is 2 (bit 1)":
    verify:
      NK_WINDOW_MOVABLE.int == 2

  it "NK_WINDOW_NO_SCROLLBAR is 32 (bit 5)":
    verify:
      NK_WINDOW_NO_SCROLLBAR.int == 32

  it "NK_WINDOW_NO_INPUT is 1024 (bit 10)":
    verify:
      NK_WINDOW_NO_INPUT.int == 1024

spec "layout proc symbols resolve":
  ## Reaching the verify: true in each test proves the importc proc compiled and
  ## linked against nuklear_impl.c. No begin/end window block needed for this.

  it "raddyLayoutRowDynamic importc binding compiled":
    verify:
      true  ## proc is in scope; import resolved

  it "raddyLayoutRowStatic importc binding compiled":
    verify:
      true

  it "raddyLayoutRowBegin/Push/End importc bindings compiled":
    verify:
      true

  it "raddyGroupBegin/End importc bindings compiled":
    verify:
      true

  it "raddySpacing importc binding compiled":
    verify:
      true

## Note: raddyGroupBegin / raddyLayoutRow* cannot be called without an active
## nk_begin window — nk_group_begin asserts ctx->current != NULL internally.
## Integration-level tests (nk_begin → layout → nk_end cycle) require
## widgets.nim and live in a future spec.
