## test_render.nim — bddy spec for src/raddy/backend/render.nim
##
## Compile+link acceptance: all raylib draw procs are stubbed out (no display needed).
## Runtime tests push no NK commands, so no draw proc is actually called.
## The dispatch loop exits immediately (nk__begin returns nil on an empty context);
## only nk_clear is called, which is safe without a raylib window.
##
## Actual draw-path correctness requires a display: those are integration tests.

import bddy
import raddy/backend/render   ## raddyRender
import raddy/types             ## nk_context, nk_user_font, nk_size
import raddy/context           ## raddyCtxInit, raddyCtxFree
import raddy/errors            ## RaddyCmdBufBytes (minimum fixed buffer size)

## ---------------------------------------------------------------------------
## Raylib draw-proc stubs — needed for the linker; never called in these tests.
## All stubs follow the same pattern as the MeasureTextEx stub in test_ctx_bundle.nim:
## include raylib.h for type names, then provide no-op bodies.
## rlRectangle: naylib renames Rectangle→rlRectangle to avoid Win32 collisions.
## rlDrawTextEx: naylib renames DrawTextEx→rlDrawTextEx for the same reason.
## ---------------------------------------------------------------------------
{.emit: """
#include "raylib.h"

void DrawRectangleRec(rlRectangle rec, Color color)
    { (void)rec; (void)color; }

void DrawRectangleLinesEx(rlRectangle rec, float lineThick, Color color)
    { (void)rec; (void)lineThick; (void)color; }

void DrawRectangleRounded(rlRectangle rec, float roundness, int segments, Color color)
    { (void)rec; (void)roundness; (void)segments; (void)color; }

void DrawRectangleRoundedLinesEx(rlRectangle rec, float roundness, int segments,
                                  float lineThick, Color color)
    { (void)rec; (void)roundness; (void)segments; (void)lineThick; (void)color; }

void DrawRectangleGradientEx(rlRectangle rec, Color col1, Color col2,
                              Color col3, Color col4)
    { (void)rec; (void)col1; (void)col2; (void)col3; (void)col4; }

void DrawLineEx(Vector2 startPos, Vector2 endPos, float thick, Color color)
    { (void)startPos; (void)endPos; (void)thick; (void)color; }

void DrawLineStrip(const Vector2 *points, int pointCount, Color color)
    { (void)points; (void)pointCount; (void)color; }

void DrawTriangle(Vector2 v1, Vector2 v2, Vector2 v3, Color color)
    { (void)v1; (void)v2; (void)v3; (void)color; }

void DrawTriangleLines(Vector2 v1, Vector2 v2, Vector2 v3, Color color)
    { (void)v1; (void)v2; (void)v3; (void)color; }

void DrawRing(Vector2 center, float innerRadius, float outerRadius,
              float startAngle, float endAngle, int segments, Color color)
    { (void)center; (void)innerRadius; (void)outerRadius;
      (void)startAngle; (void)endAngle; (void)segments; (void)color; }

void DrawCircleSector(Vector2 center, float radius, float startAngle,
                      float endAngle, int segments, Color color)
    { (void)center; (void)radius; (void)startAngle;
      (void)endAngle; (void)segments; (void)color; }

void DrawEllipse(int centerX, int centerY, float radiusH, float radiusV, Color color)
    { (void)centerX; (void)centerY; (void)radiusH; (void)radiusV; (void)color; }

void DrawEllipseLines(int centerX, int centerY, float radiusH, float radiusV, Color color)
    { (void)centerX; (void)centerY; (void)radiusH; (void)radiusV; (void)color; }

void rlDrawTextEx(Font font, const char *text, Vector2 position,
                  float fontSize, float spacing, Color tint)
    { (void)font; (void)text; (void)position;
      (void)fontSize; (void)spacing; (void)tint; }

void DrawTextureRec(Texture2D texture, rlRectangle source, Vector2 position, Color tint)
    { (void)texture; (void)source; (void)position; (void)tint; }

void BeginScissorMode(int x, int y, int width, int height)
    { (void)x; (void)y; (void)width; (void)height; }

void EndScissorMode(void) {}

Vector2 MeasureTextEx(Font font, const char *text, float fontSize, float spacing)
    { (void)font; (void)text; (void)fontSize; (void)spacing;
      Vector2 v = {0.0f, 0.0f}; return v; }
""".}

