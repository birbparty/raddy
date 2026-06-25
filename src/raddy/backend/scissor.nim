## scissor.nim — Nuklear→raylib scissor coordinate transform.
##
## Nuklear uses top-left Y-down coords. raylib's BeginScissorMode in a RenderTexture
## uses bottom-up OpenGL convention. The transform: y' = H - y - h.
##
## Pure proc — no side effects, no raylib calls, no global state. Called by render.nim.

proc scissorYFlip*(x, y, w, h: int32; framebufferH: int32): (int32, int32, int32, int32) {.inline.} =
  ## Returns (x, y', w, h) suitable for BeginScissorMode inside a RenderTexture of height H.
  ## framebufferH is the RenderTexture.texture.height (NOT GetScreenHeight()).
  ## Nuklear semantics: each NK_COMMAND_SCISSOR REPLACES the current clip — do NOT nest.
  (x, framebufferH - y - h, w, h)

static:
  ## Identity: no flip at y=0, h=100, H=100 → y'=0
  let (rx, ry, rw, rh) = scissorYFlip(10, 0, 80, 100, 100)
  doAssert ry == 0, "y=0, h=H → y'=0"
  doAssert rx == 10 and rw == 80 and rh == 100

  ## Typical: H=480, y=10, h=50 → y'=480-10-50=420
  let (_, ry2, _, _) = scissorYFlip(0, 10, 100, 50, 480)
  doAssert ry2 == 420, "y'=H-y-h"

  ## Full-height: y=0, h=H → y'=0 (mirror)
  let (_, ry3, _, _) = scissorYFlip(0, 0, 100, 480, 480)
  doAssert ry3 == 0

  ## Bottom rect: y=H-h, h → y'=0
  let (_, ry4, _, _) = scissorYFlip(0, 430, 100, 50, 480)
  doAssert ry4 == 0, "bottom rect → y'=0"

  ## nk_null_rect case: Nuklear uses {x:-8192,y:-8192,w:16384,h:16384} for popup
  ## overlays ("disable clipping so the popup can draw outside parent bounds").
  ## Nuklear's nk_push_scissor applies NK_MAX(0, w) / NK_MAX(0, h), so w and h are
  ## always non-negative. x and y may be large and negative; OpenGL's glScissor
  ## (called via BeginScissorMode → rlScissor → glScissor) intersects the scissor
  ## rect with the viewport at the driver level — the popup is visible everywhere.
  ## Formula: y' = H - y - h = 600 - (-8192) - 16384 = 600 + 8192 - 16384 = -7592
  let (nx, ny5, nw, nh) = scissorYFlip(-8192, -8192, 16384, 16384, 600)
  doAssert nx  == -8192,          "null-rect: x passes through unchanged"
  doAssert ny5 == -7592,          "null-rect: y' = 600 + 8192 - 16384 = -7592"
  doAssert nw  == 16384,          "null-rect: w passes through unchanged"
  doAssert nh  == 16384,          "null-rect: h passes through unchanged"
