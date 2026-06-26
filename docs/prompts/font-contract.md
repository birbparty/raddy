# Font Pipeline Contract

This file defines EXACTLY how raddy's font integration works. Agents must follow
these rules verbatim — any deviation risks crashes (dangling ptr), silent
measurement errors, or binary bloat.

> **Multi-size model.** raddy supports **runtime font switching** across multiple
> sizes (added in epic raddy-8an: `setRaddyFont`, `RaddyFont`/`raddyMakeFont`,
> `raddyBundleSetFont`). The earlier "one pinned font, `h` never diverges"
> invariant is **superseded** — a single context may render at several pixel
> sizes within one frame. The per-command measure/draw agreement still holds
> (see [The `height` rule](#the-height-rule)); it is now a *per-font* equality,
> not a single global constant.

## How to Load Fonts (one bake per size)

Loading is the consumer's responsibility, done once at app startup. For a
multi-size UI, bake **each size as its own `Font`** — one `loadFont` per ppem.
Do NOT load one atlas and scale it; scaling a bitmap atlas blurs glyphs.

```nim
# One distinct Font per pixel size you intend to render at.
var small = loadFont(fontPath, 16, 0)   # 16 px atlas
var large = loadFont(fontPath, 32, 0)   # 32 px atlas
setTextureFilter(small.texture, TextureFilter.Point)  # pixel-clean at small sizes
setTextureFilter(large.texture, TextureFilter.Point)
```

A single-size app simply bakes one `Font` — the multi-size machinery is additive
and imposes no cost when only one font is ever active.

**Asset path resolution** (done in the consumer's initialization, NOT inside
raddy):
- PS Vita: `app0:<your-asset-path>` (the `app0:` prefix is VitaSDK's CWD-relative
  asset root).
- Desktop: a path relative to the working directory (or absolute).

> The bundled **test** font and its exact path/license are sourced separately in
> raddy-8an.3 (recorded in `tests/assets/LICENSE.txt`); the acceptance spec
> resolves it at compile time (see `acceptance-test-model.md`). raddy itself
> bundles no font — `examples/demo.nim` uses `getFontDefault()`.

## Wrapping a Font: `RaddyFont`

Each loaded `Font` is paired with a Nuklear `nk_user_font` via the caller-owned
`RaddyFont` value (`src/raddy/backend/font.nim`):

```nim
var smallRf {.global.} = raddyMakeFont(addr small, 16.0f)  # ppem MUST match the bake size
var largeRf {.global.} = raddyMakeFont(addr large, 32.0f)
```

`raddyMakeFont(fontPtr, pixelSize)` wires `nk_user_font.height = pixelSize` and
`nk_user_font.width = raddyMeasureWidth`, and stores `fontPtr` in
`userdata.ptr`. Build one `RaddyFont` per size.

### Lifetime — two pointers escape into C, both caller-owned

1. **`fontPtr`** — Nuklear stores it in `userdata.ptr`; the width callback
   dereferences it during layout. The `RFont`/`Font` it points at MUST outlive
   every frame the font is active, at a **stable address** (a `{.global.}` or a
   long-lived field — never `addr` of a local or a movable seq element).
2. **`addr rf.nkFont`** (obtained via `raddyFontHandle(rf)`) — `setRaddyFont`
   stores it raw with **no copy**, and `raddyRender` dereferences it during the
   command walk. So the `RaddyFont` VALUE must itself stay live at a stable
   address from the moment it is set until **after** `raddyRender` consumes that
   frame. Because `RaddyFont` is a value type, a copy/move relocates `nkFont` —
   store it once and do not move it while it is the active font.

## Multi-Size Switching Workflow

Switch the active font between command groups inside a single `nk_begin`/
`nk_end`:

```nim
if raddyBegin(ctx, "panel", bounds, flags):
  setRaddyFont(ctx, raddyFontHandle(smallRf))   # everything emitted next uses 16 px
  raddyLabel(ctx, "small text")
  setRaddyFont(ctx, raddyFontHandle(largeRf))   # switch — forward-only
  raddyLabel(ctx, "BIG text")
  raddyEnd(ctx)
```

For a `RaddyCtxBundle`, the additive wrapper `raddyBundleSetFont(bundle, rf)`
does the same against the bundle's context.

### Switch semantics (grounded in `nk_style_set_font`, nuklear.h:19379)

`nk_style_set_font` (which `setRaddyFont` wraps) does exactly three things:
- sets `ctx->style.font = font` directly;
- resets the font config-stack head to 0 — the switch is **non-scoped / not
  stacked** (it is not a push/pop);
- if a window is current (`ctx->current`), calls
  `nk_layout_reset_min_row_height(ctx)` — so a **mid-frame** switch re-bases the
  current layout's minimum row height to the new font.

Consequences callers must rely on:
- **Forward-only.** A switch affects only widgets emitted *after* the call,
  within the same `nk_begin`/`nk_end` and in subsequent frames.
- **Persists across frames.** `nk_clear` (per-frame queue reset) does **not**
  touch `ctx.style.font`. A font set in frame 1 is still active in frame 2 with
  no re-switch; re-init the context to fully reset.
- **Mid-frame switching is supported** — change font as many times as needed
  within one frame; each switch resets the current layout's min row height.
- **Borrowed, never retained.** `setRaddyFont` ignores a nil `font`/`ctx`
  (early return — a guard raw `nk_style_set_font` lacks), but otherwise stores
  the raw pointer; the lifetime contract above is the caller's to honor.

## The `height` rule

`nk_user_font.height` MUST equal the pixel size the font was baked at, for BOTH
measuring and drawing — set once by `raddyMakeFont(fontPtr, pixelSize)`.

Under multi-size switching this is a **per-font** equality, not a single global
constant:
- Nuklear passes the **active** font's `height` as the `h` argument to the width
  callback. As the active font changes per command group, so does `h`.
- For any one emitted text command, Nuklear records the active font and its
  height into the command (`nk_command_text.font`, `nk_command_text.height`). So
  the measure-time `h` and the draw-time `tc.height` for that command come from
  the **same** `nk_user_font` and are therefore equal.

Therefore measure size and draw size still agree **per command**, which is what
prevents overflow/clipping — they are simply no longer one global value. Never
hand-set `nkFont.height` to anything other than the bake ppem, or that font's
measure and draw will diverge.

## Width Callback

The ONLY C-callable function raddy exposes (`src/raddy/backend/font.nim`):

```nim
proc raddyMeasureWidth(handle: nk_handle; h: float32; text: cstring; len: cint): float32
    {.cdecl, gcsafe, raises: [].}
```

The signature uses `float32` (not the wider `cfloat` spelling) so the assignment
`nkFont.width = raddyMeasureWidth` is provably type-compatible with
`nk_text_width_f`. Implementation rules (all are hard requirements):

- Nuklear passes a NON-null-terminated `char*` and explicit `len`. Do NOT convert
  to a Nim `string` (would allocate on heap — forbidden in a cdecl callback under
  arc/orc on Vita).
- Copy into a fixed stack buffer (`RaddyMaxTextBytes` = 1024) and truncate
  safely:
  ```nim
  let copyLen = min(int(len), RaddyMaxTextBytes - 1)
  copyMem(addr buf[0], text, copyLen)
  buf[copyLen] = '\0'
  ```
- Call `MeasureTextEx(font, cast[cstring](addr buf[0]), h, RaddyMeasureSpacing)`
  and return `.x`. Pass the callback's `h`, NOT a hard-coded size — that is how
  per-command size correctness is preserved under switching.
- Retrieve the `RFont` from `handle.ptr` cast to `ptr RFont`, then dereference.
- **Self-guards** (no crash, no UB): returns `0.0` when `text == nil`,
  `len <= 0`, the font pointer is nil, or `h <= 0` / `h` is NaN (the `h != h`
  test) — a NaN propagated into Nuklear layout arithmetic is undefined behavior
  across the FFI boundary.
- NO echo/log, NO raise, NO allocation inside this callback.

## Spacing Contract

Text spacing is the shared constant `RaddyMeasureSpacing = 2.0`
(`src/raddy/backend/font.nim:23`). `MeasureTextEx` (measure, in the callback) and
`rDrawTextEx` (draw, in `render.nim`'s `NK_COMMAND_TEXT` handler) MUST pass the
**same** spacing or text overflows its Nuklear-allocated bounding box.

`render.nim` imports `RaddyMeasureSpacing` from `font.nim` rather than
duplicating the literal — do NOT re-type `2.0` in either file. It is a pinned
constant; do NOT make it configurable in v1.

## Missing / Unloaded Font

`raylib`'s `loadFont*` returns a `Font` BY VALUE even when the TTF fails to bake,
leaving `texture.id == 0`. Detect this with `raddyFontLoaded(fontPtr)`
(`raylib_api.nim`) **before** building a `RaddyFont`, and log the failure once.

A `RaddyFont` built from a nil or unloaded font is still **usable, non-crashing**:
- `raddyMeasureWidth` returns `0.0` immediately for a nil font handle (above), so
  layout proceeds without measuring.
- `raddyRender`'s `NK_COMMAND_TEXT` handler reads the per-command font from
  `tc.font.userdata.ptr` and skips drawing when it is nil (Nuklear may emit text
  with a fallback font before the host sets one).

Text simply does not render; nothing crashes.