## Desktop-path tests use nk_init_default (heap). On raddyFixed/vita the heap
## allocator is not compiled in and raddyCtxInit requires a caller-owned buffer.
when not (defined(raddyFixed) or defined(vita)):
  spec "raddyRender":

    it "empty command queue returns without crash and no overflow (desktop path)":
      ## No NK commands pushed → nk__begin returns nil → dispatch loop exits immediately.
      ## Only nk_clear is called; raddyRender owns the clear (do not also call raddyCtxFree
      ## before this — raddyRender is the per-frame terminus, not raddyBundleClear).
      var nkFont: nk_user_font
      var ctx: nk_context
      let ok = raddyCtxInit(addr ctx, addr nkFont)
      doAssert ok, "raddyCtxInit must succeed before raddyRender can be called"
      var overflow = true  ## set true so we verify raddyRender writes it
      raddyRender(addr ctx, 480'i32, overflow)
      ## raddyRender called nk_clear; context is now cleared but still owns heap.
      raddyCtxFree(addr ctx)
      verify:
        overflow == false

    it "second call after context re-init also returns no overflow":
      ## Verify raddyRender is safe to call frame-over-frame: each call ends with
      ## nk_clear, leaving the context in a valid state for re-entry.
      var nkFont: nk_user_font
      var ctx: nk_context
      let ok = raddyCtxInit(addr ctx, addr nkFont)
      doAssert ok
      var overflow = true
      raddyRender(addr ctx, 600'i32, overflow)   ## frame 1
      ## After raddyRender, nk_clear has run but ctx is still valid.
      ## A real frame would call nk_input_begin/end + build UI here; we just render again.
      raddyRender(addr ctx, 600'i32, overflow)   ## frame 2 (empty queue again)
      raddyCtxFree(addr ctx)
      verify:
        overflow == false

when defined(raddyFixed):
  ## raddyFixed tests use nk_init_fixed with a stack buffer >= RaddyCmdBufBytes (64 KiB).
  ## The buffer is declared as a local in each test rather than a global to keep
  ## each test self-contained; stack-allocating 64 KiB is fine in a test binary.
  spec "raddyRender (raddyFixed path — fixed command buffer)":

    it "empty queue returns no overflow on fixed-buffer context":
      ## Fixed-buffer path: nk_init_fixed uses the cmdBuf embedded in the bundle.
      ## We test via the primitive context path (not ctx_bundle) to keep this unit-isolated.
      ## On a fresh empty context the needed/size check must produce bufOverflow=false.
      var nkFont: nk_user_font
      var ctx: nk_context
      var cmdBuf: array[RaddyCmdBufBytes, byte]
      let ok = raddyCtxInit(addr ctx, addr nkFont, addr cmdBuf[0], nk_size(RaddyCmdBufBytes))
      doAssert ok, "raddyCtxInit (fixed path) must succeed"
      var overflow = true
      raddyRender(addr ctx, 480'i32, overflow)
      raddyCtxFree(addr ctx)
      verify:
        overflow == false

    it "detects buffer overflow when ctx.memory.needed exceeds ctx.memory.size":
      ## Overflow detection path: on NK_BUFFER_FIXED, nk_buffer_alloc increments
      ## `needed` before the capacity check, so `needed` accumulates total requested
      ## bytes while `allocated` stalls at or below `size`.  The correct predicate is
      ## `needed > size` (NOT `needed > allocated`) — verified by forcing the condition
      ## directly so this test does not require the layout API to push real commands.
      ##
      ## This is the only test path that validates the overflow branch (the desktop
      ## path always takes `bufOverflow = false`).
      var nkFont: nk_user_font
      var ctx: nk_context
      var cmdBuf: array[RaddyCmdBufBytes, byte]
      let ok = raddyCtxInit(addr ctx, addr nkFont, addr cmdBuf[0], nk_size(RaddyCmdBufBytes))
      doAssert ok
      ## Simulate what Nuklear does internally when an allocation cannot fit: it
      ## increments needed past size but does not advance allocated.  We reproduce
      ## that final state by directly setting the field before raddyRender reads it.
      ctx.memory.needed = ctx.memory.size + 1
      var overflow = false
      raddyRender(addr ctx, 480'i32, overflow)
      raddyCtxFree(addr ctx)
      verify:
        overflow == true
