## errors.nim — library-wide error-reporting strategy for raddy.
##
## ALL fallible operations return bool (true = success) or use an out-param pair.
## No exceptions. No Result type. No third-party dependencies.
## See docs/prompts/error-strategy.md for the full rationale and platform matrix.
##
## Decoupled-core rule: MUST NOT import naylib, raylib_console, inputty, or any
## game-specific module.

const
  RaddyCmdBufBytes* = 65536 ## 64 KiB fixed command buffer for nk_init_fixed.
  ## One full overlay panel at ~2–4 KB/frame gives ~16-32x headroom.
  ## Override -d:raddyCmdBufBytes=N at build time for tight platforms.
  ## On desktop, nk_init_default is used instead (heap-backed, no fixed limit).

type
  RaddyError* = enum
    reOk
    reInitFailed      ## nk_init returned false
    reFontNotFound    ## font texture id == 0 after load
    reBufferOverflow  ## nk_init_fixed command buffer exhausted (Vita path)
    reMissingHostProc ## nil function pointer in host draw-proc surface
    reUnsupportedCmd  ## NK_COMMAND_CUSTOM or other unhandled command type

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

proc raddyLog*(msg: string) {.inline.} =
  ## Write a one-off diagnostic message.
  ## Desktop: stderr. Vita: debugWriteLine (no-op in release; SceKernelDebugPrintf
  ## in debug). In both cases: never raise, never allocate beyond msg.
  when defined(vita):
    when defined(debug):
      proc debugWriteLine(s: cstring) {.importc: "debugWriteLine", header: "debugnet.h".}
      debugWriteLine(("raddy: " & msg).cstring)
    else:
      discard
  else:
    stderr.writeLine("raddy: " & msg)

template raddyLogOnce*(sentinel: var bool; msg: string) =
  ## Log msg at most once per session.  `sentinel` is a module-level bool that
  ## the call site owns; pass a different sentinel per distinct message.
  if not sentinel:
    sentinel = true
    raddyLog(msg)

# ---------------------------------------------------------------------------
# Assertion helpers
# ---------------------------------------------------------------------------

template raddyAssert*(cond: bool; msg: string; sentinel: var bool) =
  ## Platform-adaptive fatal assertion.
  ## Desktop: doAssert (crashes loud — finds bugs during development).
  ## Vita:    log once and continue (partial frame is better than a hard crash
  ##          on a device with no debugger attached).
  when not defined(vita):
    doAssert cond, msg
  else:
    if not cond:
      raddyLogOnce(sentinel, msg)

template raddyAssertFatal*(cond: bool; msg: string) =
  ## Fatal assertion on both platforms (no sentinel — used for truly unrecoverable
  ## conditions like a corrupt context pointer that make continuation meaningless).
  doAssert cond, msg

# ---------------------------------------------------------------------------
# cdecl callback rules (enforced by convention, not the type system)
# ---------------------------------------------------------------------------
## Any proc registered as a C callback (nk_text_width_f, future draw hooks) MUST:
##   1. Not raise — Nim exceptions do not cross the C call boundary safely.
##   2. Not echo/writeLine — only safe Nuklear state transitions.
##   3. Not allocate — no new, @[], or string construction.
##   4. Return a safe zero/default on any internal error.
## See docs/prompts/error-strategy.md §cdecl Callback Rules.
