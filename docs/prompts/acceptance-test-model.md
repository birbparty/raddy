# Real-TTF Acceptance Test Execution Model

> Decision record for bead **raddy-8an.2**. Implementers of **raddy-8an.8**
> (wire the nimble task) and **raddy-8an.9** (write the spec) MUST follow this
> verbatim. Also recorded on the bead — read via `bd show raddy-8an.2`.

## Central risk this resolves

`nimble test` (raddy.nimble:38) does **not** link real raylib and does **not**
open a GL context. The font tests under `tests/test_*.nim` satisfy the linker
with `{.emit.}` C stubs for `MeasureTextEx` and never call `InitWindow` /
`LoadFont`. A real-TTF acceptance test needs the **real** raylib symbols
(`LoadFont`, `MeasureTextEx`) **and** an initialized GL/window context, so it
cannot run under the stubbed `nimble test`. It must be a **separate target**
that is deliberately excluded from the `test_`-glob loop.

## 1. TASK NAME

A new, separate nimble task named **`acceptance`** in `raddy.nimble`.

- It is independent of `test` / `check` / `check_vita` — do **not** alter their
  stub behaviour (raddy-8an.8 acceptance criterion).
- Invoked explicitly: `nimble acceptance`. It is **not** part of `nimble test`.

## 2. EXACT INVOCATION

The `acceptance` task discovers `bddy` and `naylib` the same way the existing
`test` task discovers `bddy` (find under `~/.nimble/pkgs2`), then compiles +
runs the single acceptance spec linking **real** raylib via naylib.

