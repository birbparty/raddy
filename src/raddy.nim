## raddy — Nuklear immediate-mode GUI binding for naylib/raylib games.
##
## Single import point: `import raddy` gives a consumer everything needed to
## initialize a Nuklear context, feed input, build UI, and render it.
##
## Public surface (populated as submodules are implemented):
##   Types     — RaddyCtx, RaddyFont, nk_bool, nk_color, NK_COMMAND_* enums
##   Lifecycle — newRaddyCtx, raddyDestroy
##   Input     — nkInputBegin/End, nkInputMotion/Button/Key/Scroll/Unicode
##   Frame     — nkClear
##   Render    — raddyRender (translates command queue to raylib draw calls)
##
## Platform: desktop (--mm:orc, naylib) and PS Vita (--mm:arc, raylib_console).
## Build with 'nim c --path:src', NOT 'nimble build' (srcDir flatten pitfall).
##
## Submodules live under src/raddy/ and are re-exported here as they are added.
## This file intentionally starts empty — submodule imports are added alongside
## each implementation task so the entry point always compiles.

import raddy/types
export types

import raddy/errors
export errors

import raddy/context
export context

import raddy/backend/ctx_bundle
export ctx_bundle
