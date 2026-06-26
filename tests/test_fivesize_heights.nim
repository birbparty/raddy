## test_fivesize_heights.nim — five-size font-switch end-to-end (headless).
##
## Proves the multi-size switch path (raddyMakeFont + setRaddyFont) really drives
## the per-command draw size: in ONE nk_begin/nk_end frame we switch the active
## font five times (8/10/16/20/32 px) and emit one label after each switch, then
## walk the Nuklear command queue and assert the five emitted NK_COMMAND_TEXT
## entries carry the five DISTINCT heights.
##
## This is the renderer-relevant field: render.nim reads cmd.height at
## NK_COMMAND_TEXT (cf. docs/command-matrix.md), and nk_command_text.height is set
## by Nuklear to the active style font's height at emit time. So distinct command
## heights from one queue == the font switch genuinely took effect per group.
##
## HEADLESS: no real raylib, no GL context, no font asset. The RaddyFonts are
## built via raddyMakeFont(nil, size) — a nil RFont is the documented "usable but
## non-rendering" case (the self-guarding width callback returns 0 before ever
## reaching MeasureTextEx), so the queue still receives text commands carrying the
## font heights. Runs under the normal stubbed `nimble test`.

import std/algorithm             ## sort
import bddy
import raddy                      ## ctx lifecycle, layout, widgets, setRaddyFont, types
import raddy/backend/font         ## RaddyFont, raddyMakeFont, raddyFontHandle

{.warning[UnusedImport]: off.}

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
    {.importc: "nk__begin", header: nkH.}

proc nkNext(ctx: ptr nk_context; cmd: ptr nk_command): ptr nk_command
    {.importc: "nk__next", header: nkH.}

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

  # Distinct default-context font height (7 px) NOT in FontSizes — proves any
  # stray non-label text (it should be none) would not collide with a size we test.
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
  if raddyBegin(ctx.addr, "fivesize", bounds, NK_WINDOW_BORDER.nk_flags):
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

  it "emitted exactly five text commands (one per font group)":
    verify:
      textHeights.len == 5

  it "the five text-command heights are the five switched font sizes":
    var sorted = textHeights
    sorted.sort()
    verify:
      sorted == @[8.0f32, 10.0f32, 16.0f32, 20.0f32, 32.0f32]

  it "the five text-command heights are all distinct":
    var seen: seq[float32]
    var allDistinct = true
    for h in textHeights:
      if h in seen: allDistinct = false
      seen.add(h)
    verify:
      allDistinct and seen.len == 5

  # Each command's height equals its font handle's height (cmd.height == font.height),
  # which is the contract render.nim relies on at NK_COMMAND_TEXT.
  it "every text-command height matches a built font's height":
    var allMatch = true
    for h in textHeights:
      var found = false
      for f in fonts:
        if f.nkFont.height == h: found = true
      if not found: allMatch = false
    verify:
      allMatch

  var overflow = false
  raddyCtxClear(addr ctx, overflow)
  raddyCtxFree(addr ctx)
