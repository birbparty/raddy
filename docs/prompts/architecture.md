# raddy Architecture

raddy is a Nim library that wraps Nuklear (immediate-mode GUI) for use in naylib/raylib games
targeting desktop (Linux/macOS/Windows) and PS Vita. It bridges Nuklear's C API to Nim and
translates Nuklear's command queue into high-level raylib draw calls.

---

## What raddy Does

### Nuklear Context Lifecycle

1. At startup: allocate backing memory, call `nk_init_default` (desktop) or `nk_init_fixed`
   (Vita), load a raylib `Font`, build an `nk_user_font` that points back to it.
   **Check the return value:** both procs return `nk_bool`; treat `0` as `reInitFailed`.
2. Each frame: `nk_input_begin` → feed input (inside the begin/end boundary) → `nk_input_end`
   → build UI panels → check for buffer overflow → walk the command queue and emit raylib draw
   calls → call `nk_clear`.
3. At shutdown: call `nk_free`. On the fixed-buffer (Vita) path this is safe — it does not
   free `vitaCmdBuf`; it only releases allocator-owned state (of which there is none).

### Per-Frame Input Feed

All `nk_input_*` calls MUST occur **inside** the `nk_input_begin` / `nk_input_end` boundary.
Calling them before `nk_input_begin` is undefined behavior in Nuklear. What may happen before
`nk_input_begin` is raw OS polling (reading `GetMousePosition()` etc.) — but the results must
only be fed to Nuklear after the boundary opens.

The caller fills Nuklear's input by calling raddy's input-feed procs (`nkInputMotion`,
`nkInputButton`, `nkInputKey`, `nkInputScroll`, `nkInputUnicode`) or by calling the convenience
pump (`pumpNaylibInput` / `pumpVitaInput`). `nk_input_end` seals the input snapshot.

See `frame-order.md` — it is the authoritative reference for per-frame order; this section is
a summary only.

### Command-Queue Rendering

After the UI build, the renderer iterates the command queue via `nk__begin`/`nk__next` and
dispatches each `NK_COMMAND_*` variant to a raylib draw call. See `command-matrix.md` for the
exact per-command formulas.

---

## Why Command-Queue, Not Vertex Buffer

The PS Vita backend (`raylib_console.nim`) exposes ONLY high-level draw procs such as
`DrawRectangle`, `DrawCircle`, `DrawLineEx`, etc. It does NOT expose `rlgl`, vertex buffer
upload, or any equivalent to `rlBegin`/`rlEnd`. Therefore:

- `NK_INCLUDE_VERTEX_BUFFER_OUTPUT` is **NOT defined** — the vertex-buffer codepath is compiled
  out entirely.
- `NK_INCLUDE_FONT_BAKING` is **NOT defined** — the font atlas baker and its glyph-upload
  codepath are compiled out entirely. This avoids linker errors from missing GL functions and
  reduces binary size.
- `NK_INCLUDE_DEFAULT_FONT` is **NOT defined** — no embedded bitmap font is compiled in.
- `nk_convert` **MUST NEVER be called** anywhere in raddy. It requires vertex buffer output and
  will produce linker errors or undefined behavior if invoked.
- The renderer uses ONLY `nk__begin` / `nk__next` to iterate the command queue.

This is a deliberate, permanent design constraint. Do not attempt to add vertex-buffer support.

---

## NK_* Macros Defined

These macros MUST be defined **identically** in `src/raddy/vendor/nuklear_impl.c` AND in every
Nim module that imports `nuklear.h` (via `{.passC: "-D...".}` or a shared header wrapper).
Inconsistency triggers ODR violations and silent struct-layout mismatches.

| Macro | Defined? | Notes |
|---|---|---|
| `NK_INCLUDE_FIXED_TYPES` | YES | stdint.h types (`nk_uint`, etc.) |
| `NK_INCLUDE_STANDARD_BOOL` | YES | `nk_bool` = C99 `bool` (1 byte) |
| `NK_INCLUDE_STANDARD_VARARGS` | YES | required for `nk_layout_row` varargs |
| `NK_INCLUDE_DEFAULT_ALLOCATOR` | Desktop only | `nk_init_default`; NOT on Vita |
| `NK_INCLUDE_STANDARD_IO` | Only where needed | Required by some Nuklear debug paths |
| `NK_INCLUDE_VERTEX_BUFFER_OUTPUT` | **NEVER** | Would break Vita; do not add |
| `NK_INCLUDE_FONT_BAKING` | **NEVER** | Would break Vita; do not add |
| `NK_INCLUDE_DEFAULT_FONT` | **NEVER** | Bloats binary; do not add |

---

## One-Definition Rule (ODR)

EXACTLY ONE translation unit defines `NK_IMPLEMENTATION`:

```
src/raddy/vendor/nuklear_impl.c
```

This file defines `NK_IMPLEMENTATION` before including `nuklear.h`. No other `.c` file and no
Nim module may define `NK_IMPLEMENTATION`. Every other Nim module that needs Nuklear types or
procs uses `{.importc, header: "nuklear.h".}` declarations only — never `#include "nuklear.h"`
from a second `.c` file.

---

## Module Structure

