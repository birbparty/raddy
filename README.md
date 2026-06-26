# raddy

**raddy — Nuklear immediate-mode GUI for naylib/raylib (desktop + PS Vita)**

## Overview

raddy is a Nim wrapper around the [Nuklear](https://github.com/Immediate-Mode-UI/Nuklear) immediate-mode GUI library. It targets both desktop (via naylib/raylib with OpenGL) and PS Vita (via raylib_console), sharing a single core that emits no platform-specific imports.

Nuklear builds a draw-command queue each frame — a list of `NK_COMMAND_*` records describing lines, rectangles, text, and so on. raddy translates that queue into raylib draw calls at render time. This is command-queue rendering, not vertex-buffer rendering. The distinction matters: the same Nuklear core runs on every platform; only the final dispatch step (raylib on desktop, raylib_console on Vita) differs.

The `import raddy` surface is backend-free. Rendering and input plumbing live in separate backend modules that consumers import explicitly. This keeps the core linkable on Vita without pulling in any desktop rendering machinery.

## Install

```sh
nimble install "https://github.com/birbparty/raddy"
```

Desktop usage also requires [naylib](https://github.com/planetis-m/naylib):

```sh
nimble install naylib
```

## Quickstart

Minimal desktop example:

```nim
import raylib
import raddy
import raddy/backend/ctx_bundle
import raddy/backend/render
import raddy/backend/pump_naylib
import raddy/backend/raylib_api

var gFont: Font
var clickCount = 0

proc buildUI(ctx: ptr nk_context) =
  let bounds = nk_rect(x: 20, y: 20, w: 300, h: 200)
  let flags = NK_WINDOW_BORDER.nk_flags or NK_WINDOW_TITLE.nk_flags
  if not raddyBegin(ctx, "demo", bounds, flags):
    raddyEnd(ctx); return
  raddyLayoutRowDynamic(ctx, height=30, cols=2)
  if raddyButton(ctx, "Click"):
    inc clickCount
  raddyLabel(ctx, "Count: " & $clickCount, NK_TEXT_LEFT)
  raddyEnd(ctx)

proc main() =
  initWindow(800, 600, "raddy demo")
  setTargetFPS(60)
  gFont = getFontDefault()
  let bundle = raddyBundleCreate(cast[ptr RFont](addr gFont), float32(gFont.baseSize))
  let ctx = raddyBundleCtx(bundle)
  let rt = loadRenderTexture(800, 600)
  while not windowShouldClose():
    beginTextureMode(rt)
    clearBackground(Color(r:30,g:30,b:30,a:255))
    raddyNaylibPump(ctx)
    buildUI(ctx)
    var overflow = false
    raddyRender(ctx, rt.texture.height, overflow)
    endTextureMode()
    beginDrawing()
    drawTexture(rt.texture,
      source=Rectangle(x:0,y:0,width:float32(rt.texture.width),height:float32(-rt.texture.height)),
      dest=Rectangle(x:0,y:0,width:800,height:600),
      origin=Vector2(x:0,y:0),rotation=0,tint=White)
    endDrawing()
  raddyBundleFree(bundle)
  closeWindow()
main()
```

## Multi-size fonts and font switching

raddy renders at multiple font sizes in one UI by switching the active Nuklear
font between widget groups. Bake **one `Font` per pixel size** (do not scale a
single atlas — it blurs), wrap each in a caller-owned `RaddyFont`, and switch
with `setRaddyFont` (handle form) or `raddyBundleSetFont` (bundle form — see
below):

```nim
import raddy
import raddy/backend/font        # RaddyFont, raddyMakeFont, raddyFontHandle
import raddy/backend/raylib_api  # RFont

# Module scope — each Font and its RaddyFont must outlive every frame it is
# active, at a STABLE address (both pointers escape into Nuklear).
var small, large: Font
var smallRf, largeRf: RaddyFont

proc loadFonts() =               # call after initWindow (baking needs a GL context)
  small = loadFont("my.ttf", 16, 0)
  large = loadFont("my.ttf", 32, 0)
  # RFont is raddy's separate Nim view of raylib's Font (same C struct, distinct
  # Nim identity) — bridge the ptr with cast[ptr RFont]. Pass the bake ppem
  # (baseSize) as the pixel height: it MUST equal the size the font was baked at,
  # or measure and draw diverge and text clips/overflows.
  smallRf = raddyMakeFont(cast[ptr RFont](addr small), float32(small.baseSize))
  largeRf = raddyMakeFont(cast[ptr RFont](addr large), float32(large.baseSize))

# Per frame, inside raddyBegin/raddyEnd. `ctx` is raddyBundleCtx(bundle) from the
# Quickstart above.
setRaddyFont(ctx, raddyFontHandle(smallRf))   # smallRf active; everything next is 16 px
raddyLabel(ctx, "small")
setRaddyFont(ctx, raddyFontHandle(largeRf))   # mid-frame switch is supported → 32 px
raddyLabel(ctx, "BIG")
```

If you hold the bundle (not a raw `ctx`), the bundle form switches the same way
but takes the `RaddyFont` **value** rather than a handle:

```nim
raddyBundleSetFont(bundle, largeRf)   # equivalent to setRaddyFont(raddyBundleCtx(bundle), raddyFontHandle(largeRf))
```

The switch is **forward-only** (affects only widgets emitted after it) and
**persists across frames** (the per-frame clear, `nk_clear`, does not reset it —
re-set each frame if you want a deterministic starting font). A single-size app
just bakes one font; the machinery is additive. See
[docs/prompts/font-contract.md](docs/prompts/font-contract.md) for the full
lifetime contract (the fonts and `RaddyFont`s must stay at a stable address —
no frame-loop locals, no reallocating `seq` storage — until after `raddyRender`).

## Building

Do **not** use `nimble build` — the `srcDir` flatten causes import path issues. Compile directly:

```sh
nim c \
  --mm:orc \
  --path:src \
  --path:"$(nimble path naylib)" \
  --passC:"-I$(nimble path naylib)/raylib" \
  examples/demo.nim
```

## Testing

```sh
nimble test         # unit/spec suite — stubs raylib, no GL context required
nimble acceptance   # real-raylib acceptance spec — needs a GL/window context
```

`nimble test` links a **stubbed** raylib (no window, no GPU) and runs every
`tests/test_*.nim`. The `acceptance` task is **separate**: it links **real**
raylib (naylib) and opens a hidden window to exercise the font pipeline against
the real `LoadFont`/`MeasureTextEx` — it runs `tests/acceptance_smoke.nim`
(deliberately named without `test_` so the stubbed suite never picks it up). On
a headless CI host, wrap it with a virtual framebuffer:
`xvfb-run -a nimble acceptance`.

### Bundled test font

`tests/assets/unscii-16.ttf` is the bundled acceptance-test font —
[Unscii](http://viznut.fi/unscii/) 16, public domain / CC-0. It is a **test
asset only**: raddy's library bundles no font, and consumers supply their own.
Provenance and the CC-0 terms (and the GPL carve-out that this non-`full`
variant avoids) are recorded in `tests/assets/LICENSE.txt`.

## Architecture: Command-queue rendering (not vertex)

Nuklear exposes two rendering backends: vertex-buffer (fills a GPU-ready buffer) and command-queue (emits a linked list of draw commands). raddy uses the **command-queue** path.

Why:

- **Backend-agnostic dispatch.** Nuklear produces `NK_COMMAND_RECT`, `NK_COMMAND_TEXT`, etc. — abstract draw intents. `raddyRender` iterates them with `nk__begin`/`nk__next` and maps each to a raylib call. The mapping is the same whether raylib is naylib on desktop or raylib_console on Vita.
- **No geometry shaders required.** Vertex-buffer rendering assumes a shader pipeline for atlas-based glyph rendering. raylib_console on Vita does not expose that pipeline. Command-queue sidesteps it entirely.
- **Fits in 64 KiB fixed memory.** The Vita build uses `nk_init_fixed` with a 64 KiB stack buffer (`-d:vita` or `-d:raddyFixed`). A vertex buffer would overflow that budget. The command queue is compact by design.

Desktop uses `nk_init_default` (heap allocation) unless `-d:raddyFixed` is set.

## Widget coverage

| Widget | Proc |
|---|---|
| Window | `raddyBegin` / `raddyEnd` |
| Label | `raddyLabel` |
| Button | `raddyButton` |
| Checkbox | `raddyCheckbox` |
| Slider | `raddySlider` |
| Text edit | `raddyEdit` |
| Combo box | `raddyCombo` |
| Group | `raddyGroupBegin` / `raddyGroupEnd` |
| Property | `raddyProperty` |
| Spacing | `raddySpacing` |

Layout rows: `raddyLayoutRowDynamic`, `raddyLayoutRowStatic`, `raddyLayoutRowBegin`/`Push`/`End`.

See [docs/api/widgets.md](docs/api/widgets.md) for full signatures and usage.

## Platform notes

| Platform | Renderer | Input pump |
|---|---|---|
| Desktop | naylib (OpenGL via GLFW) | `raddy/backend/pump_naylib` |
| PS Vita | raylib_console | `raddy/backend/pump_vita` |

`import raddy` has no naylib or raylib_console imports. Backend modules are pulled in explicitly by the application. The core compiles cleanly on Vita without any desktop rendering headers in scope.

## NK_COMMAND coverage

See [docs/command-coverage.md](docs/command-coverage.md) for the full dispatch matrix, including provisional items (ARC, TRIANGLE winding).

## License

raddy is MIT licensed. Nuklear is vendored from https://github.com/Immediate-Mode-UI/Nuklear under the Unlicense (public domain). See `src/raddy/vendor/nuklear.h` for the full license.

The bundled test font `tests/assets/unscii-16.ttf` is [Unscii](http://viznut.fi/unscii/) — public domain / CC-0 (the non-`full` variant; the GPL `unscii-full`/Unifont-derived files are deliberately not vendored). See `tests/assets/LICENSE.txt`.
