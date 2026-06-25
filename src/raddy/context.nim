## context.nim — nk_context lifecycle and per-frame management.
##
## Provides C FFI bindings for nk_init_default / nk_init_fixed / nk_free / nk_clear
## and Nim-level wrappers that handle the desktop / Vita split and error reporting.
##
## Init signature: the caller supplies the nk_user_font pointer.
## The font→context ordering invariant (font must outlive the context) is enforced
## by the long-lived object task (raddy-8nm). This module does NOT create fonts.
##
## Decoupled-core rule: MUST NOT import naylib, raylib_console, inputty, or any
## game-specific module.

import ./vendor  ## side-effect: compile nuklear_impl.c; inject nk_config.h
import ./types
import ./errors

const nkH = "nuklear.h"

# ---------------------------------------------------------------------------
# Raw C FFI bindings
# ---------------------------------------------------------------------------

when not defined(vita):
  proc nk_init_default*(ctx: ptr nk_context; font: ptr nk_user_font): nk_bool
      {.importc: "nk_init_default", header: nkH.}
    ## Heap-backed init. Only available when NK_INCLUDE_DEFAULT_ALLOCATOR is defined
    ## (i.e., desktop builds). Calling on Vita is a link error — guard call sites
    ## with `when not defined(vita):`.

proc nk_init_fixed*(ctx: ptr nk_context; memory: pointer; size: nk_size;
                    font: ptr nk_user_font): nk_bool
    {.importc: "nk_init_fixed", header: nkH.}
  ## Fixed-buffer init. Nuklear silently drops commands when full (no realloc).
  ## `memory` must remain valid for the context's entire lifetime.

proc nk_free*(ctx: ptr nk_context) {.importc: "nk_free", header: nkH.}
  ## Release internal context allocations. Not needed after nk_init_fixed, but safe.

proc nk_clear*(ctx: ptr nk_context) {.importc: "nk_clear", header: nkH.}
  ## Reset the command queue for the next frame.
  ## MUST be called AFTER raddyRender() drains the queue and BEFORE nk_input_begin().

# ---------------------------------------------------------------------------
# Per-session sentinel flags (module-level, one per process; single-context assumption)
# ---------------------------------------------------------------------------

var overflowWarned  = false  ## set once when buffer overflow is first detected
var initFailedWarned = false  ## set once if init fails (Vita path)

# ---------------------------------------------------------------------------
# Nim-level wrappers
# ---------------------------------------------------------------------------

proc raddyCtxInit*(ctx: ptr nk_context; font: ptr nk_user_font;
                   buf: pointer = nil; bufLen: nk_size = 0): bool {.raises: [].} =
  ## Initialize a Nuklear context with the given font.
  ##
  ## Desktop (not -d:vita, not -d:raddyFixed): uses nk_init_default (heap, growing).
  ##   buf/bufLen are ignored.
  ## Vita or -d:raddyFixed: uses nk_init_fixed. buf must point to a buffer of at
  ##   least RaddyCmdBufBytes bytes whose lifetime equals or exceeds the context.
  ##
  ## Returns true on success. On success, font pointer must outlive the context.
  ## Call raddyCtxFree only after a successful init.
  when defined(vita) or defined(raddyFixed):
    raddyAssertFatal buf != nil,
      "raddyCtxInit: buf must be non-nil on fixed-buffer path"
    raddyAssertFatal bufLen >= nk_size(RaddyCmdBufBytes),
      "raddyCtxInit: bufLen too small; use at least RaddyCmdBufBytes bytes"
    let ok = bool(nk_init_fixed(ctx, buf, bufLen, font))
    if not ok:
      raddyLogOnce(initFailedWarned, "nk_init_fixed returned false — context unusable")
    return ok
  else:
    let ok = bool(nk_init_default(ctx, font))
    raddyAssert ok, "nk_init_default returned false — context unusable", initFailedWarned
    return ok

proc raddyCtxFree*(ctx: ptr nk_context) {.inline, raises: [].} =
  ## Release Nuklear context resources. Only call after raddyCtxInit returned true.
  ## On nk_init_fixed paths nk_free is a no-op (does not own the memory),
  ## but calling it is safe.
  nk_free(ctx)

proc raddyCtxClear*(ctx: ptr nk_context; bufOverflow: var bool) {.inline, raises: [].} =
  ## Per-frame reset. Call AFTER raddyRender() drains the queue and BEFORE
  ## the next nk_input_begin().
  ##
  ## Overflow detection on the fixed-buffer path (Vita / -d:raddyFixed):
  ##   ctx.memory.needed > ctx.memory.size → commands were silently dropped.
  ## Why `needed` not `allocated`: nk_buffer_alloc increments `needed` before
  ## the full check, then returns 0 without advancing `allocated`. So `allocated`
  ## stays below `size` even when overflow occurred; `needed` exceeds `size`.
  ## See src/raddy/vendor/nuklear.h:nk_buffer_alloc for the authoritative source.
  ##
  ## Sets bufOverflow=true if overflow occurred this frame, false otherwise.
  ## The renderer MUST check bufOverflow and skip emitting a partial frame.
  when defined(vita) or defined(raddyFixed):
    bufOverflow = ctx.memory.needed > ctx.memory.size
    if bufOverflow:
      raddyLogOnce(overflowWarned,
        "Nuklear command buffer full — some commands were silently dropped this frame")
  else:
    bufOverflow = false  ## desktop heap path cannot overflow
  nk_clear(ctx)
