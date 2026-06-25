## examples/demo.nim — raddy desktop demo
##
## Exercises the full public API surface:
##   window · labels · buttons · slider · checkbox · edit field · scrolled group
##
## Build (desktop, naylib installed via nimble):
##   NAYLIB=$(nimble path naylib)
##   nim c --mm:orc --path:src --path:"$NAYLIB" --passC:"-I${NAYLIB}/raylib" \
##       examples/demo.nim
##   ./examples/demo
##
## Vita (same UI code; only the frame-loop imports differ):
##   On Vita replace:
##     import raylib          →  import raylib_console (or the platform's raylib wrapper)
##     import raddy/backend/pump_naylib  →  import raddy/backend/pump_vita
##     raddyNaylibPump(ctx)   →  call raddyInputBegin/End + pump_vita.nim events
##   The raddy core (import raddy) and every widget call is IDENTICAL on both
##   platforms — only the window management + input pump differs.
##
## Note: naylib/raylib Font* = raddy/backend/raylib_api RFont* — same C struct;
## cast[ptr RFont](addr gFont) is the correct bridge between them.
## naylib Font has a =destroy that calls UnloadFont; gFont here stores the
## engine-owned default font and is only safe because =destroy fires after
## closeWindow(). For owned fonts (loadFont), the =destroy behaviour is correct.

import raylib                           ## naylib's raylib binding (package name: naylib)
import raddy
import raddy/backend/ctx_bundle         ## RaddyCtxBundle, raddyBundleCreate/Free/Ctx
import raddy/backend/render             ## raddyRender
import raddy/backend/pump_naylib        ## raddyNaylibPump
import raddy/backend/raylib_api         ## RFont (for the cast bridge to naylib Font)

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

const
  ScreenW    = 800
  ScreenH    = 600
  TargetFPS  = 60
  EditMaxLen = 127   ## max editable chars in the edit field

# ---------------------------------------------------------------------------
# Module-level state — gFont must outlive the RaddyCtxBundle because
# raddyBundleCreate stores addr gFont as a raw C pointer inside nk_handle.
# Module-scope variables are stable for the program's lifetime.
# ---------------------------------------------------------------------------

var gFont: Font

# ---------------------------------------------------------------------------
# Mutable UI state — persists across frames
# ---------------------------------------------------------------------------

var
  clickCount = 0
  checkA     = false
  checkB     = true
  sliderVal  = 50.0f
  editBuf    = "Hello, raddy!"

# ---------------------------------------------------------------------------
# Frame: build the Nuklear UI
# ---------------------------------------------------------------------------

