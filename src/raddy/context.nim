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

proc nk_init_default*(ctx: ptr nk_context; font: ptr nk_user_font): nk_bool
    {.importc: "nk_init_default", header: nkH.}
  ## Heap-backed init (NK_INCLUDE_DEFAULT_ALLOCATOR required — desktop only).
  ## Returns nk_bool (0 = failure).

proc nk_init_fixed*(ctx: ptr nk_context; memory: pointer; size: nk_size;
                    font: ptr nk_user_font): nk_bool
    {.importc: "nk_init_fixed", header: nkH.}
  ## Fixed-buffer init — Nuklear silently drops commands on exhaustion (no realloc).
  ## `memory` must remain valid for the context's entire lifetime.
  ## Returns nk_bool (0 = failure).

proc nk_free*(ctx: ptr nk_context) {.importc: "nk_free", header: nkH.}
  ## Release internal context allocations. Not needed after nk_init_fixed.

proc nk_clear*(ctx: ptr nk_context) {.importc: "nk_clear", header: nkH.}
  ## Reset the command queue for the next frame.
  ## MUST be called AFTER raddyRender() drains the queue and BEFORE nk_input_begin().

# ---------------------------------------------------------------------------
# Per-session sentinel flags (module-level so "log once" survives across frames)
# ---------------------------------------------------------------------------

var overflowWarned = false
var initFailedWarned = false

# ---------------------------------------------------------------------------
# Nim-level wrappers
# ---------------------------------------------------------------------------

proc raddyCtxInit*(ctx: ptr nk_context; font: ptr nk_user_font;
                   buf: pointer = nil; bufLen: nk_size = 0): bool =
  ## Initialize a Nuklear context with the given font.
  ##
  ## Desktop (--mm:orc): calls nk_init_default. buf/bufLen are ignored.
  ## Vita (--mm:arc -d:vita): calls nk_init_fixed. Caller must provide buf pointing
  ## to a buffer of at least RaddyCmdBufBytes bytes, with lifetime >= ctx's lifetime.
  ##
  ## Returns true on success. Font pointer must outlive the context.
  when defined(vita):
    raddyAssertFatal buf != nil,
      "raddyCtxInit: buf must be non-nil on Vita (nk_init_fixed path)"
    raddyAssertFatal bufLen >= nk_size(RaddyCmdBufBytes),
      "raddyCtxInit: bufLen too small; allocate at least RaddyCmdBufBytes bytes"
    let ok = bool(nk_init_fixed(ctx, buf, bufLen, font))
    if not ok:
      raddyLogOnce(initFailedWarned, "nk_init_fixed returned false — context unusable")
    return ok
  else:
    let ok = bool(nk_init_default(ctx, font))
    raddyAssert ok, "nk_init_default returned false — context unusable", initFailedWarned
    return ok

proc raddyCtxFree*(ctx: ptr nk_context) {.inline.} =
  ## Release Nuklear context resources (desktop only — no-op after nk_init_fixed).
  ## Call once on teardown.
  nk_free(ctx)

proc raddyCtxClear*(ctx: ptr nk_context; bufOverflow: var bool) {.inline.} =
  ## Per-frame reset. Call AFTER raddyRender() and BEFORE the next nk_input_begin().
  ##
  ## Detects command-buffer overflow on the nk_init_fixed path (Vita / -d:raddyFixed):
  ## ctx.memory.allocated >= ctx.memory.size → commands were silently dropped.
  ## Sets bufOverflow=true if overflow detected this frame.
  ##
  ## Desktop: uses nk_init_default (heap-backed, unlimited); overflow cannot happen,
  ## but the check runs as a doAssert to catch misuse early.
  when defined(vita):
    bufOverflow = ctx.memory.allocated >= ctx.memory.size
    if bufOverflow:
      raddyLogOnce(overflowWarned,
        "Nuklear command buffer full — some commands were silently dropped this frame")
  else:
    bufOverflow = false
    doAssert ctx.memory.allocated < ctx.memory.size,
      "Nuklear cmd buf overflow (unexpected on nk_init_default/heap path)"
  nk_clear(ctx)
