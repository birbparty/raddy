## tests/acceptance_smoke.nim — real-raylib acceptance spec (raddy-8an.9)
##
## DELIBERATELY named WITHOUT the substring `test_` so raddy.nimble's stubbed
## `test` task glob (which runs every tests/*.nim containing `test_` under emit
## stubs) never picks it up. Run it ONLY via the dedicated real-raylib target:
##
##   nimble acceptance        # links real naylib + opens a hidden GL window
##
## See docs/prompts/acceptance-test-model.md (the raddy-8an.2 decision) for the
## task wiring, window strategy, and headless fallback.
##
## What this proves (machine-checkable, on a real GL context):
##   - the bundled CC0 font (tests/assets/unscii-16.ttf) bakes at TWO distinct
##     ppem via separate loadFont calls (one atlas per size, not one scaled);
##   - raddy's width callback (raddyMeasureWidth) agrees with raylib's
##     MeasureTextEx within <=1px PER LINE at each size, spacing = 2.0
##     (RaddyMeasureSpacing) — the core font-binding contract;
##   - one frame mixing text + a filled rect + a rect outline, with the active
##     font switched between groups, drains through raddyRender into a
##     RenderTexture without buffer overflow.
##
## RALPH GATE: this needs a real GL/window context. If InitWindow cannot obtain
## one (`isWindowReady()` is false), the doAssert below aborts — a headless SKIP
## is NOT a pass. In that case flag the bead for human/on-device execution:
##   bd update raddy-8an.9 --add-label human   (then: bd human list)

import std/os
import raylib                       ## naylib — the REAL raylib (not the test stub)
import bddy
import raddy                        ## frame API + types (raddyBegin/Label/Button/End, nk_rect, NK_WINDOW_*)
import raddy/backend/ctx_bundle     ## RaddyCtxBundle lifecycle
import raddy/backend/render         ## raddyRender
import raddy/backend/font           ## RaddyFont, raddyMakeFont, raddyFontHandle, raddyMeasureWidth
import raddy/backend/raylib_api     ## RFont (cast bridge from naylib Font)

const
  assetsDir = currentSourcePath().parentDir / "assets"
  fontPath  = assetsDir / "unscii-16.ttf"
  FbW       = 320'i32
  FbH       = 240'i32
  Spacing   = 2.0f32   ## MUST equal RaddyMeasureSpacing (font.nim) — measure/draw parity

# Module-level storage: both the naylib Font and the RaddyFont must live at a
# STABLE address until after raddyRender consumes the frame (the RFont ptr and
# the nk_user_font ptr both escape into Nuklear). See docs/prompts/font-contract.md.
var
  font16: Font
  font32: Font
  rf16:   RaddyFont
  rf32:   RaddyFont

# --- RALPH GATE: real GL/window context -------------------------------------
setConfigFlags(flags(WindowHidden))          ## FLAG_WINDOW_HIDDEN — set BEFORE initWindow
initWindow(FbW, FbH, "raddy acceptance")
doAssert isWindowReady(),
  "no GL context — acceptance spec cannot run headlessly. Flag raddy-8an.9 " &
  "for human/on-device (bd update raddy-8an.9 --add-label human). SKIP is NOT a pass."

# Two distinct sizes, one bake per ppem (NOT one atlas scaled). `0` glyphCount =
# raylib's default ASCII set (95 glyphs). RFont is a distinct Nim type aliasing
# naylib's Font (same C struct) — bridge with cast[ptr RFont].
font16 = loadFont(fontPath, 16, 0)
font32 = loadFont(fontPath, 32, 0)
doAssert font16.texture.id != 0, "unscii-16.ttf failed to bake at 16 px"
doAssert font32.texture.id != 0, "unscii-16.ttf failed to bake at 32 px"
rf16 = raddyMakeFont(cast[ptr RFont](addr font16), float32(font16.baseSize))
rf32 = raddyMakeFont(cast[ptr RFont](addr font32), float32(font32.baseSize))

proc widthRaddy(rf: var RaddyFont; s: string; ppem: float32): float32 =
  ## raddy's Nuklear width callback path: reads the RFont from the font handle's
  ## userdata, measures via MeasureTextEx(font, s, ppem, RaddyMeasureSpacing).
  raddyMeasureWidth(rf.nkFont.userdata, ppem, s.cstring, s.len.cint)

proc widthRaylib(f: Font; s: string; ppem: float32): float32 =
  ## Direct raylib measurement with the SAME spacing the callback uses.
  measureText(f, s, ppem, Spacing).x

const Sample = "Width parity 123"   ## known multi-glyph, single line

spec "raddy acceptance (real raylib, hidden GL window)":

  it "bundled unscii-16.ttf bakes at two distinct ppem (16 and 32)":
    verify:
      font16.texture.id != 0
      font32.texture.id != 0
      font16.baseSize == 16
      font32.baseSize == 32

  it "raddyMeasureWidth matches raylib MeasureTextEx within <=1px at 16 px":
    let delta = abs(widthRaddy(rf16, Sample, 16.0f) - widthRaylib(font16, Sample, 16.0f))
    verify:
      delta <= 1.0f

  it "raddyMeasureWidth matches raylib MeasureTextEx within <=1px at 32 px":
    let delta = abs(widthRaddy(rf32, Sample, 32.0f) - widthRaylib(font32, Sample, 32.0f))
    verify:
      delta <= 1.0f

  it "one frame: text + filled rect + rect outline + font switch renders, no overflow":
    let bundle = raddyBundleCreate(cast[ptr RFont](addr font16), float32(font16.baseSize))
    doAssert bundle.ctxOk, "bundle ctx init failed"
    let ctx = raddyBundleCtx(bundle)

    raddyInputBegin(ctx)
    raddyInputEnd(ctx)

    # NK_WINDOW_BORDER emits a rect OUTLINE; raddyButton emits a filled rect; the
    # labels emit text. The active font is switched between the two groups.
    let flags = NK_WINDOW_BORDER.nk_flags or NK_WINDOW_TITLE.nk_flags
    if raddyBegin(ctx, "acceptance", nk_rect(x: 10, y: 10, w: 280, h: 200), flags):
      setRaddyFont(ctx, raddyFontHandle(rf16))            ## 16 px group
      raddyLayoutRowDynamic(ctx, height = 20, cols = 1)
      raddyLabel(ctx, "small text")                       ## TEXT
      raddyLayoutRowDynamic(ctx, height = 30, cols = 1)
      discard raddyButton(ctx, "filled")                  ## RECT_FILLED (+ border + text)
      setRaddyFont(ctx, raddyFontHandle(rf32))            ## switch → 32 px group
      raddyLayoutRowDynamic(ctx, height = 40, cols = 1)
      raddyLabel(ctx, "BIG")                              ## TEXT at 32 px
    raddyEnd(ctx)                                         ## every frame, regardless of return

    # raddyRender requires a RenderTexture target (its scissor Y-flip assumes an
    # FBO origin; direct-to-screen is unsupported). Pass explicit framebuffer
    # height — NEVER getScreenHeight (0 on the Vita binding).
    let rt = loadRenderTexture(FbW, FbH)
    beginTextureMode(rt)
    var overflow = false
    raddyRender(ctx, rt.texture.height, overflow)
    endTextureMode()

    raddyBundleFree(bundle)
    verify:
      not overflow              ## heap path: always false; asserts the contract holds

  it "raddyMeasureWidth is monotonic in ppem (32 px wider than 16 px)":
    verify:
      widthRaddy(rf32, Sample, 32.0f) > widthRaddy(rf16, Sample, 16.0f)

closeWindow()
