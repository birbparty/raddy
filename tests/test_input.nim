## test_input.nim — bddy spec for src/raddy/input.nim
##
## input.nim is decoupled-core (no raylib): these tests require NO draw-proc
## stubs and link against only Nuklear (via vendor.nim / nuklear_impl.c).
##
## Tests verify:
##   - All seven wrappers compile and call through without Defect on a live context
##   - Type coercions (int32→cint, bool→nk_bool, uint32→nk_rune) are correct
##   - raddyInputBegin/End bracketing pattern is safe across multiple frames
##
## Behavioral contract (widget hit-testing, scroll accumulation) is Nuklear
## internals; we test the FFI seam, not reimplemented logic.
##
## freshCtx() always uses nk_init_fixed so the spec runs identically on desktop,
## -d:raddyFixed, and -d:vita without a code-path switch.

import bddy
import raddy/input   ## raddyInputBegin, raddyInputEnd, raddyInputMotion,
                      ## raddyInputButton, raddyInputKey, raddyInputScroll,
                      ## raddyInputUnicode
import raddy/types   ## nk_context, nk_user_font, NkButtons, NkKeys, nk_bool, nk_vec2
import raddy/context ## raddyCtxInit, raddyCtxFree
import raddy/errors  ## RaddyCmdBufBytes

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc freshCtx(buf: var array[RaddyCmdBufBytes, byte]): (nk_context, nk_user_font) =
  ## Initialize a context using nk_init_fixed with caller-supplied buf.
  ## Always uses the fixed-buffer path so the spec is portable to -d:vita and
  ## -d:raddyFixed. buf must outlive the returned context; addr ctx is stable
  ## because the returned tuple is destructured into a caller-scope local var
  ## before addr is taken.
  var ctx: nk_context
  var font: nk_user_font
  let ok = raddyCtxInit(addr ctx, addr font, addr buf[0], nk_size(RaddyCmdBufBytes))
  doAssert ok, "raddyCtxInit failed in test_input helper"
  (ctx, font)

# ---------------------------------------------------------------------------
# Specs
# ---------------------------------------------------------------------------

spec "raddyInputBegin / raddyInputEnd":

  it "empty begin/end frame does not crash":
    var buf: array[RaddyCmdBufBytes, byte]
    var (ctx, _) = freshCtx(buf)
    raddyInputBegin(addr ctx)
    raddyInputEnd(addr ctx)
    raddyCtxFree(addr ctx)
    verify: true

  it "multiple consecutive begin/end frames are safe":
    var buf: array[RaddyCmdBufBytes, byte]
    var (ctx, _) = freshCtx(buf)
    for _ in 0 ..< 3:
      raddyInputBegin(addr ctx)
      raddyInputEnd(addr ctx)
    raddyCtxFree(addr ctx)
    verify: true

spec "raddyInputMotion":

  it "motion at origin does not crash":
    var buf: array[RaddyCmdBufBytes, byte]
    var (ctx, _) = freshCtx(buf)
    raddyInputBegin(addr ctx)
    raddyInputMotion(addr ctx, 0'i32, 0'i32)
    raddyInputEnd(addr ctx)
    raddyCtxFree(addr ctx)
    verify: true

  it "motion at large coordinate does not crash":
    var buf: array[RaddyCmdBufBytes, byte]
    var (ctx, _) = freshCtx(buf)
    raddyInputBegin(addr ctx)
    raddyInputMotion(addr ctx, 1920'i32, 1080'i32)
    raddyInputEnd(addr ctx)
    raddyCtxFree(addr ctx)
    verify: true

  it "negative coordinates are accepted (off-canvas)":
    var buf: array[RaddyCmdBufBytes, byte]
    var (ctx, _) = freshCtx(buf)
    raddyInputBegin(addr ctx)
    raddyInputMotion(addr ctx, -1'i32, -1'i32)
    raddyInputEnd(addr ctx)
    raddyCtxFree(addr ctx)
    verify: true

spec "raddyInputButton":

  it "left button press at origin does not crash":
    var buf: array[RaddyCmdBufBytes, byte]
    var (ctx, _) = freshCtx(buf)
    raddyInputBegin(addr ctx)
    raddyInputButton(addr ctx, NK_BUTTON_LEFT, 0'i32, 0'i32, true)
    raddyInputEnd(addr ctx)
    raddyCtxFree(addr ctx)
    verify: true

  it "right button release does not crash":
    var buf: array[RaddyCmdBufBytes, byte]
    var (ctx, _) = freshCtx(buf)
    raddyInputBegin(addr ctx)
    raddyInputButton(addr ctx, NK_BUTTON_RIGHT, 100'i32, 200'i32, false)
    raddyInputEnd(addr ctx)
    raddyCtxFree(addr ctx)
    verify: true

  it "double-click button is accepted":
    var buf: array[RaddyCmdBufBytes, byte]
    var (ctx, _) = freshCtx(buf)
    raddyInputBegin(addr ctx)
    raddyInputButton(addr ctx, NK_BUTTON_DOUBLE, 50'i32, 50'i32, true)
    raddyInputEnd(addr ctx)
    raddyCtxFree(addr ctx)
    verify: true

