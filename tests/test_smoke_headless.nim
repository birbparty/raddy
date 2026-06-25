## test_smoke_headless.nim — Headless acceptance smoke test for examples/demo.nim
##
## Machine-checkable acceptance criteria from raddy-h92:
##   ✓  Demo UI builds without crash (N simulated frames)
##   ✓  Command buffer non-empty after each frame (Nuklear generated draw calls)
##   ✓  Buffer overflow = false (no commands were dropped)
##
## Screenshot non-uniform check (pixel variance) requires a real GL context
## (xvfb or a physical display) and is covered by the separate human visual
## sign-off bead (raddy-bdz). This file covers everything testable headlessly.
##
## The test exercises the SAME widget calls as examples/demo.nim using:
##   - nk_init_fixed (fixed buffer — same path as vita/-d:raddyFixed)
##   - A stub font width callback (8 px/char; satisfies Nuklear's non-nil assert)
##   - No raylib window, no naylib, no OpenGL — pure Nuklear + raddy API

import bddy
import raddy
import raddy/context  ## raddyCtxInit, raddyCtxFree, raddyCtxClear

# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

proc stubWidth(handle: nk_handle; h: float32; text: cstring; len: cint): float32
    {.cdecl.} = float32(len) * 8.0

proc makeCtx(buf: var array[RaddyCmdBufBytes, byte];
             font: var nk_user_font): nk_context =
  font.height = 16.0
  font.width  = stubWidth
  var ctx: nk_context
  let ok = raddyCtxInit(addr ctx, addr font, addr buf[0], nk_size(RaddyCmdBufBytes))
  doAssert ok, "raddyCtxInit failed"
  ctx

# ---------------------------------------------------------------------------
# Demo UI mirroring examples/demo.nim — exercises every widget family
# ---------------------------------------------------------------------------

var clickCount = 0
var checkA     = false
var checkB     = true
var sliderVal  = 50.0f
var editBuf    = "Hello, raddy!"

proc buildDemoUI(ctx: ptr nk_context) =
  ## Replicate examples/demo.nim buildUI exactly — same widget sequence.
  ## Headless: no render pass, no scissor — only the Nuklear command build phase.
  let flags = NK_WINDOW_BORDER.nk_flags or
              NK_WINDOW_MOVABLE.nk_flags or
              NK_WINDOW_TITLE.nk_flags
  let bounds = nk_rect(x: 0, y: 0, w: 400, h: 540)

  if not raddyBegin(ctx, "demo smoke", bounds, flags):
    raddyEnd(ctx)
    return

  raddyLayoutRowDynamic(ctx, height = 20, cols = 1)
  raddyLabel(ctx, "Labels")
  raddyLayoutRowDynamic(ctx, height = 20, cols = 2)
  raddyLabel(ctx, "left-aligned",   NK_TEXT_LEFT)
  raddyLabel(ctx, "right-aligned",  NK_TEXT_RIGHT)
  raddyLayoutRowDynamic(ctx, height = 20, cols = 1)
  raddyLabel(ctx, "centered",       NK_TEXT_CENTERED)

  raddyLayoutRowDynamic(ctx, height = 8, cols = 1)
  raddySpacing(ctx, 1)

  raddyLayoutRowDynamic(ctx, height = 20, cols = 1)
  raddyLabel(ctx, "Buttons")
  raddyLayoutRowDynamic(ctx, height = 30, cols = 2)
  if raddyButton(ctx, "Click me"):
    inc clickCount
  raddyLabel(ctx, "Clicks: " & $clickCount, NK_TEXT_LEFT)

  raddyLayoutRowDynamic(ctx, height = 8, cols = 1)
  raddySpacing(ctx, 1)
  raddyLayoutRowDynamic(ctx, height = 20, cols = 1)
  raddyLabel(ctx, "Checkboxes")
  raddyLayoutRowDynamic(ctx, height = 25, cols = 1)
  discard raddyCheckbox(ctx, "Option A", checkA)
  discard raddyCheckbox(ctx, "Option B", checkB)

  raddyLayoutRowDynamic(ctx, height = 8, cols = 1)
  raddySpacing(ctx, 1)
  raddyLayoutRowDynamic(ctx, height = 25, cols = 1)
  discard raddySlider(ctx, 0.0f, sliderVal, 100.0f, step = 1.0f)
  raddyLayoutRowDynamic(ctx, height = 20, cols = 1)
  raddyLabel(ctx, "Slider value: " & $int(sliderVal))

  raddyLayoutRowDynamic(ctx, height = 8, cols = 1)
  raddySpacing(ctx, 1)
  raddyLayoutRowDynamic(ctx, height = 20, cols = 1)
  raddyLabel(ctx, "Edit field")
  raddyLayoutRowDynamic(ctx, height = 30, cols = 1)
  discard raddyEdit(ctx, NK_EDIT_FIELD_FLAGS, editBuf, maxLen = 127)

  raddyLayoutRowDynamic(ctx, height = 8, cols = 1)
  raddySpacing(ctx, 1)
  raddyLayoutRowDynamic(ctx, height = 20, cols = 1)
  raddyLabel(ctx, "Scrolled group")
  raddyLayoutRowDynamic(ctx, height = 120, cols = 1)

  if raddyGroupBegin(ctx, "items", NK_WINDOW_BORDER.nk_flags):
    raddyLayoutRowDynamic(ctx, height = 20, cols = 1)
    for i in 1..12:
      raddyLabel(ctx, "Group item " & $i)
    raddyGroupEnd(ctx)

  raddyEnd(ctx)

# ---------------------------------------------------------------------------
# Acceptance tests
# ---------------------------------------------------------------------------

const SmokeFrames = 5

spec "demo UI smoke (headless, N=" & $SmokeFrames & " frames)":

  var buf:  array[RaddyCmdBufBytes, byte]
  var font: nk_user_font
  var ctx = makeCtx(buf, font)

  it "raddyCtxInit succeeded":
    verify:
      ctx.memory.size > 0

  for frame in 1..SmokeFrames:
    # Simulate input begin/end (no real device; just signals Nuklear that
    # input collection is done so layout procs can proceed).
    raddyInputBegin(addr ctx)
    raddyInputEnd(addr ctx)

    buildDemoUI(addr ctx)

    let allocated = ctx.memory.allocated
    let needed    = ctx.memory.needed
    let capacity  = ctx.memory.size

    it "frame " & $frame & ": command buffer non-empty (allocated > 0)":
      verify:
        allocated > 0

    it "frame " & $frame & ": no buffer overflow (needed <= capacity)":
      verify:
        needed <= capacity

    # Advance to next frame (mirrors raddyBundleClear / nk_clear semantics).
    var overflow = false
    raddyCtxClear(addr ctx, overflow)

    it "frame " & $frame & ": raddyCtxClear reported no overflow":
      verify:
        not overflow

  raddyCtxFree(addr ctx)
