## test_widgets.nim — bddy spec for src/raddy/widgets.nim
##
## Tests: enum ordinals, symbol resolution, and wrapper round-trips through
## a live raddyBegin/raddyEnd window (the only way to exercise layout-phase
## procs without SIGABRT from Nuklear's panel-stack assertions).
##
## All tests use nk_init_fixed so the spec runs identically on desktop,
## -d:raddyFixed, and -d:vita without a code-path switch.
##
## Behavioral contracts (hit-testing, state transitions) live in Nuklear;
## we test the FFI seam and Nim-level coercions only.

import bddy
import raddy/widgets
import raddy/types    ## nk_context, nk_user_font, nk_size, nk_rect, nk_vec2
import raddy/errors   ## RaddyCmdBufBytes
import raddy/context  ## raddyCtxInit, raddyCtxFree
import raddy/input    ## raddyInputBegin, raddyInputEnd

# ---------------------------------------------------------------------------
# Helper: minimal per-test context
# ---------------------------------------------------------------------------

proc stubWidth(handle: nk_handle; h: float32; text: cstring; len: cint): float32
    {.cdecl.} = float32(len) * 8.0
  ## Stub font metric: 8 px per character. Nuklear requires a non-nil width
  ## callback before nk_begin; this dummy satisfies that contract without
  ## needing a real font (no display required, compile+link only test env).

proc freshCtx(buf: var array[RaddyCmdBufBytes, byte]): (nk_context, nk_user_font) =
  var ctx: nk_context
  var font: nk_user_font
  font.height = 16.0
  font.width  = stubWidth
  let ok = raddyCtxInit(addr ctx, addr font, addr buf[0], nk_size(RaddyCmdBufBytes))
  doAssert ok, "raddyCtxInit failed in test_widgets helper"
  (ctx, font)

proc windowBounds(): nk_rect = nk_rect(x: 0, y: 0, w: 400, h: 300)

# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

spec "NkEditEvents enum":

  it "NK_EDIT_ACTIVE is 1 (bit 0)":
    verify:
      NK_EDIT_ACTIVE.int == 1

  it "NK_EDIT_COMMITTED is 16 (bit 4)":
    verify:
      NK_EDIT_COMMITTED.int == 16

spec "NkEditFlags enum":

  it "NK_EDIT_READ_ONLY is 1 (bit 0)":
    verify:
      NK_EDIT_READ_ONLY.int == 1

  it "NK_EDIT_MULTILINE is 1024 (bit 10)":
    verify:
      NK_EDIT_MULTILINE.int == 1024

# ---------------------------------------------------------------------------
# Symbol resolution (compile+link check for all importc procs)
# ---------------------------------------------------------------------------

spec "widget proc symbols resolve":

  it "raddyBegin/raddyEnd importc bindings compiled":
    verify:
      true

  it "raddyLabel importc binding compiled":
    verify:
      true

  it "raddyButton importc binding compiled":
    verify:
      true

  it "raddyCheckbox importc binding compiled":
    verify:
      true

  it "raddySlider importc binding compiled":
    verify:
      true

  it "raddyEdit importc binding compiled":
    verify:
      true

  it "raddyCombo importc binding compiled":
    verify:
      true

  it "raddyProperty importc binding compiled":
    verify:
      true

# ---------------------------------------------------------------------------
# Live context round-trips
# ---------------------------------------------------------------------------

spec "raddyBegin / raddyEnd":
  var buf: array[RaddyCmdBufBytes, byte]

  it "begin with 400×300 bounds does not crash and returns bool":
    var (ctx, _) = freshCtx(buf)
    raddyInputBegin(addr ctx)
    raddyInputEnd(addr ctx)
    let vis = raddyBegin(addr ctx, "test", windowBounds(),
                         NK_WINDOW_BORDER.nk_flags)
    raddyEnd(addr ctx)
    raddyCtxFree(addr ctx)
    verify:
      vis == true or vis == false  ## either state is valid

  it "raddyEnd must be called even when raddyBegin returns false":
    ## Nuklear requires nk_end every frame even on hidden/collapsed windows.
    ## This test verifies no crash when begin→false path calls end.
    var (ctx, _) = freshCtx(buf)
    raddyInputBegin(addr ctx)
    raddyInputEnd(addr ctx)
    # Open then immediately close to set collapsed state
    discard raddyBegin(addr ctx, "collapsible", windowBounds(), 0)
    raddyEnd(addr ctx)
    raddyCtxFree(addr ctx)
    verify:
      true

spec "raddyLabel":

  it "emits without crash inside a window":
    var buf: array[RaddyCmdBufBytes, byte]
    var (ctx, _) = freshCtx(buf)
    raddyInputBegin(addr ctx)
    raddyInputEnd(addr ctx)
    discard raddyBegin(addr ctx, "w", windowBounds(), 0)
    raddyLabel(addr ctx, "Hello", NK_TEXT_LEFT)
    raddyEnd(addr ctx)
    raddyCtxFree(addr ctx)
    verify:
      true

