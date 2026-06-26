## test_bundle_setfont.nim — bddy spec for raddyBundleSetFont (ctx_bundle.nim).
##
## raddyBundleSetFont is a thin additive wrapper over setRaddyFont that switches
## the bundle's ACTIVE Nuklear font to a caller-owned RaddyFont. The nk_context
## partial view (types.nim) does not expose ctx.style.font, so the switch is
## verified BEHAVIORALLY on the heap path: build one nk_begin/nk_end frame on the
## bundle's context, switch the font via the wrapper, emit a label, then walk the
## command queue and assert the emitted NK_COMMAND_TEXT carries the switched
## font's handle + height.
##
## Path split mirrors tests/test_render.nim: command-CONTENT assertions run only
## on the heap path (nk_init_default). On the fixed-buffer path (-d:raddyFixed /
## vita) nk__begin/nk__next over a ref-embedded bundle buffer does not surface the
## command content the same way (tracked separately in raddy-ac3), so the fixed
## path gets a structural check (switch + emit does not crash and commits bytes).
##
## HEADLESS: no real raylib / GL. The switched RaddyFont uses a nil RFont (the
## documented usable-but-non-rendering case — raddyMeasureWidth self-guards before
## MeasureTextEx), so no draw symbol is needed; the MeasureTextEx stub exists only
## to satisfy the linker for the font width callbacks. Runs under stubbed
## `nimble test`.

import bddy
import raddy                       ## frame API (raddyBegin/Label/End, input, nk_rect), types
import raddy/backend/ctx_bundle    ## RaddyCtxBundle, raddyBundleCreate/Ctx/SetFont/Clear/Free
import raddy/backend/font          ## RaddyFont, raddyMakeFont, raddyFontHandle
import raddy/backend/raylib_api    ## RFont

const nkH = "nuklear.h"

# MeasureTextEx linker stub — see test_ctx_bundle.nim / test_font.nim for rationale.
{.emit: """
#include "raylib.h"
Vector2 MeasureTextEx(Font font, const char *text, float fontSize, float spacing) {
  (void)font; (void)text; (void)fontSize; (void)spacing;
  Vector2 v = {0.0f, 0.0f};
  return v;
}
""".}

# Command-queue walk — bind nk__begin/nk__next directly (render.nim binds them
# privately). Reading commands touches no raylib draw symbol.
proc nkBegin(ctx: ptr nk_context): ptr nk_command
    {.importc: "nk__begin", header: nkH, sideEffect.}
proc nkNext(ctx: ptr nk_context; cmd: ptr nk_command): ptr nk_command
    {.importc: "nk__next", header: nkH, sideEffect.}

# Build one frame on `ctx`: open a borderless (no-title) window, switch the active
# font to `rf` via the wrapper, emit a single label. Returns nothing — the caller
# inspects the resulting command queue / buffer state.
proc switchAndEmit(bundle: RaddyCtxBundle; rf: var RaddyFont) =
  let ctx = raddyBundleCtx(bundle)
  raddyInputBegin(ctx)
  raddyInputEnd(ctx)
  let opened = raddyBegin(ctx, "setfont", nk_rect(x: 0, y: 0, w: 300, h: 200),
                          NK_WINDOW_BORDER.nk_flags)   ## no title → no stray text
  doAssert opened, "raddyBegin must open the window"
  raddyBundleSetFont(bundle, rf)
  raddyLayoutRowDynamic(ctx, height = 40, cols = 1)
  raddyLabel(ctx, "switched")
  raddyEnd(ctx)

spec "raddyBundleSetFont":

  it "is a no-op (no crash) on a nil bundle":
    var bundle: RaddyCtxBundle = nil
    var rf = raddyMakeFont(nil, 16.0f)
    raddyBundleSetFont(bundle, rf)   ## must return early, never deref bundle.ctx
    verify:
      true

when not (defined(raddyFixed) or defined(vita)):
  ## Heap path (nk_init_default): the command queue surfaces content via
  ## nk__begin/nk__next, so we can assert the SWITCH actually changed the font the
  ## emitted text command carries.
  spec "raddyBundleSetFont switches the active font (heap path)":

    it "the emitted text command carries the switched handle + height":
      # Base font (height 16) is the bundle default; we switch to a distinct 28 px
      # font before emitting the only label, so the text command must carry the
      # 28 px font — proving the wrapper changed ctx.style.font.
      var baseFont: RFont
      var bundle = raddyBundleCreate(addr baseFont, 16.0f)
      doAssert bundle.ctxOk, "bundle ctx init failed"

      # Switched font at a stable local address (single scope, never moved/copied).
      var rf = raddyMakeFont(nil, 28.0f)   ## nil RFont: handle-only switch, headless
      switchAndEmit(bundle, rf)

      var fonts: seq[ptr nk_user_font]
      var heights: seq[float32]
      let ctx = raddyBundleCtx(bundle)
      var cmd = nkBegin(ctx)
      while cmd != nil:
        if cmd.`type` == NK_COMMAND_TEXT:
          let tc = cast[ptr nk_command_text](cmd)
          fonts.add(tc.font)
          heights.add(tc.height)
        cmd = nkNext(ctx, cmd)

      verify:
        fonts.len == 1
        fonts[0] == raddyFontHandle(rf)   ## the switched handle, not the bundle default
        heights[0] == 28.0f32             ## the switched font's height, not the base 16

      var overflow = false
      raddyBundleClear(bundle, overflow)
      raddyBundleFree(bundle)

when defined(raddyFixed) or defined(vita):
  ## Fixed-buffer path: command-content walking over a ref-embedded bundle buffer
  ## is tracked separately (raddy-ac3). Here we assert the switch + emit path is
  ## crash-free and commits command bytes into the bundle's fixed buffer.
  spec "raddyBundleSetFont switches the active font (fixed path — structural)":

    it "switch + emit commits commands without overflow":
      var baseFont: RFont
      var bundle = raddyBundleCreate(addr baseFont, 16.0f)
      doAssert bundle.ctxOk, "bundle ctx init failed"

      var rf = raddyMakeFont(nil, 28.0f)
      switchAndEmit(bundle, rf)

      let allocated = raddyBundleCtx(bundle).memory.allocated
      var overflow = false
      raddyBundleClear(bundle, overflow)
      raddyBundleFree(bundle)

      verify:
        allocated > 0      ## the frame produced command bytes
        not overflow       ## buffer did not overflow
