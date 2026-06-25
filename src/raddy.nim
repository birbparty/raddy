## raddy — Nuklear immediate-mode GUI binding for naylib/raylib games.
##
## `import raddy` gives the complete core UI API — context lifecycle, input
## feed, layout, widgets, style, and types. This module is backend-free: it
## contains NO imports of naylib, raylib_console, inputty, or any draw API.
##
## Public core surface:
##   types   — nk_context, nk_bool, nk_color, nk_rect, nk_vec2, nk_flags …
##   errors  — RaddyCmdBufBytes, raddyLog
##   context — raddyCtxInit, raddyCtxFree, raddyCtxClear
##   style   — raddyStyleDefault, raddyStyleColor, nk_color helpers
##   input   — raddyInputBegin/End, raddyInputMotion/Button/Key/Scroll/Unicode
##   layout  — raddyLayoutRow*, raddyGroupBegin/End, raddySpacing, NkWindowFlags
##   widgets — raddyBegin/End, raddyLabel, raddyButton, raddyCheckbox,
##             raddySlider, raddyEdit, raddyCombo, raddyProperty
##
## Backend (rendering + context bundle):
##   import raddy/backend/ctx_bundle   — RaddyCtxBundle lifecycle helper
##   import raddy/backend/render       — raddyRender (Nuklear → raylib draw calls)
##   import raddy/backend/pump_naylib  — optional desktop naylib input pump
##   import raddy/backend/pump_vita    — optional Vita gamepad input pump
##
## Platform: desktop (--mm:orc, naylib) and PS Vita (--mm:arc, raylib_console).
## Build with 'nim c --path:src', NOT 'nimble build' (srcDir flatten pitfall).

import raddy/types
export types

import raddy/errors
export errors

import raddy/context
export context

import raddy/style
export style

import raddy/input
export input

import raddy/layout
export layout

import raddy/widgets
export widgets
