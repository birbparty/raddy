## test_bundle_render.nim — regression guard for raddy-ac3.
##
## A RaddyCtxBundle created on the fixed-buffer path (-d:raddyFixed / vita) must
## actually RENDER: raddyRender(bundle.ctx) has to dispatch the window's draw
## commands. Before the alignment fix, the bundle's inline cmdBuf could be pushed
## off the alignment nk_init_fixed requires (by the preceding bool fields), which
## made raddyRender emit ZERO draw calls — or crash with an illegal access — while
## a direct raddyCtxInit context rendered fine. Pure lifecycle tests
## (test_ctx_bundle.nim) never rendered, so this slipped through.
##
## This test builds one frame on a bundle context and counts the raylib draw
## calls raddyRender makes. A bordered window + label produces several; we assert
## > 0 (it was exactly 0 on the misaligned fixed path). Runs on BOTH the heap and
## fixed paths — the heap path always rendered; the fixed path is the regression.
##
## HEADLESS: all raylib draw procs are counting stubs; no GL / window needed.

import bddy
import raddy                       ## frame API + types
import raddy/backend/ctx_bundle    ## RaddyCtxBundle, raddyBundleCreate/Ctx/Free
import raddy/backend/raylib_api    ## RFont
import raddy/backend/render        ## raddyRender

# Counting draw stubs — every raylib draw proc raddyRender may call bumps g_draws.
# rlDrawTextEx additionally bumps g_text. dbg_draws()/dbg_reset() expose the count.
{.emit: """
#include "raylib.h"
static int g_draws = 0;
static int g_text  = 0;
void DrawRectangleRec(rlRectangle r, Color c){ (void)r;(void)c; g_draws++; }
void DrawRectangleLinesEx(rlRectangle r, float t, Color c){ (void)r;(void)t;(void)c; g_draws++; }
void DrawRectangleRounded(rlRectangle r, float ro, int s, Color c){ (void)r;(void)ro;(void)s;(void)c; g_draws++; }
void DrawRectangleRoundedLinesEx(rlRectangle r, float ro, int s, float t, Color c){ (void)r;(void)ro;(void)s;(void)t;(void)c; g_draws++; }
void DrawRectangleGradientEx(rlRectangle r, Color a, Color b, Color cc, Color d){ (void)r;(void)a;(void)b;(void)cc;(void)d; g_draws++; }
void DrawLineEx(Vector2 a, Vector2 b, float t, Color c){ (void)a;(void)b;(void)t;(void)c; g_draws++; }
void DrawLineStrip(const Vector2 *p, int n, Color c){ (void)p;(void)n;(void)c; g_draws++; }
void DrawTriangle(Vector2 a, Vector2 b, Vector2 d, Color c){ (void)a;(void)b;(void)d;(void)c; g_draws++; }
void DrawTriangleLines(Vector2 a, Vector2 b, Vector2 d, Color c){ (void)a;(void)b;(void)d;(void)c; g_draws++; }
void DrawRing(Vector2 ce, float i, float o, float s, float e, int sg, Color c){ (void)ce;(void)i;(void)o;(void)s;(void)e;(void)sg;(void)c; g_draws++; }
void DrawCircleSector(Vector2 ce, float r, float s, float e, int sg, Color c){ (void)ce;(void)r;(void)s;(void)e;(void)sg;(void)c; g_draws++; }
void DrawEllipse(int x, int y, float a, float b, Color c){ (void)x;(void)y;(void)a;(void)b;(void)c; g_draws++; }
void DrawEllipseLines(int x, int y, float a, float b, Color c){ (void)x;(void)y;(void)a;(void)b;(void)c; g_draws++; }
void rlDrawTextEx(Font f, const char *t, Vector2 p, float s, float sp, Color c){ (void)f;(void)t;(void)p;(void)s;(void)sp;(void)c; g_draws++; g_text++; }
void DrawTextureRec(Texture2D t, rlRectangle s, Vector2 p, Color c){ (void)t;(void)s;(void)p;(void)c; g_draws++; }
void BeginScissorMode(int x, int y, int w, int h){ (void)x;(void)y;(void)w;(void)h; }
void EndScissorMode(void){}
Vector2 MeasureTextEx(Font f, const char *t, float s, float sp){ (void)f;(void)t;(void)s;(void)sp; Vector2 v={0.0f,0.0f}; return v; }
int  dbg_draws(void){ return g_draws; }
int  dbg_text(void){ return g_text; }
void dbg_reset(void){ g_draws = 0; g_text = 0; }
""".}

proc dbgDraws(): cint {.importc: "dbg_draws".}
proc dbgText():  cint {.importc: "dbg_text".}
proc dbgReset()       {.importc: "dbg_reset".}

spec "raddyBundleCreate context renders (raddy-ac3 alignment regression)":

  it "raddyRender dispatches draw calls for a bundle frame (window + label)":
    dbgReset()

    # A non-nil, "loaded" font so the label's text command also draws (texture.id
    # != 0 satisfies render.nim's text path; the width callback is stubbed).
    var baseFont: RFont
    baseFont.texture.id = 1'u32
    var bundle = raddyBundleCreate(addr baseFont, 16.0f)
    doAssert bundle.ctxOk, "bundle ctx init failed"
    doAssert bundle.fontLoaded, "test font should report loaded (texture.id != 0)"

    let ctx = raddyBundleCtx(bundle)
    raddyInputBegin(ctx)
    raddyInputEnd(ctx)
    doAssert raddyBegin(ctx, "render", nk_rect(x: 0, y: 0, w: 300, h: 200),
                        NK_WINDOW_BORDER.nk_flags), "raddyBegin must open the window"
    raddyLayoutRowDynamic(ctx, height = 40, cols = 1)
    raddyLabel(ctx, "render me")
    raddyEnd(ctx)

    var overflow = false
    raddyRender(ctx, 200'i32, overflow)   ## owns the per-frame nk_clear
    let draws = dbgDraws()
    let text  = dbgText()
    raddyBundleFree(bundle)

    verify:
      draws > 0       ## was exactly 0 on the misaligned fixed path (raddy-ac3)
      text > 0        ## the switched-on, loaded font drew its label
      not overflow    ## fixed buffer did not overflow
