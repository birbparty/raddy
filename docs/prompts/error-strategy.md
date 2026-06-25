# Global Error-Reporting Strategy

This file defines library-wide error handling for raddy. ALL fallible operations follow this strategy. Agents MUST NOT invent local error schemes — every fallible path maps to this document.

## Core Policy

All fallible procs return `bool` (true = success) or a `(value, bool)` out-param pair where
the caller also needs the return value. Do NOT use exceptions, and do NOT introduce a
`Result[T, E]` type — Nim's stdlib has no `Result`; adding `nim-results` or `questionable`
as a dependency is not approved for v1. Standardize on `bool` / out-params.

Do NOT use exceptions. The Vita build uses `--opt:size --threads:off` and exceptions add overhead and complicate `cdecl` callback boundaries. Exception support is not assumed.

```nim
type RaddyError* = enum
  reOk
  reInitFailed
  reFontNotFound
  reBufferOverflow
  reMissingHostProc
```

## Per-Platform Behavior Matrix

| Condition | Desktop | Vita |
|---|---|---|
| Init failure (`nk_init` returns false) | `doAssert false, msg` (crash loud) | return false, log once |
| Font load failure (`font.texture.id == 0`) | `stderr.writeLine "raddy: font load failed"`, set `fontOk=false`, continue | set `fontOk=false`, continue silently |
| Buffer overflow (`nk_init_fixed` exhausted) | `doAssert false, "Nuklear cmd buf overflow"` | set `overflowFlag`, log once per session |
| Missing host proc (nil function ptr) | `doAssert false, msg` | log once, no-op the command |
| Unsupported `NK_COMMAND_CUSTOM` | log once (debug) | log once |
| Width callback error | return `0.0` (never crash in cdecl) | return `0.0` |

## Command Buffer Size

```nim
const RaddyCmdBufBytes* {.intdefine.} = 65536  # 64 KiB
```

Defined in `src/raddy/errors.nim`. Override at build time: `-d:raddyCmdBufBytes=32768`.

**Rationale**: Holds one full overlay panel's command stream under `nk_init_fixed`. A typical raddy UI frame with ~20 widgets generates 2–4 KB of commands. 64 KiB gives 16–32x headroom. Revisit if overflow trips in practice.

On desktop, `nk_init_default` is used instead (heap-backed, unlimited). The fixed-buffer path MUST be exercised in tests via a `-d:vita`-like or `-d:raddyFixed` flag so overflow detection is not dead code.

## Buffer Overflow Detection

Nuklear silently drops commands when `nk_init_fixed` buffer is full. Detect by checking `ctx.memory.needed > ctx.memory.size` after the UI build phase.

**Important**: the correct predicate is `needed > size`, NOT `allocated >= size`. In `nk_buffer_alloc`, the `needed` counter is incremented before the full-buffer check; on overflow the function returns 0 without advancing `allocated`. So `allocated` stays below `size` even when commands were dropped. Bind `nk_buffer.needed: nk_size` in types.nim to access it.

**Binding requirement.** This check requires `nk_buffer` to be imported in `src/raddy/types.nim`
with at minimum the `allocated` and `size` fields bound as `nk_size`. The `nk_context.memory`
field is of type `nk_buffer`. Without this binding the check cannot compile. The check is only
meaningful on the `nk_init_fixed` path; on desktop (`nk_init_default`) the buffer is heap-backed
and this condition should never trigger.

If true: set `raddyCtx.bufOverflow = true`.

The renderer MUST check this flag and skip rendering. Emitting an incomplete frame is worse than a blank one on Vita — a partial draw with missing scissor resets or clipped widgets produces visual corruption.

## Logging

**Desktop**: `stderr.writeLine "raddy: " & msg`

Use a once-per-session flag per message type. Do not spam the same warning on every frame.

**Vita**: `debugWriteLine "raddy: " & msg` where `debugWriteLine` is:
- A no-op in release builds
- `SceKernelDebugPrintf` or similar in debug builds

In v1, if no debug channel is available on Vita, `discard` the message. Do not let logging code fail the build.

## cdecl Callback Rules

Applies to `raddyMeasureWidth` and any future callbacks registered with Nuklear via a C function pointer.

**Hard rules:**
- MUST NOT call `echo` or `stderr.writeLine`
- MUST NOT raise any exception (including `ValueError`, `Defect`, or `CatchableError`)
- MUST NOT allocate (no `new`, no `@[]`, no string construction)
- Return a safe zero/default value on any internal error
- No `doAssert` inside a cdecl callback — an unhandled exception or signal in a C callback is undefined behavior and will silently corrupt state or crash the process

These constraints exist because Nuklear calls these functions synchronously from C. The Nim runtime's exception machinery does not cross the C call boundary safely.
