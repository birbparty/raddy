# Per-Frame Call Order and RenderTexture Coordinate Contract

This file is the authoritative reference for how consumers wire raddy into their render loop. Incorrect ordering causes invisible widgets, stale input, or scissor artifacts. Agents generating integration code MUST follow this document exactly.

## Canonical Per-Frame Order

Applies to both desktop and Vita:

```
1. nk_input_begin(ctx)
2.   [feed input: nkInputMotion / nkInputButton / nkInputKey / nkInputScroll / nkInputUnicode]
3.   [OR: pumpNaylibInput(ctx) on desktop / pumpVitaInput(ctx, raddyCtx, dt) on Vita]
4. nk_input_end(ctx)
5. [build UI: nk_begin() / widgets / nk_end() — may call multiple panels]
6. raddyRender(ctx, raddyCtx)   <- drains command queue via nk__begin/nk__next
7. nk_clear(ctx)                <- MUST come AFTER render, BEFORE next input_begin
```

## Critical Ordering Rules

**`nk_clear` AFTER render, not before.** Calling `nk_clear` before `raddyRender` empties the command queue. Nothing renders.

**`nk_input_begin` BEFORE any widget calls.** Nuklear's input state is only valid between `nk_input_begin` / `nk_input_end`. Widget behavior is undefined outside this boundary.

**`raddyRender` BEFORE `nk_clear`.** These two are always paired in this order, end of frame, without exception.

**Do NOT call `nk_begin` outside of `nk_input_end` / `nk_input_begin` boundaries** on the next frame. Widget state depends on the input snapshot captured between those calls.

## topdown Integration (320x180 RenderTexture)

topdown renders into a low-resolution RenderTexture2D and composites it onto the screen. Raddy draws into this texture before compositing.

```nim
# topdown drawOverlay signature (consumer's code):
proc drawOverlay(rt: RenderTexture2D) =
  BeginTextureMode(rt)           # rt is 320x180
  ClearBackground(BLANK)

  # --- raddy frame ---
  nk_input_begin(addr ctx.nk)
  pumpVitaInput(addr ctx.nk, ctx.raddy, dt)  # or pumpNaylibInput on desktop
  nk_input_end(addr ctx.nk)

  if nk_begin(addr ctx.nk, "overlay", nk_rect(10, 10, 200, 150), NK_WINDOW_BORDER):
    # widgets...
    discard
  nk_end(addr ctx.nk)

  raddyRender(addr ctx.nk, ctx.raddy, framebufH = 180)  # renders into 320x180 texture
  nk_clear(addr ctx.nk)

  EndTextureMode()
  # consumer then DrawTexturePro(rt.texture, ...) to composite onto screen
```

## Scissor Y-Flip in topdown

Framebuffer height H = 180 for topdown's RenderTexture.

Nuklear emits `NK_COMMAND_SCISSOR` with Y in Nuklear's top-left coordinate system. Inside `BeginTextureMode`, the OpenGL framebuffer is Y-flipped (origin at bottom-left).

**Correct mapping:**
```nim
BeginScissorMode(cmd.x, H - cmd.y - cmd.h, cmd.w, cmd.h)
```
where `H` is the RenderTexture height (180).

`raddyRender` receives the RenderTexture height as a parameter:
```nim
proc raddyRender*(ctx: ptr nk_context; raddyCtx: RaddyCtx; framebufH: int32 = 0)
```

- When `framebufH > 0`: apply Y-flip using the formula above.
- When `framebufH == 0` (clckr native-resolution case): use `cmd.y` directly, no flip.

## clckr Integration (Native Resolution, Post-endMode2D)

clckr renders in screen space after the 2D game world pass. No RenderTexture is involved.

```nim
# clckr's screen-space pass (after game world rendering):
endMode2D()

# --- raddy frame (screen-space, no RenderTexture) ---
nk_input_begin(addr ctx.nk)
pumpNaylibInput(addr ctx.nk)
nk_input_end(addr ctx.nk)

if nk_begin(addr ctx.nk, "hud", nk_rect(10, 10, 300, 200), NK_WINDOW_BORDER):
  discard
nk_end(addr ctx.nk)

raddyRender(addr ctx.nk, ctx.raddy)  # framebufH=0: no Y-flip needed
nk_clear(addr ctx.nk)

endDrawing()
```

## Scissor in clckr

No Y-flip. Use the scissor rectangle directly:

```nim
BeginScissorMode(cmd.x, cmd.y, cmd.w, cmd.h)
```

`raddyRender` detects `framebufH == 0` and uses this straight mapping.

## NK_COMMAND_SCISSOR Semantics (Both Targets)

**Replace, not nest.** Each `NK_COMMAND_SCISSOR` replaces the active scissor. Nuklear does not push/pop scissor state — each command is absolute.

**End-of-queue cleanup.** At the end of the command queue, call `EndScissorMode()` unconditionally — but ONLY if a scissor was opened this frame. `raddyRender` tracks a `scissorActive: bool` flag internally.

**Empty UI guard.** If NO `NK_COMMAND_SCISSOR` was emitted in the frame (empty UI, all panels closed, or all NOP), do NOT call `EndScissorMode`. Closing a scissor that was never opened is undefined behavior in raylib/OpenGL.

Internal tracking pattern:
```nim
var scissorActive = false
# ... iterate commands ...
# on NK_COMMAND_SCISSOR:
#   if scissorActive: EndScissorMode()
#   BeginScissorMode(...)
#   scissorActive = true
# after loop:
if scissorActive:
  EndScissorMode()
```

## Context Init Order

The `nk_user_font` MUST be installed BEFORE the first `nk_begin` call. `nk_init_*` takes the font pointer and the context is invalid until init completes.

Correct order:

```
1. loadFont(...)            -> pin Font in a long-lived object (do NOT let it go out of scope)
2. initialize nk_user_font  -> set .height and .width callback pointing at the pinned font
3. nk_init_default(ctx, allocator, addr nkFont)
   -- OR --
   nk_init_fixed(ctx, buf, bufLen, addr nkFont)   # Vita / -d:raddyFixed path
4. nk_begin / widgets / raddyRender / nk_clear loop begins here
```

Any `nk_begin` call before `nk_init_*` is a crash — the context is uninitialized and the font pointer is null.

Agents writing init code MUST verify this order against `font-contract.md`, which defines the `nk_user_font` width callback contract and font lifetime requirements.
