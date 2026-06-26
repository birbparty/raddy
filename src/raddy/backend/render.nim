## render.nim — Nuklear command-queue translator for raddy.
##
## raddyRender walks nk__begin/nk__next and dispatches each Nuklear command to
## the appropriate raylib draw call (via raylib_api.nim procs only).
##
## Implemented commands:
##   NK_COMMAND_NOP              — skip
##   NK_COMMAND_SCISSOR          — BeginScissorMode (Y-flip, replace semantics)
##   NK_COMMAND_LINE             — DrawLineEx
##   NK_COMMAND_CURVE            — Bézier tessellation (BezierSegs segments) + DrawLineStrip or DrawLineEx
##   NK_COMMAND_RECT             — DrawRectangleLinesEx / DrawRectangleRoundedLinesEx
##   NK_COMMAND_RECT_FILLED      — DrawRectangleRec / DrawRectangleRounded
##   NK_COMMAND_RECT_MULTI_COLOR — DrawRectangleGradientEx (corner-color approximation)
##   NK_COMMAND_CIRCLE           — DrawRing (circle) / DrawEllipseLines (ellipse; no-op vita)
##   NK_COMMAND_CIRCLE_FILLED    — DrawCircleSector / DrawEllipse (no-op vita)
##   NK_COMMAND_ARC              — DrawRing (partial arc, line_thickness → innerR)
##   NK_COMMAND_ARC_FILLED       — DrawCircleSector
##   NK_COMMAND_TRIANGLE         — DrawTriangleLines (winding corrected)
##   NK_COMMAND_TRIANGLE_FILLED  — DrawTriangle (winding corrected)
##   NK_COMMAND_POLYGON          — DrawLineStrip closed (capped at PolyLineMax)
##   NK_COMMAND_POLYGON_FILLED   — fan triangulation via DrawTriangle (capped)
##   NK_COMMAND_POLYLINE         — DrawLineStrip (capped at PolyLineMax)
##   NK_COMMAND_TEXT             — DrawTextEx (stack buffer, no Nim string)
##   NK_COMMAND_IMAGE            — DrawTextureRec (handle.ptr → ptr RTexture)
##   NK_COMMAND_CUSTOM           — no-op (C callback; host handles if needed)
##
## NEVER call nk_convert — the vertex path is compiled out
## (NK_INCLUDE_VERTEX_BUFFER_OUTPUT not set) and its symbols do not link.
##
## raddyRender calls nk_clear on exit. Do NOT also call raddyBundleClear in the
## same frame — that would double-clear. Use raddyBundleClear only when NOT
## calling raddyRender (e.g., headless / off-frame processing).
##
## Decoupled-core exception: backend/ may reference platform types (RColor, etc.).
## Consumers call raddyRender; they never import raylib_api directly.

import ../types    ## nk_context, nk_command, NkCommandType, nk_command_*
import ../errors   ## raddyLog
import ./raylib_api ## rDraw* procs, RColor, RVec2, RRect, RFont, RTexture
import ./geom      ## toRColor, rectRoundness, RoundedRectSegs, BezierSegs, ArcSegs,
                   ## PolyLineMax, bezierTessellate, radToDeg, fixTriWinding
## scissor.nim is no longer imported: BeginScissorMode handles FBO Y-flip internally.
import ./font      ## RaddyMeasureSpacing

const nkH = "nuklear.h"

# ---------------------------------------------------------------------------
# Nuklear command-queue iteration (NEVER use nk_convert — not linked)
# Nim rejects double-underscore identifiers; bind C nk__begin/nk__next via importc.
# ---------------------------------------------------------------------------

proc nkBegin(ctx: ptr nk_context): ptr nk_command
    {.importc: "nk__begin", header: nkH, sideEffect.}

proc nkNext(ctx: ptr nk_context; cmd: ptr nk_command): ptr nk_command
    {.importc: "nk__next", header: nkH, sideEffect.}

proc nkClear(ctx: ptr nk_context)
    {.importc: "nk_clear", header: nkH, sideEffect.}

# ---------------------------------------------------------------------------
# Per-command-type no-op warning (fires once per type, then silences)
# ---------------------------------------------------------------------------

