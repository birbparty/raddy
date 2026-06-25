## render.nim — Nuklear command-queue translator for raddy.
##
## raddyRender walks nk__begin/nk__next and dispatches each Nuklear command to
## the appropriate raylib draw call (via raylib_api.nim procs only).
##
## First-pass commands with real implementations:
##   NK_COMMAND_NOP          — skip
##   NK_COMMAND_SCISSOR      — BeginScissorMode (Y-flip, replace semantics)
##   NK_COMMAND_LINE         — DrawLineEx
##   NK_COMMAND_RECT         — DrawRectangleLinesEx / DrawRectangleRoundedLinesEx
##   NK_COMMAND_RECT_FILLED  — DrawRectangleRec / DrawRectangleRounded
##   NK_COMMAND_TEXT         — DrawTextEx (stack buffer, no Nim string)
##
## Every other NK_COMMAND_* type is a logged no-op. Each type logs once, then
## silences further warnings. NEVER call nk_convert — the vertex path is compiled
## out (NK_INCLUDE_VERTEX_BUFFER_OUTPUT not set) and its symbols do not link.
##
## raddyRender calls nk_clear on exit. Do NOT also call raddyBundleClear in the
## same frame — that would double-clear. Use raddyBundleClear only when NOT
## calling raddyRender (e.g., headless / off-frame processing).
##
## Decoupled-core exception: backend/ may reference platform types (RColor, etc.).
## Consumers call raddyRender; they never import raylib_api directly.

import ../types    ## nk_context, nk_command, NkCommandType, nk_command_*
import ../errors   ## raddyLog
import ./raylib_api ## rDraw* procs, RColor, RVec2, RRect, RFont
import ./geom      ## toRColor, rectRoundness, RoundedRectSegs
import ./scissor   ## scissorYFlip
import ./font      ## RaddyMeasureSpacing

const nkH = "nuklear.h"

# ---------------------------------------------------------------------------
# Nuklear command-queue iteration (NEVER use nk_convert — not linked)
# Nim rejects double-underscore identifiers; bind C nk__begin/nk__next via importc.
# ---------------------------------------------------------------------------

proc nkBegin(ctx: ptr nk_context): ptr nk_command
    {.importc: "nk__begin", header: nkH.}

proc nkNext(ctx: ptr nk_context; cmd: ptr nk_command): ptr nk_command
    {.importc: "nk__next", header: nkH.}

proc nkClear(ctx: ptr nk_context)
    {.importc: "nk_clear", header: nkH, sideEffect.}

# ---------------------------------------------------------------------------
# Per-command-type no-op warning (fires once per type, then silences)
# ---------------------------------------------------------------------------

const nkCmdCount = ord(NK_COMMAND_CUSTOM) + 1  ## 19 total command types
var noopWarned {.global.}: array[nkCmdCount, bool]

# ---------------------------------------------------------------------------
# raddyRender
# ---------------------------------------------------------------------------