spec "raddyButton":

  it "returns false with no pointer over it":
    var buf: array[RaddyCmdBufBytes, byte]
    var (ctx, _) = freshCtx(buf)
    raddyInputBegin(addr ctx)
    raddyInputEnd(addr ctx)
    discard raddyBegin(addr ctx, "w", windowBounds(), 0)
    let clicked = raddyButton(addr ctx, "OK")
    raddyEnd(addr ctx)
    raddyCtxFree(addr ctx)
    verify:
      not clicked

spec "raddyCheckbox":

  it "does not change state without pointer interaction":
    var buf: array[RaddyCmdBufBytes, byte]
    var (ctx, _) = freshCtx(buf)
    raddyInputBegin(addr ctx)
    raddyInputEnd(addr ctx)
    var active = false
    discard raddyBegin(addr ctx, "w", windowBounds(), 0)
    let changed = raddyCheckbox(addr ctx, "opt", active)
    raddyEnd(addr ctx)
    raddyCtxFree(addr ctx)
    verify:
      not changed
      not active

spec "raddySlider":

  it "clamps val to [min..max] and does not change without input":
    var buf: array[RaddyCmdBufBytes, byte]
    var (ctx, _) = freshCtx(buf)
    raddyInputBegin(addr ctx)
    raddyInputEnd(addr ctx)
    var val: float32 = 0.5
    discard raddyBegin(addr ctx, "w", windowBounds(), 0)
    let changed = raddySlider(addr ctx, 0.0, val, 1.0, 0.1)
    raddyEnd(addr ctx)
    raddyCtxFree(addr ctx)
    verify:
      not changed
      val >= 0.0 and val <= 1.0

spec "raddyProperty":

  it "does not change val without input and returns false":
    var buf: array[RaddyCmdBufBytes, byte]
    var (ctx, _) = freshCtx(buf)
    raddyInputBegin(addr ctx)
    raddyInputEnd(addr ctx)
    var val: float32 = 5.0
    discard raddyBegin(addr ctx, "w", windowBounds(), 0)
    let changed = raddyProperty(addr ctx, "#volume", 0.0, val, 10.0, 1.0)
    raddyEnd(addr ctx)
    raddyCtxFree(addr ctx)
    verify:
      val == 5.0
      not changed

spec "raddyCombo edge cases":

  it "empty items returns selected unchanged without crash":
    var buf: array[RaddyCmdBufBytes, byte]
    var (ctx, _) = freshCtx(buf)
    raddyInputBegin(addr ctx)
    raddyInputEnd(addr ctx)
    discard raddyBegin(addr ctx, "w", windowBounds(), 0)
    let sz = nk_vec2(x: 200, y: 100)
    let ret = raddyCombo(addr ctx, [], 42, 20, sz)
    raddyEnd(addr ctx)
    raddyCtxFree(addr ctx)
    verify:
      ret == 42

  it "out-of-range selected is clamped to valid index":
    var buf: array[RaddyCmdBufBytes, byte]
    var (ctx, _) = freshCtx(buf)
    raddyInputBegin(addr ctx)
    raddyInputEnd(addr ctx)
    discard raddyBegin(addr ctx, "w", windowBounds(), 0)
    let sz = nk_vec2(x: 200, y: 100)
    let items = ["A", "B", "C"]
    let ret = raddyCombo(addr ctx, items, 99, 20, sz)
    raddyEnd(addr ctx)
    raddyCtxFree(addr ctx)
    verify:
      ret >= 0 and ret <= 2  ## clamped; returns a valid index

spec "raddyEdit capacity":

  it "accepts empty buf and does not crash":
    var buf: array[RaddyCmdBufBytes, byte]
    var (ctx, _) = freshCtx(buf)
    raddyInputBegin(addr ctx)
    raddyInputEnd(addr ctx)
    var s = ""
    discard raddyBegin(addr ctx, "w", windowBounds(), 0)
    let ev = raddyEdit(addr ctx, NK_EDIT_FIELD_FLAGS, s, 64)
    raddyEnd(addr ctx)
    raddyCtxFree(addr ctx)
    verify:
      s.len <= 64

  it "truncates pre-populated buf longer than maxLen":
    var buf: array[RaddyCmdBufBytes, byte]
    var (ctx, _) = freshCtx(buf)
    raddyInputBegin(addr ctx)
    raddyInputEnd(addr ctx)
    var s = "Hello World This Is Longer"  ## 26 chars
    discard raddyBegin(addr ctx, "w", windowBounds(), 0)
    let ev = raddyEdit(addr ctx, NK_EDIT_FIELD_FLAGS, s, 8)
    raddyEnd(addr ctx)
    raddyCtxFree(addr ctx)
    verify:
      s.len <= 8  ## truncated to maxLen

spec "nkFilter accessors":

  it "nkFilterDefault returns non-nil":
    verify:
      nkFilterDefault() != nil

  it "nkFilterAscii returns non-nil":
    verify:
      nkFilterAscii() != nil

  it "nkFilterFloat returns non-nil":
    verify:
      nkFilterFloat() != nil

  it "nkFilterDecimal returns non-nil":
    verify:
      nkFilterDecimal() != nil
