# raddy API Overview

## Core modules

All core modules are re-exported by `import raddy`. No backend imports are required to use the full UI API.

| Module | Description |
|---|---|
| `raddy/types` | Fundamental Nuklear types: `nk_context`, `nk_bool`, `nk_color`, `nk_rect`, `nk_vec2`, `nk_flags`, `nk_user_font`, `nk_handle`, `nk_size`, `RaddyCmdBufBytes`. |
| `raddy/errors` | Error reporting. Defines `RaddyCmdBufBytes` (64 KiB fixed buffer size constant) and `raddyLog` for structured diagnostic output. |
| `raddy/context` | Context lifecycle: `raddyCtxInit`, `raddyCtxFree`, `raddyCtxClear`. Wraps `nk_init_default` (heap) or `nk_init_fixed` (fixed, when `-d:raddyFixed` or `-d:vita`). |
| `raddy/style` | Theme management: `raddyStyleDefault`, `raddyStyleFromTable`, `raddyColorName`. |
| `raddy/input` | Input event feed: `raddyInputBegin`/`End`, `raddyInputMotion`, `raddyInputButton`, `raddyInputKey`, `raddyInputScroll`, `raddyInputUnicode`. Must bracket all input calls each frame. |
| `raddy/layout` | Row layout and grouping: `raddyLayoutRowDynamic`/`Static`/`Begin`/`Push`/`End`, `NkWindowFlags`, `raddyGroupBegin`/`End`, `raddySpacing`. |
| `raddy/widgets` | Widget procs: `raddyBegin`/`End`, `raddyLabel`, `raddyButton`, `raddyCheckbox`, `raddySlider`, `raddyEdit`, `raddyCombo`, `raddyProperty`. |

## Backend modules

Backend modules must be imported explicitly by the application. They are never pulled in by `import raddy`.

| Module | Description |
|---|---|
| `raddy/backend/ctx_bundle` | `RaddyCtxBundle` lifecycle helper. Wraps context creation, font pinning, and teardown in a single object. `raddyBundleCreate(fontPtr, fontPx)` stores a raw `ptr RFont` in Nuklear's user handle. |
| `raddy/backend/render` | `raddyRender(ctx, screenHeight, overflow)` — iterates Nuklear's command queue with `nk__begin`/`nk__next` and dispatches each `NK_COMMAND_*` to the corresponding raylib draw call. See [../command-coverage.md](../command-coverage.md) for the full dispatch matrix. |
| `raddy/backend/pump_naylib` | Optional desktop input pump. `raddyNaylibPump(ctx)` reads mouse, keyboard, and scroll state from naylib and feeds it to Nuklear's input pipeline. Import only on desktop builds. |
| `raddy/backend/pump_vita` | Optional PS Vita gamepad input pump. Reads DualShock 4 / Vita controller state and maps buttons to Nuklear input events. Import only on Vita builds. |

## Decoupled-core rule

`import raddy` is backend-free. It compiles with zero naylib or raylib_console symbols in scope. This is not a convention — it is enforced by `tests/test_import_purity.nim`, which confirms that a bare `import raddy` produces no naylib/raylib link symbols.

Backend modules are always imported explicitly by the application or platform entry point. This makes the core usable on Vita without any desktop rendering headers present on the compile path.

## Frame loop pattern

The correct order of operations each frame:

```
# 1. Begin input phase
raddyInputBegin(ctx)

# 2. Feed all input events for this frame
raddyInputMotion(ctx, mouseX, mouseY)
raddyInputButton(ctx, NK_BUTTON_LEFT, mouseX, mouseY, pressed)
# ... other input events ...

# 3. End input phase (Nuklear latches the snapshot)
raddyInputEnd(ctx)

# 4. Build UI — call raddyBegin/widget/raddyEnd trees
buildUI(ctx)

# 5. Render — translate command queue to draw calls
raddyRender(ctx, screenHeight, overflow)

# 6. Clear context state for next frame
raddyCtxClear(ctx)

# 7. Present to screen
# (swap buffers / end drawing / blit render texture)
```

`raddyNaylibPump` (desktop) wraps steps 1-3 in a single call by reading naylib's current input state. On Vita, `pump_vita` does the same for gamepad state. Either way, steps 4-7 are identical across platforms.