proc raddyRender*(ctx: ptr nk_context; framebufferH: int32;
                  bufOverflow: var bool) {.raises: [].} =
  ## Drain the Nuklear command queue and dispatch draw calls to raylib.
  ##
  ## ctx:         pointer to the nk_context (from raddyBundleCtx or raddyCtxInit).
  ## framebufferH: height of the current render target in pixels.
  ##              Pass RenderTexture.texture.height inside BeginTextureMode,
  ##              or GetScreenHeight() when rendering directly to the screen.
  ##              Required for NK_COMMAND_SCISSOR Y-flip.
  ## bufOverflow: set true if the Nuklear command buffer overflowed this frame
  ##              (vita/raddyFixed path only). Commands were dropped when true.
  ##
  ## Calls nk_clear on exit. Do NOT also call raddyBundleClear the same frame.
  var scissorActive = false

  var cmd = nkBegin(ctx)
  while cmd != nil:
    case cmd.`type`

    of NK_COMMAND_NOP:
      discard

    of NK_COMMAND_SCISSOR:
      let sc = cast[ptr nk_command_scissor](cmd)
      ## Replace semantics: close any active scissor before opening a new one.
      if scissorActive: rEndScissorMode()
      let (sx, sy, sw, sh) = scissorYFlip(sc.x.int32, sc.y.int32,
                                           sc.w.int32, sc.h.int32,
                                           framebufferH)
      rBeginScissorMode(sx, sy, sw, sh)
      scissorActive = true

    of NK_COMMAND_LINE:
      let lc = cast[ptr nk_command_line](cmd)
      rDrawLineEx(
        RVec2(x: lc.`begin`.x.float32, y: lc.`begin`.y.float32),
        RVec2(x: lc.`end`.x.float32,   y: lc.`end`.y.float32),
        lc.line_thickness.float32,
        toRColor(lc.color)
      )

    of NK_COMMAND_RECT:
      let rc = cast[ptr nk_command_rect](cmd)
      let r = RRect(x: rc.x.float32, y: rc.y.float32,
                    width: rc.w.float32, height: rc.h.float32)
      if rc.rounding == 0:
        rDrawRectangleLinesEx(r, rc.line_thickness.float32, toRColor(rc.color))
      elif rc.w > 0 and rc.h > 0:
        rDrawRectangleRoundedLinesEx(
          r,
          rectRoundness(rc.rounding.float32, rc.w.float32, rc.h.float32),
          RoundedRectSegs,
          rc.line_thickness.float32,
          toRColor(rc.color)
        )

    of NK_COMMAND_RECT_FILLED:
      let rf = cast[ptr nk_command_rect_filled](cmd)
      let r = RRect(x: rf.x.float32, y: rf.y.float32,
                    width: rf.w.float32, height: rf.h.float32)
      if rf.rounding == 0:
        rDrawRectangleRec(r, toRColor(rf.color))
      elif rf.w > 0 and rf.h > 0:
        rDrawRectangleRounded(
          r,
          rectRoundness(rf.rounding.float32, rf.w.float32, rf.h.float32),
          RoundedRectSegs,
          toRColor(rf.color)
        )

    of NK_COMMAND_TEXT:
      let tc = cast[ptr nk_command_text](cmd)
      ## tc.font is ptr nk_user_font; its userdata.ptr holds the ptr RFont stored
      ## by raddyInitFont. nil check required — Nuklear may emit text with a
      ## fallback font before the host has set one.
      let fontPtr = cast[ptr RFont](tc.font.userdata.ptr)
      if fontPtr != nil and tc.length > 0:
        ## Stack buffer: NK text is NOT null-terminated (length is byte count).
        ## NEVER construct a Nim string from tc.`string` — `$ptr` reads past valid
        ## memory. copyMem + null-terminate is the only safe pattern.
        const MaxTextBytes = 1024
        var buf: array[MaxTextBytes, char]
        let copyLen = min(int(tc.length), MaxTextBytes - 1)
        copyMem(addr buf[0], addr tc.`string`[0], copyLen)
        buf[copyLen] = '\0'
        rDrawTextEx(
          fontPtr[],
          cast[cstring](addr buf[0]),
          RVec2(x: tc.x.float32, y: tc.y.float32),
          tc.height,
          RaddyMeasureSpacing,  ## must match MeasureTextEx spacing in font.nim
          toRColor(tc.foreground)
        )
        ## tc.background intentionally ignored — Nuklear pre-fills it with a
        ## separate NK_COMMAND_RECT_FILLED before this command.

    else:
      ## Unimplemented command type — log once, then silence.
      ## Remaining shape handlers land in the render-shapes follow-up iteration.
      let cmdOrd = ord(cmd.`type`)
      if cmdOrd < nkCmdCount and not noopWarned[cmdOrd]:
        noopWarned[cmdOrd] = true
        raddyLog("raddyRender: " & $cmd.`type` & " no-op — not yet implemented (silenced)")

    cmd = nkNext(ctx, cmd)

  ## Close any open scissor region before returning.
  if scissorActive:
    rEndScissorMode()

  ## Overflow check: on vita/raddyFixed, `needed > size` means commands were dropped.
  ## Must happen BEFORE nk_clear (which resets the buffer pointers).
  when defined(vita) or defined(raddyFixed):
    bufOverflow = ctx.memory.needed > ctx.memory.size
    if bufOverflow:
      raddyLog("raddyRender: Nuklear command buffer full — some commands were dropped")
  else:
    bufOverflow = false

  nkClear(ctx)
