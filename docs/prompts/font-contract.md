# Font Pipeline Contract

This file defines EXACTLY how raddy's font integration works. Agents must follow these rules verbatim — any deviation risks crashes (dangling ptr), silent measurement errors, or binary bloat.

## How to Load the Font

Consumer's responsibility, done once at app startup:

```nim
let font = loadFont("assets/fonts/match7.ttf", 32, 0)  # 32px, no codepoints filter
setTextureFilter(font.texture, TEXTURE_FILTER_POINT)    # Point filter — pixel-clean at small sizes
```

**Asset path resolution** (done in the consumer's initialization, NOT inside raddy):
- PS Vita: `app0:assets/fonts/match7.ttf` (the `app0:` prefix is VitaSDK's CWD-relative asset root)
- Desktop: `assets/fonts/match7.ttf`

## The `font.height` Rule

`nk_user_font.height` MUST equal the pixel size used for BOTH measuring AND drawing. For a font loaded at size 32 with Point filter, `font.baseSize == 32 == render size`. Set:

```nim
nkFont.height = cfloat(font.baseSize)
```

Do NOT use a different size for measuring vs drawing or text will overflow/clip.

## Width Callback

The ONLY C-callable function raddy exposes:

```nim
proc raddyMeasureWidth(handle: nk_handle; h: cfloat; text: cstring; len: cint): cfloat
    {.cdecl, gcsafe, raises: [].}
```

Implementation rules (all are hard requirements):

- Nuklear passes a NON-null-terminated `char*` and explicit `len`. Do NOT convert to a Nim `string` (would allocate on heap — forbidden in a cdecl callback under arc/orc on Vita).
- Copy into a fixed stack buffer of 1024 bytes max, truncate safely:
  ```nim
  bufLen = min(len, 1023)
  copyMem(addr buf[0], text, bufLen)
  buf[bufLen] = '\0'
  ```
- Call `MeasureTextEx(font, cast[cstring](addr buf[0]), h, 2.0)` and return `.x`.
- **Invariant:** Nuklear always passes `nk_user_font.height` as the `h` argument to this
  callback. So `h` == `nkFont.height` == `font.baseSize` at all times under the pinned font
  contract. Draw size and measure size are therefore guaranteed equal — there is no case where
  they diverge with a single pinned font.
- `spacing = 2.0` matches the `DrawTextEx` spacing used in NK_COMMAND_TEXT handling.
- Retrieve `font` from `handle.ptr` cast to `ptr Font` then dereferenced. The Font MUST be pinned (see architecture.md lifetime section) — a dangling ptr here is silent corruption.
- NO echo, NO raise, NO allocation inside this callback.

## nk_user_font Initialization

```nim
var nkFont: nk_user_font
nkFont.userdata.ptr = unsafeAddr ctx.font  # ctx.font is the pinned Font
nkFont.height = cfloat(font.baseSize)
nkFont.width = raddyMeasureWidth
```

This `nk_user_font` is passed to `nk_init_*` and installed before ANY `nk_begin` call.

## Spacing Contract

`DrawTextEx` uses `spacing = 2.0` always. `MeasureTextEx` uses the SAME `spacing = 2.0`. If they diverge, text will overflow its Nuklear-allocated bounding box.

This value is a pinned constant — do NOT make it configurable in v1.

## Missing Font Fallback

If `loadFont` fails (file not found), `font.texture.id == 0`. Set a `fontOk: bool` flag in the raddy context.

When `fontOk == false`:
- NK_COMMAND_TEXT procs call the width callback with zero result (no draw)
- `raddyMeasureWidth` returns `0.0` immediately
- Log the failure once on init

Do NOT crash.