proc buildUI(ctx: ptr nk_context) =
  let flags = NK_WINDOW_BORDER.nk_flags or
              NK_WINDOW_MOVABLE.nk_flags or
              NK_WINDOW_SCALABLE.nk_flags or
              NK_WINDOW_TITLE.nk_flags
  let bounds = nk_rect(x: 20, y: 20, w: 400, h: 540)

  if not raddyBegin(ctx, "raddy demo", bounds, flags):
    raddyEnd(ctx)   # always pair Begin with End, even on false
    return

  # ---- Labels ---------------------------------------------------------------
  raddyLayoutRowDynamic(ctx, height = 20, cols = 1)
  raddyLabel(ctx, "Labels")
  raddyLayoutRowDynamic(ctx, height = 20, cols = 2)
  raddyLabel(ctx, "left-aligned",   NK_TEXT_LEFT)
  raddyLabel(ctx, "right-aligned",  NK_TEXT_RIGHT)
  raddyLayoutRowDynamic(ctx, height = 20, cols = 1)
  raddyLabel(ctx, "centered", NK_TEXT_CENTERED)

  # ---- Buttons --------------------------------------------------------------
  raddyLayoutRowDynamic(ctx, height = 8, cols = 1)
  raddySpacing(ctx, 1)

  raddyLayoutRowDynamic(ctx, height = 20, cols = 1)
  raddyLabel(ctx, "Buttons")
  raddyLayoutRowDynamic(ctx, height = 30, cols = 2)
  if raddyButton(ctx, "Click me"):
    inc clickCount
  raddyLabel(ctx, "Clicks: " & $clickCount, NK_TEXT_LEFT)

  # ---- Checkboxes -----------------------------------------------------------
  raddyLayoutRowDynamic(ctx, height = 8, cols = 1)
  raddySpacing(ctx, 1)
  raddyLayoutRowDynamic(ctx, height = 20, cols = 1)
  raddyLabel(ctx, "Checkboxes")
  raddyLayoutRowDynamic(ctx, height = 25, cols = 1)
  discard raddyCheckbox(ctx, "Option A", checkA)
  discard raddyCheckbox(ctx, "Option B", checkB)

  # ---- Slider ---------------------------------------------------------------
  raddyLayoutRowDynamic(ctx, height = 8, cols = 1)
  raddySpacing(ctx, 1)
  raddyLayoutRowDynamic(ctx, height = 25, cols = 1)
  discard raddySlider(ctx, 0.0f, sliderVal, 100.0f, step = 1.0f)
  raddyLayoutRowDynamic(ctx, height = 20, cols = 1)
  raddyLabel(ctx, "Slider value: " & $int(sliderVal))

  # ---- Edit field -----------------------------------------------------------
  raddyLayoutRowDynamic(ctx, height = 8, cols = 1)
  raddySpacing(ctx, 1)
  raddyLayoutRowDynamic(ctx, height = 20, cols = 1)
  raddyLabel(ctx, "Edit field")
  raddyLayoutRowDynamic(ctx, height = 30, cols = 1)
  discard raddyEdit(ctx, NK_EDIT_FIELD_FLAGS, editBuf, maxLen = EditMaxLen)

  # ---- Scrolled group -------------------------------------------------------
  raddyLayoutRowDynamic(ctx, height = 8, cols = 1)
  raddySpacing(ctx, 1)
  raddyLayoutRowDynamic(ctx, height = 20, cols = 1)
  raddyLabel(ctx, "Scrolled group")
  raddyLayoutRowDynamic(ctx, height = 120, cols = 1)

  if raddyGroupBegin(ctx, "items", NK_WINDOW_BORDER.nk_flags):
    raddyLayoutRowDynamic(ctx, height = 20, cols = 1)
    for i in 1..12:
      raddyLabel(ctx, "Group item " & $i)
    raddyGroupEnd(ctx)   # only call End when Begin returned true

  raddyEnd(ctx)

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

proc main() =
  initWindow(ScreenW, ScreenH, "raddy demo")
  setTargetFPS(TargetFPS)

  # Font MUST be loaded after initWindow (GPU context required).
  # getFontDefault() returns raylib's built-in engine font (baseSize = 10 px).
  # For larger text or Vita 960x544, replace with:
  #   gFont = loadFont("assets/my.ttf", fontSize = 18, glyphCount = 95)
  gFont = getFontDefault()
  let fontPx = float32(gFont.baseSize)   # 10.0 for the default font

  let bundle = raddyBundleCreate(cast[ptr RFont](addr gFont), fontPx)
  let ctx = raddyBundleCtx(bundle)

  # Render into a RenderTexture so raddyRender's scissor Y-flip is correct.
  # (raylib FBOs use bottom-up OpenGL coordinates; screen drawing is top-down.)
  let rt = loadRenderTexture(ScreenW, ScreenH)

  while not windowShouldClose():
    # ---- Input + UI into the offscreen texture ----------------------------
    beginTextureMode(rt)
    clearBackground(Color(r: 30, g: 30, b: 30, a: 255))

    raddyNaylibPump(ctx)   # gather input → Nuklear (wraps inputBegin/End)
    buildUI(ctx)            # declare Nuklear panel + widgets

    # overflow is always false on desktop (heap allocator); non-zero only on
    # vita/-d:raddyFixed when the fixed command buffer fills up.
    var overflow = false
    raddyRender(ctx, rt.texture.height, overflow)
    endTextureMode()

    # ---- Blit offscreen texture to screen (flip UV on Y for FBO origin) ----
    beginDrawing()
    drawTexture(
      rt.texture,
      source   = Rectangle(x: 0, y: 0,
                           width:  float32(rt.texture.width),
                           height: float32(-rt.texture.height)),  # negative = Y-flip
      dest     = Rectangle(x: 0, y: 0,
                           width:  float32(ScreenW),
                           height: float32(ScreenH)),
      origin   = Vector2(x: 0, y: 0),
      rotation = 0.0f,
      tint     = White)
    endDrawing()

  raddyBundleFree(bundle)
  closeWindow()
  # rt goes out of scope here; naylib's RenderTexture =destroy calls
  # UnloadRenderTexture automatically. Same for gFont / =destroy / UnloadFont.

main()