spec "raddyInputKey":

  it "shift-press does not crash":
    var buf: array[RaddyCmdBufBytes, byte]
    var (ctx, _) = freshCtx(buf)
    raddyInputBegin(addr ctx)
    raddyInputKey(addr ctx, NK_KEY_SHIFT, true)
    raddyInputEnd(addr ctx)
    raddyCtxFree(addr ctx)
    verify: true

  it "ctrl-release does not crash":
    var buf: array[RaddyCmdBufBytes, byte]
    var (ctx, _) = freshCtx(buf)
    raddyInputBegin(addr ctx)
    raddyInputKey(addr ctx, NK_KEY_CTRL, false)
    raddyInputEnd(addr ctx)
    raddyCtxFree(addr ctx)
    verify: true

  it "all NkKeys values are accepted (no bounds error)":
    ## Iterate every valid key from NK_KEY_NONE to NK_KEY_F12 (enum 0..42)
    ## and feed a press+release pair. NK_KEY_MAX (= 43) is the sentinel equal
    ## to the array size and is intentionally excluded — passing it would write
    ## out of bounds. NK_KEY_F1..F12 (enum 31..42) are included here.
    var buf: array[RaddyCmdBufBytes, byte]
    var (ctx, _) = freshCtx(buf)
    raddyInputBegin(addr ctx)
    for k in NK_KEY_NONE .. NK_KEY_F12:
      raddyInputKey(addr ctx, k, true)
      raddyInputKey(addr ctx, k, false)
    raddyInputEnd(addr ctx)
    raddyCtxFree(addr ctx)
    verify: true

spec "raddyInputScroll":

  it "vertical scroll delta +1.0 does not crash":
    var buf: array[RaddyCmdBufBytes, byte]
    var (ctx, _) = freshCtx(buf)
    raddyInputBegin(addr ctx)
    raddyInputScroll(addr ctx, 0.0f32, 1.0f32)
    raddyInputEnd(addr ctx)
    raddyCtxFree(addr ctx)
    verify: true

  it "horizontal scroll delta does not crash":
    var buf: array[RaddyCmdBufBytes, byte]
    var (ctx, _) = freshCtx(buf)
    raddyInputBegin(addr ctx)
    raddyInputScroll(addr ctx, -1.0f32, 0.0f32)
    raddyInputEnd(addr ctx)
    raddyCtxFree(addr ctx)
    verify: true

  it "zero scroll delta is accepted":
    var buf: array[RaddyCmdBufBytes, byte]
    var (ctx, _) = freshCtx(buf)
    raddyInputBegin(addr ctx)
    raddyInputScroll(addr ctx, 0.0f32, 0.0f32)
    raddyInputEnd(addr ctx)
    raddyCtxFree(addr ctx)
    verify: true

spec "raddyInputUnicode":

  it "ASCII printable codepoint U+0041 (A) does not crash":
    var buf: array[RaddyCmdBufBytes, byte]
    var (ctx, _) = freshCtx(buf)
    raddyInputBegin(addr ctx)
    raddyInputUnicode(addr ctx, 0x0041u32)  ## 'A'
    raddyInputEnd(addr ctx)
    raddyCtxFree(addr ctx)
    verify: true

  it "BMP codepoint U+00E9 (é) does not crash":
    var buf: array[RaddyCmdBufBytes, byte]
    var (ctx, _) = freshCtx(buf)
    raddyInputBegin(addr ctx)
    raddyInputUnicode(addr ctx, 0x00E9u32)  ## é
    raddyInputEnd(addr ctx)
    raddyCtxFree(addr ctx)
    verify: true

  it "CJK codepoint U+4E2D (中) does not crash":
    var buf: array[RaddyCmdBufBytes, byte]
    var (ctx, _) = freshCtx(buf)
    raddyInputBegin(addr ctx)
    raddyInputUnicode(addr ctx, 0x4E2Du32)  ## 中
    raddyInputEnd(addr ctx)
    raddyCtxFree(addr ctx)
    verify: true

  it "feeding more than NK_INPUT_MAX codepoints in one frame does not crash":
    ## NK_INPUT_MAX = 16 bytes; excess is silently dropped. This test exercises
    ## the overflow path to lock in the no-Defect contract.
    var buf: array[RaddyCmdBufBytes, byte]
    var (ctx, _) = freshCtx(buf)
    raddyInputBegin(addr ctx)
    for _ in 0 ..< 20:
      raddyInputUnicode(addr ctx, 0x0041u32)  ## 'A', repeated 20 times
    raddyInputEnd(addr ctx)
    raddyCtxFree(addr ctx)
    verify: true

spec "raddyInputBegin/End with all event types":

  it "full frame with motion + button + key + scroll + unicode":
    var buf: array[RaddyCmdBufBytes, byte]
    var (ctx, _) = freshCtx(buf)
    raddyInputBegin(addr ctx)
    raddyInputMotion(addr ctx, 320'i32, 240'i32)
    raddyInputButton(addr ctx, NK_BUTTON_LEFT, 320'i32, 240'i32, true)
    raddyInputKey(addr ctx, NK_KEY_SHIFT, true)
    raddyInputScroll(addr ctx, 0.0f32, -1.0f32)
    raddyInputUnicode(addr ctx, 0x0041u32)
    raddyInputButton(addr ctx, NK_BUTTON_LEFT, 320'i32, 240'i32, false)
    raddyInputKey(addr ctx, NK_KEY_SHIFT, false)
    raddyInputEnd(addr ctx)
    raddyCtxFree(addr ctx)
    verify: true
