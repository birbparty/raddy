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
  let bddyDir = bddyDirs[0]
  # naylib (REAL raylib) — required for the real LoadFont/MeasureTextEx + window.
  let (naylibRaw, naylibCode) = gorgeEx(
    "find " & home & "/.nimble/pkgs2 -maxdepth 1 -name 'naylib-*' -type d")
  let naylibDirs = naylibRaw.strip().splitLines()
  if naylibCode != 0 or naylibDirs.len == 0 or naylibDirs[0].len == 0:
    quit "raddy acceptance: naylib not found — run: nimble install naylib"
  let naylibDir = naylibDirs[0]
  let flags = "--mm:orc --hints:off --path:src" &
              " --path:" & bddyDir &
              " --path:" & naylibDir &
              " --passC:\"-I" & naylibDir & "/raylib\""
  exec "nim c " & flags & " -r tests/acceptance_smoke.nim"
```

Notes:
- `--mm:orc` matches the desktop demo build (`examples/demo.nim`).
- naylib here is `naylib-26.08.0` at `~/.nimble/pkgs2/naylib-*`; `bddy-0.1.0` at
  `~/.nimble/pkgs2/bddy-*`. Discovery (not a pinned path) keeps it portable.
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

`tests/config.nims` currently only adds `$projectDir/../src` to the path. For
the acceptance spec, resolve `tests/assets/` from the spec file using
`currentSourcePath()` parent + `/assets/` (compile-time path), so the bundled
TTF (raddy-8an.3) loads regardless of CWD. Do **not** use
`getScreenWidth/Height` for the framebuffer dims — they return 0 on the Vita
binding; pass explicit dimensions to `raddyRender`.

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
   bead for human / on-device execution:

   ```
   bd human raddy-8an.9
   ```

   A headless **SKIP is explicitly NOT a pass.** Under the Ralph loop, if
   raddy-8an.9 cannot obtain a GL context, do not merge a skipped or stubbed
   pass — flag via `bd human` and halt that bead for human/on-device sign-off.

   The dev host here is macOS, where `FLAG_WINDOW_HIDDEN` + `initWindow`
   yields a real hidden GL window, so the local run is expected to execute the
   real assertions rather than fall back.