The decisive difference from the `test` task: the `acceptance` build adds
`--path:$naylibDir` so `import raylib` resolves to **naylib's real module**
(which compiles + links the raylib C library through naylib's own build hooks),
instead of relying on `{.emit.}` stubs. It still passes
`--passC:"-I$naylibDir/raylib"` so raddy's `raylib_api.nim` importc declarations
see `raylib.h`.

```nim
task acceptance, "Run the real-raylib acceptance spec (needs a GL context)":
  let home = getEnv("HOME")
  # bddy (spec framework) — same discovery as the `test` task.
  let (bddyRaw, bddyCode) = gorgeEx(
    "find " & home & "/.nimble/pkgs2 -maxdepth 1 -name 'bddy-*' -type d")
  let bddyDirs = bddyRaw.strip().splitLines()
  if bddyCode != 0 or bddyDirs.len == 0 or bddyDirs[0].len == 0:
    quit "raddy acceptance: bddy not found — run: nimble install bddy"
  if bddyDirs.len > 1:
    echo "raddy acceptance: WARNING multiple bddy-* dirs, using " & bddyDirs[0]
  let bddyDir = bddyDirs[0]
  # naylib (REAL raylib) — required for the real LoadFont/MeasureTextEx + window.
  let (naylibRaw, naylibCode) = gorgeEx(
    "find " & home & "/.nimble/pkgs2 -maxdepth 1 -name 'naylib-*' -type d")
  let naylibDirs = naylibRaw.strip().splitLines()
  if naylibCode != 0 or naylibDirs.len == 0 or naylibDirs[0].len == 0:
    quit "raddy acceptance: naylib not found — run: nimble install naylib"
  if naylibDirs.len > 1:
    echo "raddy acceptance: WARNING multiple naylib-* dirs, using " & naylibDirs[0]
  let naylibDir = naylibDirs[0]
  let flags = "--mm:orc --hints:off --path:src" &
              " --path:" & bddyDir &
              " --path:" & naylibDir &
              " --passC:\"-I" & naylibDir & "/raylib\""
  exec "nim c " & flags & " -r tests/acceptance_smoke.nim"
```

Notes:
- `--mm:orc` matches the desktop demo build (`examples/demo.nim`) and is also
  set by the repo-root `nim.cfg` (which `nim c` inherits by walking up the
  tree). The task passes it explicitly to mirror the existing `test` task; it is
  not lost if the flag list changes. (raddy's font/filter callbacks build clean
  under Apple clang with no fn-ptr-compat flag — their proc types emit
  const-qualified C pointers matching Nuklear's typedefs as of raddy-u7d; the
  old `-Wno-error=incompatible-function-pointer-types` workaround is gone.)
- naylib/bddy versions are discovered, not pinned. The versions observed at the
  time of writing were `naylib-26.08.0` and `bddy-0.1.0` (under
  `~/.nimble/pkgs2/`) — recorded only as a sanity reference; do not hardcode
  them. The `find` discovery keeps the task portable across version bumps.
- naylib links the raylib C library itself once its module is imported; no
  extra `--passL` is required on the dev host (macOS).

### Window strategy — hidden window, real GL context

Open a **hidden** real window so a GL context exists without a visible window:

```nim
import raylib   # naylib
setConfigFlags(flags(WindowHidden))   # FLAG_WINDOW_HIDDEN (=128) — set BEFORE initWindow
initWindow(320, 240, "raddy acceptance")
doAssert isWindowReady(), "no GL context"   # see HEADLESS FALLBACK below
# ... loadFont(path, ppem, 0) per size; build one frame; raddyRender ...
closeWindow()
```

Grounded naylib symbols (naylib `raylib.nim`):
- `setConfigFlags(flags: Flags[ConfigFlags])` + enum `WindowHidden = 128`
- `initWindow(width, height: int32; title: string)`
- `isWindowReady(): bool` — the readiness guard
- `loadFont(fileName: string; fontSize, glyphCount: int32): Font` — distinct
  `LoadFont` per ppem (do **not** scale one atlas)
- `closeWindow()`

### Resolving the bundled TTF — and a note on `config.nims`

bead raddy-8an.8 literally says "ensure `tests/config.nims` also resolves
`tests/assets/`". **That wording is superseded by this decision:** `config.nims`
adds a Nim **module search path** (`$projectDir/../src`), which governs `import`
resolution, not runtime file lookup — it cannot make `loadFont` find an asset.
Leave `config.nims` unchanged. Instead the spec resolves `tests/assets/` at
compile time from its own location, so the font loads regardless of CWD:

```nim
import std/os
const assetsDir = currentSourcePath().parentDir / "assets"
# e.g. loadFont(assetsDir / <fontFile>, ppem, 0)
```

The `.8` implementer should follow this doc, not the bead's `config.nims`
sentence.

### Framebuffer dimensions and render target

`raddyRender(ctx, framebufferH: int32, bufOverflow: var bool)` takes the
framebuffer height **explicitly** (`src/raddy/backend/render.nim:87`). Its own
contract states direct-to-screen rendering is **not supported** — scissor
commands apply a Y-flip for raylib's bottom-up FBO origin — so the acceptance
frame MUST render into a `RenderTexture` inside `beginTextureMode`, passing
`rt.texture.height` as `framebufferH` (mirror `examples/demo.nim:174-188`).
Do not call `getScreenWidth/Height`; pass explicit dimensions. (As a secondary
aside, those globals also read 0 on the Vita binding, but the binding reason
above is the one that holds on desktop.)

For the minimal smoke frame (one text + one filled rect + one rect outline, no
clipped region) no `NK_COMMAND_SCISSOR` is emitted, so `framebufferH` only acts
as a guard value there — but use a `RenderTexture` anyway to stay within the
supported path.

### Stable addresses (carried over from raddy-8an.9)

Each `RaddyFont` value and the `Font` it borrows must stay live at a **stable
address** from `setRaddyFont`/`raddyBundleSetFont` until **after** the
`raddyRender` call consumes that frame — the raw pointer is stored in
`nk_handle`/`ctx.style.font` with no copy (see the lifetime contract in
`src/raddy/backend/font.nim`). Hold each font in a module-level/`{.global.}`
var; never `addr` a local or a movable seq element.

## 2b. Bundled TTF + what the spec asserts

### The font asset (depends on raddy-8an.3)

The spec loads a bundled CC0/OFL TTF from `tests/assets/`. That asset does
**not exist yet** — it is delivered by **raddy-8an.3**, which also records the
exact filename + license in `tests/assets/LICENSE.txt`. raddy-8an.9 already
`DEPENDS ON` raddy-8an.3, so the spec cannot be written verbatim until .3
lands. Use the filename .3 records (referenced here as `<fontFile>`); do **not**
invent one, and do **not** reference topdown's `assets/fonts/match7.ttf`.

### Assertions (raddy-8an.9)

Build ONE frame and assert, per the bead:

- **Two distinct sizes.** Load the TTF at TWO distinct ppem via **separate**
  `loadFont(assetsDir / <fontFile>, ppem, 0)` calls (one atlas per ppem, never
  one atlas scaled). Pick two ppems that raddy-8an.3 actually bakes (its
  candidate set is 8/10/16/20/32 px) — e.g. **16 and 32**. Switch the active
  font between groups via `setRaddyFont` / `raddyBundleSetFont`.
- **Geometry.** Emit text + a filled rect + a rect outline, then call
  `raddyRender(ctx, rt.texture.height, bufOverflow)` (inside `beginTextureMode`,
  per the render-target note above).
- **Width parity, ≤1px per line.** For a known multi-glyph string, assert
  `raddyMeasureWidth` (raddy's Nuklear width callback) matches raylib's
  `MeasureTextEx(font, str, ppem, spacing)` within **≤1px for each line**
  measured. The spacing argument MUST be the shared constant
  `RaddyMeasureSpacing` (`src/raddy/backend/font.nim:23`, value `2.0`) — import
  and reference it; do **not** re-type the `2.0` literal, or measure/draw will
  silently diverge. Compare line-by-line for multi-line strings (Nuklear
  measures per line, not the whole block).

## 3. TEST FILE NAME

**`tests/acceptance_smoke.nim`** — deliberately chosen to **not** contain the
substring `test_`. raddy.nimble:38 runs every `tests/*.nim` whose name
*contains* `test_` under the stubbed `test` task; a name without `test_` is
never picked up there. Do **NOT** name it `tests/test_acceptance*.nim` or
`tests/test_smoke_acceptance.nim` — those would run under stubbed `nimble test`
and fail to link real raylib.

## 4. HEADLESS FALLBACK

The acceptance spec needs a real GL/window context. Handling when none is
available:

1. **Linux CI with no display:** wrap the invocation in xvfb —
   `xvfb-run -a nimble acceptance`. This supplies a virtual framebuffer so
   `initWindow` + hidden window get a usable GL context.
2. **No GL context obtainable** (`isWindowReady()` is false, or `initWindow`
   aborts): the spec MUST NOT report a green/skipped pass. Flag the acceptance
   bead for human / on-device execution by adding the `human` label (this is
   what `bd human list` surfaces — `bd human` itself only has the subcommands
   `list`/`respond`/`dismiss`/`stats`, NOT a bare-id form):

   ```
   bd update raddy-8an.9 --add-label human
   bd human list            # confirm it now appears as human-needed
   ```

   A headless **SKIP is explicitly NOT a pass.** Under the Ralph loop, if
   raddy-8an.9 cannot obtain a GL context, do not merge a skipped or stubbed
   pass — flag via the `human` label (above) and halt that bead for
   human/on-device sign-off.

   The dev host here is macOS, where `FLAG_WINDOW_HIDDEN` + `initWindow`
   yields a real hidden GL window, so the local run is expected to execute the
   real assertions rather than fall back.
