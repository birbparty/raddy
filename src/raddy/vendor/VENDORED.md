# Vendored Dependencies

## Nuklear

- **Upstream:** https://github.com/Immediate-Mode-UI/Nuklear
- **Version/Tag:** v4.13.3
- **Upstream commit:** `https://github.com/Immediate-Mode-UI/Nuklear/releases/tag/4.13.3`
- **Vendored files:**
  - `nuklear.h` — upstream single-header C immediate-mode GUI library (unmodified)
  - `nuklear_impl.c` — raddy's sole TU that defines `NK_IMPLEMENTATION`
  - `nk_config.h` — raddy's canonical `NK_*` macro configuration
- **SHA256 of `nuklear.h`:** `41b8ef9e19c176e7f902670f12acd1f6f458ac22576a303e72b2f55ffa429f36`
- **License:** MIT / Public Domain dual (see `LICENSE`)

### What was changed

`nuklear.h` is **not modified**. Two raddy-specific files sit alongside it:

- `nk_config.h` — controls which Nuklear features are compiled in. Key choices:
  - `NK_INCLUDE_DEFAULT_ALLOCATOR` is defined only on desktop (not Vita/`NK_VITA`);
    Vita uses `NK_BUFFER_FIXED` / `nk_init_fixed`.
  - `NK_INCLUDE_VERTEX_BUFFER_OUTPUT` is **not** defined — the vertex path is
    compiled out to avoid link errors and reduce binary size.
  - `NK_INCLUDE_FONT_BAKING` is **not** defined — raddy uses pre-loaded raylib fonts.

- `nuklear_impl.c` — `#include "nk_config.h"` then `#define NK_IMPLEMENTATION`
  then `#include "nuklear.h"`. This is the single translation unit that emits
  all Nuklear function definitions; every other Nuklear import is declaration-only.
  ODR is enforced: `nuklear.h` is included exactly once across the binary.

### Embedded dependencies inside nuklear.h

Nuklear embeds the following stb public-domain libraries (unmodified):
- `stb_textedit.h` by Sean Barrett (public domain)
- `stb_truetype.h` by Sean Barrett (public domain)
- `stb_rect_pack.h` by Sean Barrett (public domain)
- ProggyClean.ttf font by Tristan Grimmer (MIT license)

### Upgrading

To upgrade Nuklear:

1. Download the new `nuklear.h` from upstream and replace `src/raddy/vendor/nuklear.h`.
2. Update the `SHA256` and `Version/Tag` fields in this file.
3. Regenerate the SHA256 with: `sha256sum src/raddy/vendor/nuklear.h`
4. Review `nk_config.h` for any new macros that should be opted in/out.
5. Run `./scripts/verify.sh` — it checks the SHA256 and runs the full test suite.
