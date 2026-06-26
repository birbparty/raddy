## test_fivesize_heights.nim — five-size font-switch end-to-end (headless).
##
## Proves the multi-size switch path (raddyMakeFont + setRaddyFont) really drives
## the per-command draw size: in ONE nk_begin/nk_end frame we switch the active
## font five times (8/10/16/20/32 px) and emit one label after each switch, then
## walk the Nuklear command queue and assert the five emitted NK_COMMAND_TEXT
## entries carry the five DISTINCT heights.
##
## This is the renderer-relevant field: render.nim reads cmd.height at
## NK_COMMAND_TEXT (cf. docs/command-coverage.md), and nk_command_text.height is set
## by Nuklear to the active style font's height at emit time. So distinct command
## heights from one queue == the font switch genuinely took effect per group.
##
## HEADLESS: no real raylib, no GL context, no font asset. The RaddyFonts are
## built via raddyMakeFont(nil, size) — a nil RFont is the documented "usable but
## non-rendering" case (the self-guarding width callback returns 0 before ever
## reaching MeasureTextEx), so the queue still receives text commands carrying the
## font heights. Runs under the normal stubbed `nimble test`.

import bddy
import raddy                      ## ctx lifecycle, layout, widgets, setRaddyFont, types
import raddy/backend/font         ## RaddyFont, raddyMakeFont, raddyFontHandle

const nkH = "nuklear.h"

# ---------------------------------------------------------------------------
# Linker stub — MeasureTextEx is referenced by raddyMeasureWidth (wired into
# every RaddyFont by raddyMakeFont) so the symbol must exist to link. The nil
# fontPtr guard in raddyMeasureWidth means it is never actually CALLED here; the
# stub exists purely to satisfy the linker. Mirrors tests/test_font.nim.
# ---------------------------------------------------------------------------
{.emit: """
#include "raylib.h"
Vector2 MeasureTextEx(Font font, const char *text, float fontSize, float spacing) {
  (void)font; (void)text; (void)fontSize; (void)spacing;
  Vector2 v = {0.0f, 0.0f};
  return v;
}
""".}

# ---------------------------------------------------------------------------
# Command-queue walk — bind nk__begin/nk__next directly (render.nim binds them
# privately). These iterate the per-frame command buffer; reading commands does
# not touch any raylib draw symbol, so no draw stubs are needed.
# ---------------------------------------------------------------------------

proc nkBegin(ctx: ptr nk_context): ptr nk_command
    {.importc: "nk__begin", header: nkH, sideEffect.}

proc nkNext(ctx: ptr nk_context; cmd: ptr nk_command): ptr nk_command
    {.importc: "nk__next", header: nkH, sideEffect.}

# ---------------------------------------------------------------------------
# Fixture
# ---------------------------------------------------------------------------

const FontSizes = [8.0f32, 10.0f32, 16.0f32, 20.0f32, 32.0f32]

spec "five-size font switch emits five distinct text-command heights":

  # Five caller-owned fonts at a stable array address (no copy/move while active).
  # nil RFont: usable handle, non-rendering — see raddyMakeFont's nil-fontPtr contract.
  var fonts: array[FontSizes.len, RaddyFont]
  for i, sz in FontSizes:
    fonts[i] = raddyMakeFont(nil, sz)

  # Default-context font height (7 px) deliberately NOT in FontSizes. The first
  # setRaddyFont below replaces it before any label is emitted, so it is a
  # defensive sentinel: if some unexpected text were emitted BEFORE the first
  # switch (there should be none), its 7 px height could not be mistaken for one
  # of the five sizes under test.
  var buf:  array[RaddyCmdBufBytes, byte]
  var baseFont: nk_user_font
  baseFont.height = 7.0f32
  baseFont.width  = fonts[0].nkFont.width   ## reuse the self-guarding width callback

  var ctx: nk_context
  let okInit = raddyCtxInit(addr ctx, addr baseFont,
                            addr buf[0], nk_size(RaddyCmdBufBytes))
  doAssert okInit, "raddyCtxInit failed"

  # ---- one frame: switch font between five single-label groups ----
  raddyInputBegin(addr ctx)
  raddyInputEnd(addr ctx)

  # NK_WINDOW_BORDER only — deliberately NO NK_WINDOW_TITLE so the panel emits no
  # title text command that would pollute the text-command set.
  let bounds = nk_rect(x: 0, y: 0, w: 400, h: 600)
  let opened = raddyBegin(addr ctx, "fivesize", bounds, NK_WINDOW_BORDER.nk_flags)
  doAssert opened, "raddyBegin must open the window for any text command to emit"
  for i, sz in FontSizes:
    setRaddyFont(addr ctx, raddyFontHandle(fonts[i]))
    # Generous row height so even the 32 px font is not clipped before emit.
    raddyLayoutRowDynamic(addr ctx, height = 40, cols = 1)
    raddyLabel(addr ctx, "size " & $int(sz))
  raddyEnd(addr ctx)

  # ---- walk the command queue, collect NK_COMMAND_TEXT heights ----
  var textHeights: seq[float32]
  var cmd = nkBegin(addr ctx)
  while cmd != nil:
    if cmd.`type` == NK_COMMAND_TEXT:
      let tc = cast[ptr nk_command_text](cmd)
      textHeights.add(tc.height)
    cmd = nkNext(addr ctx, cmd)

  # Exactly one text command per font group — guards against a missing emit
  # (empty queue) or a stray text command (e.g. an accidental window title)
  # before the stronger ordered checks below run.
  it "emitted exactly five text commands (one per font group)":
    verify:
      textHeights.len == 5

  # The STRONGEST claim: heights appear in the SAME order the fonts were switched
  # (8 → 10 → 16 → 20 → 32). Nuklear's command buffer is append-only in widget
  # build order, so comparing the unsorted sequence proves each switch bound to
  # the label that followed it — an off-by-one or scrambled switch that preserved
  # the multiset would still fail here. This also subsumes the length, set, and
  # distinctness properties of the emitted heights.
  it "each text-command height equals the font active when its label emitted (in order)":
    verify:
      textHeights == @[8.0f32, 10.0f32, 16.0f32, 20.0f32, 32.0f32]

  # Tie the emitted heights back to the actual switched fonts (not just the
  # literals): textHeights[i] must equal the i-th built font's height. This is
  # the cmd.height == font.height contract render.nim relies on at NK_COMMAND_TEXT.
  it "each text-command height matches its built font positionally":
    var allMatch = textHeights.len == fonts.len
    for i in 0 ..< min(textHeights.len, fonts.len):
      if textHeights[i] != fonts[i].nkFont.height: allMatch = false
    verify:
      allMatch

  # Per-frame reset must report no dropped commands. Meaningful only on the
  # fixed-buffer path (heap path always reports false); mirrors test_smoke_headless.nim.
  var overflow = false
  raddyCtxClear(addr ctx, overflow)
  when defined(raddyFixed) or defined(vita):
    it "raddyCtxClear reported no buffer overflow":
      verify:
        not overflow
  raddyCtxFree(addr ctx)