const nkCmdCount = ord(NK_COMMAND_CUSTOM) + 1  ## 19 total command types
static: doAssert ord(NK_COMMAND_CUSTOM) == 18, "NkCommandType layout changed — update nkCmdCount"

## One-per-process truncation sentinel for NK_COMMAND_TEXT oversize payloads.
var textTruncWarnEmitted {.global.} = false

## One shared latch across POLYGON / POLYGON_FILLED / POLYLINE: the first
## truncation anywhere in the polygon family warns once for the whole process.
## Intentional — avoids log spam in animation loops where many polys may
## exceed PolyLineMax every frame.
var polyTruncWarnEmitted {.global.} = false

## Vita-only: warn once when the ellipse (non-square CIRCLE/CIRCLE_FILLED)
## no-op path is hit, so host authors notice missing UI instead of debugging
## blank space.
when defined(vita):
  var ellipseNoopWarnEmitted {.global.} = false

# ---------------------------------------------------------------------------
# raddyRender
# ---------------------------------------------------------------------------

proc raddyRender*(ctx: ptr nk_context; framebufferH: int32;
                  bufOverflow: var bool) {.raises: [].} =
  ## Drain the Nuklear command queue and dispatch draw calls to raylib.
  ##
  ## ctx:         pointer to the nk_context (from raddyBundleCtx or raddyCtxInit).
  ## framebufferH: retained for API compatibility; no longer used for scissor flip.
  ##              raylib's BeginScissorMode internally applies the FBO Y-flip
  ##              (rlScissor(x, FboH-(y+h), w, h)) when CORE.Window.usingFbo is set,
  ##              so Nuklear's Y-down coords must be forwarded UNCHANGED. An extra flip
  ##              here would double-invert the scissor and push it off-screen.
  ## bufOverflow: set true if the Nuklear command buffer overflowed this frame
  ##              (vita/raddyFixed path only). Commands were dropped when true.
  ##              Text longer than RaddyMaxTextBytes (1024) per NK_COMMAND_TEXT is
  ##              silently truncated to RaddyMaxTextBytes-1 bytes (logged once).
  ##
  ## Calls nk_clear on exit. Do NOT also call raddyBundleClear the same frame.
  if ctx == nil:
    ## Graceful nil-ctx guard: prefer early-return over assert because assert
    ## compiles out under -d:release/-d:danger, where a nil-deref crash is
    ## hardest to diagnose on-device (vita).
    raddyLog("raddyRender: ctx is nil — skipping frame")
    bufOverflow = false
    return
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
      ## Forward Nuklear's Y-down coordinates directly. BeginScissorMode handles the
      ## FBO Y-flip internally (rcore.c: rlScissor(x, FboH-(y+h), w, h)).
      ## Do NOT pre-flip: double-flipping would push the scissor to the wrong region.
      rBeginScissorMode(sc.x.int32, sc.y.int32, sc.w.int32, sc.h.int32)
      scissorActive = true

    of NK_COMMAND_LINE:
      let lc = cast[ptr nk_command_line](cmd)
      rDrawLineEx(
        RVec2(x: lc.`begin`.x.float32, y: lc.`begin`.y.float32),
        RVec2(x: lc.`end`.x.float32,   y: lc.`end`.y.float32),
        lc.line_thickness.float32,
        toRColor(lc.color)
      )

    of NK_COMMAND_CURVE:
      ## Cubic Bézier: tessellate on the stack then draw as a line strip or thick segments.
      let cv = cast[ptr nk_command_curve](cmd)
      var pts: array[BezierSegs + 1, RVec2]
      bezierTessellate(
        RVec2(x: cv.`begin`.x.float32, y: cv.`begin`.y.float32),
        RVec2(x: cv.ctrl[0].x.float32, y: cv.ctrl[0].y.float32),
        RVec2(x: cv.ctrl[1].x.float32, y: cv.ctrl[1].y.float32),
        RVec2(x: cv.`end`.x.float32,   y: cv.`end`.y.float32),
        pts
      )
      let col = toRColor(cv.color)
      ## line_thickness is nk_ushort (unsigned); <= 1 means 0 or 1 → thin strip.
      ## Do NOT change to < 1 — that would route thickness-1 curves through the
      ## slow per-segment path unnecessarily.
      if cv.line_thickness <= 1:
        rDrawLineStrip(addr pts[0], int32(BezierSegs + 1), col)
      else:
        let thick = cv.line_thickness.float32
        for i in 0 ..< BezierSegs:
          rDrawLineEx(pts[i], pts[i + 1], thick, col)

    of NK_COMMAND_RECT:
      let rc = cast[ptr nk_command_rect](cmd)
      let r = RRect(x: rc.x.float32, y: rc.y.float32,
                    width: rc.w.float32, height: rc.h.float32)
      if rc.rounding == 0:
        rDrawRectangleLinesEx(r, rc.line_thickness.float32, toRColor(rc.color))
      elif rc.w > 0 and rc.h > 0:
        ## The w>0/h>0 guard protects rectRoundness's divisor; geom.nim guards it
        ## too, so a zero-extent rounded rect would be a safe no-op either way.
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
        ## Same w>0/h>0 guard as RECT; see comment there.
        rDrawRectangleRounded(
          r,
          rectRoundness(rf.rounding.float32, rf.w.float32, rf.h.float32),
          RoundedRectSegs,
          toRColor(rf.color)
        )

    of NK_COMMAND_RECT_MULTI_COLOR:
      let mg = cast[ptr nk_command_rect_multi_color](cmd)
      if mg.w > 0 and mg.h > 0:
        ## Nuklear edge colors (left, top, bottom, right) mapped to raylib corner colors.
        ## Mapping: topLeft=left, bottomLeft=bottom, bottomRight=right, topRight=top.
        ## This is an approximation — true per-corner blending requires vertex data
        ## unavailable in the command-mode path (raddy-5ce for vita verification).
        rDrawRectangleGradientEx(
          RRect(x: mg.x.float32, y: mg.y.float32, width: mg.w.float32, height: mg.h.float32),
          toRColor(mg.left),   # topLeft
          toRColor(mg.bottom), # bottomLeft
          toRColor(mg.right),  # bottomRight
          toRColor(mg.top)     # topRight
        )

    of NK_COMMAND_CIRCLE:
      let cc = cast[ptr nk_command_circle](cmd)
      let rx = cc.w.float32 * 0.5f32
      let ry = cc.h.float32 * 0.5f32
      let cx = cc.x.float32 + rx
      let cy = cc.y.float32 + ry
      let col = toRColor(cc.color)
      if cc.w == cc.h:
        ## True circle: use ring to honour line_thickness (vita: verify DrawRing in raddy-5ce).
        let innerR = max(0.0f32, rx - cc.line_thickness.float32)
        rDrawRing(RVec2(x: cx, y: cy), innerR, rx, 0.0f32, 360.0f32, ArcSegs, col)
      else:
        ## Ellipse outline: no-op on vita (DrawEllipseLines guarded in raylib_api.nim).
        when defined(vita):
          if not ellipseNoopWarnEmitted:
            ellipseNoopWarnEmitted = true
            raddyLog("raddyRender: NK_COMMAND_CIRCLE (ellipse w!=h) is a no-op on vita (silenced)")
        rDrawEllipseLines(int32(cx), int32(cy), rx, ry, col)

    of NK_COMMAND_CIRCLE_FILLED:
      let cf = cast[ptr nk_command_circle_filled](cmd)
      let rx = cf.w.float32 * 0.5f32
      let ry = cf.h.float32 * 0.5f32
      let cx = cf.x.float32 + rx
      let cy = cf.y.float32 + ry
      let col = toRColor(cf.color)
      if cf.w == cf.h:
        rDrawCircleSector(RVec2(x: cx, y: cy), rx, 0.0f32, 360.0f32, ArcSegs, col)
      else:
        ## Ellipse fill: no-op on vita (DrawEllipse guarded in raylib_api.nim).
        when defined(vita):
          if not ellipseNoopWarnEmitted:
            ellipseNoopWarnEmitted = true
            raddyLog("raddyRender: NK_COMMAND_CIRCLE_FILLED (ellipse w!=h) is a no-op on vita (silenced)")
        rDrawEllipse(int32(cx), int32(cy), rx, ry, col)

    of NK_COMMAND_ARC:
      let ac = cast[ptr nk_command_arc](cmd)
      let outerR = ac.r.float32
      let innerR = max(0.0f32, outerR - ac.line_thickness.float32)
      ## Nuklear: absolute radians, CCW+. raylib: degrees, CW+ in Y-down screen.
      ## The math→screen Y-flip and raylib's CW sweep cancel, so NO negation is
      ## needed. We must ensure start <= end for raylib's span math — Nuklear does
      ## not guarantee this ordering.
      let arcS = radToDeg(ac.a[0])
      var arcE = radToDeg(ac.a[1])
      if arcE < arcS: arcE += 360.0f32
      rDrawRing(
        RVec2(x: ac.cx.float32, y: ac.cy.float32),
        innerR, outerR,
        arcS, arcE,
        ArcSegs, toRColor(ac.color)
      )

    of NK_COMMAND_ARC_FILLED:
      let af = cast[ptr nk_command_arc_filled](cmd)
      ## Same angle normalization as NK_COMMAND_ARC — see comment there.
      let afS = radToDeg(af.a[0])
      var afE = radToDeg(af.a[1])
      if afE < afS: afE += 360.0f32
      rDrawCircleSector(
        RVec2(x: af.cx.float32, y: af.cy.float32),
        af.r.float32,
        afS, afE,
        ArcSegs, toRColor(af.color)
      )

    of NK_COMMAND_TRIANGLE:
      let tr = cast[ptr nk_command_triangle](cmd)
      var a = RVec2(x: tr.a.x.float32, y: tr.a.y.float32)
      var b = RVec2(x: tr.b.x.float32, y: tr.b.y.float32)
      var c = RVec2(x: tr.c.x.float32, y: tr.c.y.float32)
      fixTriWinding(a, b, c)
      rDrawTriangleLines(a, b, c, toRColor(tr.color))

    of NK_COMMAND_TRIANGLE_FILLED:
      let tf = cast[ptr nk_command_triangle_filled](cmd)
      var a = RVec2(x: tf.a.x.float32, y: tf.a.y.float32)
      var b = RVec2(x: tf.b.x.float32, y: tf.b.y.float32)
      var c = RVec2(x: tf.c.x.float32, y: tf.c.y.float32)
      fixTriWinding(a, b, c)
      rDrawTriangle(a, b, c, toRColor(tf.color))

    of NK_COMMAND_POLYGON:
      let pg = cast[ptr nk_command_polygon](cmd)
      let count = pg.point_count.int32
      if count >= 2:
        let pts = cast[ptr UncheckedArray[nk_vec2i]](addr pg.points[0])
        let safeCount = min(count, PolyLineMax)
        if count > PolyLineMax and not polyTruncWarnEmitted:
          polyTruncWarnEmitted = true
          raddyLog("raddyRender: NK_COMMAND_POLYGON point_count " & $count &
                   " exceeds PolyLineMax (" & $PolyLineMax & ") — truncated (silenced)")
        ## Collect to stack, append first point to close the loop for DrawLineStrip.
        var rvec: array[PolyLineMax + 1, RVec2]
        for i in 0 ..< safeCount:
          rvec[i] = RVec2(x: pts[i].x.float32, y: pts[i].y.float32)
        rvec[safeCount] = rvec[0]
        rDrawLineStrip(addr rvec[0], safeCount + 1, toRColor(pg.color))

    of NK_COMMAND_POLYGON_FILLED:
      let pf = cast[ptr nk_command_polygon_filled](cmd)
      let count = pf.point_count.int32
      if count >= 3:
        let pts = cast[ptr UncheckedArray[nk_vec2i]](addr pf.points[0])
        let safeCount = min(count, PolyLineMax)
        if count > PolyLineMax and not polyTruncWarnEmitted:
          polyTruncWarnEmitted = true
          raddyLog("raddyRender: NK_COMMAND_POLYGON_FILLED point_count " & $count &
                   " exceeds PolyLineMax (" & $PolyLineMax & ") — truncated (silenced)")
        let col = toRColor(pf.color)
        ## Fan triangulation from vertex 0. Valid only for convex polygons —
        ## concave polygons will fill the convex hull with overlapping triangles
        ## rather than the true concave shape. Nuklear's widget-layer polygons
        ## are always convex, so this is correct for raddy's use case.
        for i in 1 ..< safeCount - 1:
          var ta = RVec2(x: pts[0].x.float32,   y: pts[0].y.float32)
          var tb = RVec2(x: pts[i].x.float32,   y: pts[i].y.float32)
          var tc = RVec2(x: pts[i+1].x.float32, y: pts[i+1].y.float32)
          fixTriWinding(ta, tb, tc)
          rDrawTriangle(ta, tb, tc, col)

    of NK_COMMAND_POLYLINE:
      let pl = cast[ptr nk_command_polyline](cmd)
      let count = pl.point_count.int32
      if count >= 2:
        let pts = cast[ptr UncheckedArray[nk_vec2i]](addr pl.points[0])
        let safeCount = min(count, PolyLineMax)
        if count > PolyLineMax and not polyTruncWarnEmitted:
          polyTruncWarnEmitted = true
          raddyLog("raddyRender: NK_COMMAND_POLYLINE point_count " & $count &
                   " exceeds PolyLineMax (" & $PolyLineMax & ") — truncated (silenced)")
        var rvec: array[PolyLineMax, RVec2]
        for i in 0 ..< safeCount:
          rvec[i] = RVec2(x: pts[i].x.float32, y: pts[i].y.float32)
        rDrawLineStrip(addr rvec[0], safeCount, toRColor(pl.color))

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
        ## Cap: RaddyMaxTextBytes-1 usable chars; see font.nim for the shared constant.
        ## UTF-8 note: truncation at an arbitrary byte can split a multi-byte codepoint;
        ## this is acceptable for the first-pass renderer — fix in the i18n follow-up.
        var buf: array[RaddyMaxTextBytes, char]
        let copyLen = min(int(tc.length), RaddyMaxTextBytes - 1)
        if copyLen < int(tc.length) and not textTruncWarnEmitted:
          textTruncWarnEmitted = true
          raddyLog("raddyRender: NK_COMMAND_TEXT payload truncated to " &
                   $RaddyMaxTextBytes & " bytes (silenced hereafter)")
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

    of NK_COMMAND_IMAGE:
      let ic = cast[ptr nk_command_image](cmd)
      ## nk_image.handle.ptr holds a ptr RTexture owned by the host.
      ## Integer handle (handle.id) is not supported — callers must store ptr.
      let texPtr = cast[ptr RTexture](ic.img.handle.`ptr`)
      if texPtr != nil:
        ## nk_image.region[0..3]: [x, y, w, h] sub-rectangle in the texture.
        ## region[2]==0 or region[3]==0 means use the full texture dimension.
        let srcW = if ic.img.region[2] > 0: float32(ic.img.region[2]) else: float32(texPtr.width)
        let srcH = if ic.img.region[3] > 0: float32(ic.img.region[3]) else: float32(texPtr.height)
        rDrawTextureRec(
          texPtr[],
          RRect(x: float32(ic.img.region[0]), y: float32(ic.img.region[1]),
                width: srcW, height: srcH),
          RVec2(x: ic.x.float32, y: ic.y.float32),
          toRColor(ic.col)
        )

    of NK_COMMAND_CUSTOM:
      ## Custom commands carry a C callback that raddy never invokes.
      ## The host handles custom drawing directly if needed.
      discard

    cmd = nkNext(ctx, cmd)

  ## Close any open scissor region before returning.
  if scissorActive:
    rEndScissorMode()

  ## Overflow check: on vita/raddyFixed, `needed > size` means commands were dropped.
  ## Must happen BEFORE nk_clear (which resets the buffer pointers).
  ## Predicate is `needed > size` (NOT `needed > allocated`): on NK_BUFFER_FIXED,
  ## nk_buffer_alloc increments `needed` before the capacity check, so `needed`
  ## accumulates total requested bytes while `allocated` stalls below `size` when
  ## the buffer is full. See types.nim nk_buffer comment for the full explanation.
  when defined(vita) or defined(raddyFixed):
    bufOverflow = ctx.memory.needed > ctx.memory.size
    if bufOverflow:
      raddyLog("raddyRender: Nuklear command buffer full — some commands were dropped")
  else:
    bufOverflow = false

  nkClear(ctx)