```
src/
  raddy.nim                        # Public re-export entry point. Imports and re-exports
                                   # types, context, input, layout, widgets, style.
  raddy/
    types.nim                      # nk_* type bindings. Contains the nk_bool size assert.
                                   # No imports of naylib or any game module.
    context.nim                    # nk_context lifecycle: init, free, clear.
    input.nim                      # Input-feed procs wrapping nk_input_* C functions.
    layout.nim                     # Layout procs: rows, columns, groups, trees.
    widgets.nim                    # Widget procs: buttons, labels, sliders, etc.
    style.nim                      # Style manipulation procs.
    backend/
      render.nim                   # Command-queue renderer. Iterates nk__begin/nk__next.
                                   # Imports raylib_api.nim for draw calls.
      raylib_api.nim               # Platform seam (see below). Imports naylib or
                                   # raylib_console based on `when defined(vita)`.
      font.nim                     # Font loading and nk_user_font construction.
    vendor/
      nuklear_impl.c               # SOLE definition of NK_IMPLEMENTATION.
```

---

## Decoupled Core Rule

Every module under `src/raddy/` EXCEPT `src/raddy/backend/` MUST NOT import:
- `naylib`
- `raylib_console`
- `inputty`
- any game-specific module

The core (types, context, input, layout, widgets, style) depends only on the Nuklear C API and
Nim stdlib. This is enforced by `tests/test_import_purity.nim` which statically verifies the
import graph.

---

## Platform Seam: `src/raddy/backend/raylib_api.nim`

raddy defines its own normalized draw-proc surface using raddy-local type aliases. The backend
module is the ONLY place where platform-specific type names appear.

### raddy-local type aliases

```nim
# Defined in raylib_api.nim. Used throughout backend/.
type
  RColor* = ...   # maps to raylib Color / console Color
  RVec2*  = ...   # maps to raylib Vector2 / console Vector2
  RRect*  = ...   # maps to raylib Rectangle / console Rectangle
  RFont*  = ...   # maps to raylib Font / console Font
```

### Platform branching

```nim
when defined(vita):
  import raylib_console  # importc bindings for PS Vita raylib port
else:
  import raylib          # naylib's raylib wrapper for desktop
```

naylib and raylib_console have distinct, non-interchangeable type names and proc spellings.
`raylib_api.nim` normalizes them so that `render.nim` calls only `R*` aliases and is
platform-agnostic.

---

## nk_bool Binding

With `NK_INCLUDE_STANDARD_BOOL` defined, `nk_bool` is C99 `_Bool` / `bool` — exactly 1 byte.
It MUST be bound to Nim `bool`, NOT `cint`. A `cint` binding would produce ABI mismatches on
every Nuklear function that returns or accepts `nk_bool`.

Enforcement — add to `src/raddy/types.nim`:

```nim
static:
  doAssert sizeof(nk_bool) == 1, "nk_bool must be 1 byte (C99 bool). Check NK_INCLUDE_STANDARD_BOOL."
```

---

## Memory

### Desktop

```nim
# nk_init_default signature: (ctx, font) — 2 arguments; no allocator parameter.
if nk_init_default(addr ctx, addr userFont) == 0:
  return reInitFailed
```

Uses the system allocator (libc malloc/free). The backing buffer grows as needed. No fixed size.

### PS Vita

```nim
# RaddyCmdBufBytes is defined in src/raddy/context.nim. See error-strategy.md.
if nk_init_fixed(addr ctx, addr vitaCmdBuf[0], RaddyCmdBufBytes.nk_size, addr userFont) == 0:
  return reInitFailed
```

- Zero per-frame heap churn: the fixed buffer is reused every frame after `nk_clear`.
- 64 KiB is sized to hold one full overlay panel's command stream.
- `nk_init_fixed` silently drops commands when the buffer is exhausted — it does NOT crash or
  return an error mid-frame.

### Overflow detection (REQUIRED)

After the UI build phase and BEFORE rendering, check:

```nim
if ctx.memory.allocated >= ctx.memory.size:
  raddyCtx.bufOverflow = true
```

This requires binding `nk_buffer` with `allocated` and `size` fields as `nk_size`. See
`error-strategy.md` for the full response matrix. The renderer MUST skip drawing if
`bufOverflow` is set — a partial frame produces visual corruption (missing scissor resets,
clipped widgets). On desktop, `doAssert false, "Nuklear cmd buf overflow"` (loud crash). On
Vita, log once and continue with no draw calls.

---

## Lifetime Requirements

The following objects MUST all outlive the Nuklear context and MUST be pinned in memory
(address must not change after init):

1. The raylib `Font` object
2. The `nk_user_font` struct
3. The Nuklear backing buffer (desktop: implicit via allocator; Vita: `vitaCmdBuf` array)

The `Font` is passed to C via `nk_handle.ptr` — a raw pointer escape into C territory. If the
Font is a local variable or moves in memory (e.g., a seq element that gets reallocated), the
pointer becomes dangling and Nuklear will read garbage during text rendering.

Correct pattern: wrap all three in a single `ref object` and call `GC_ref` on it, OR declare
them as module-level globals. Do NOT store them as local variables in a proc.

---

## Per-Frame Order

Brief summary (see `frame-order.md` for the authoritative protocol):

1. `nk_input_begin`
2. Feed input (inside the boundary): call pump or individual `nk_input_*` procs
3. `nk_input_end`
4. Build UI: call Nuklear panel/widget procs
5. Check overflow: `if ctx.memory.allocated >= ctx.memory.size → raddyCtx.bufOverflow = true`
6. Render: iterate command queue via `nk__begin`/`nk__next`, emit raylib draw calls
7. `nk_clear`

`nk_clear` MUST be called every frame even if no UI was built, to reset the command queue.

---

## Compiler Flags by Platform

| Flag | Desktop | PS Vita |
|---|---|---|
| `--mm:` | `orc` | `arc` |
| `--opt:` | `speed` (default) | `size` |
| `--threads:` | on (default) | `off` |
| `--define:vita` | not set | set |

The `defined(vita)` compile-time flag is the canonical platform discriminator used throughout
`raylib_api.nim` and any other platform-branching code.
