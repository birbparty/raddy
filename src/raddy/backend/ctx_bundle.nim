## ctx_bundle.nim — Long-lived object pinning nk_user_font + nk_context + cmd buffer.
##
## Lifetime contract:
##   - RaddyCtxBundle is a ref object — its heap address is stable for GC lifetime.
##   - fontPtr (ptr RFont) is a RAW POINTER ESCAPE into C (Nuklear stores it in
##     nk_handle.ptr). The caller MUST ensure the RFont at fontPtr outlives the bundle.
##     Safe patterns: store the RFont in a module-level global, or in the same ref
##     object as RaddyCtxBundle (if the consumer's ref object embeds both).
##   - fontPtr MUST be stable — do NOT pass addr of a local variable or a seq element.
##
## What the bundle pins:
##   1. nk_user_font — holds the Nuklear text-measurement callback and the fontPtr raw ptr.
##   2. nk_context   — Nuklear's full context state; the C allocator (desktop) or the
##                     cmd buffer (Vita/raddyFixed) provides backing memory.
##   3. cmdBuf       — Fixed backing buffer for Nuklear on the vita/raddyFixed path.
##                     On the desktop heap path this field does not exist.
##
## Usage (myFont MUST outlive the bundle — module global or long-lived field):
##   var myFont {.global.} = loadFont(...)        ## caller-owned, stable address
##   var bundle = raddyBundleCreate(addr myFont, fontPixelSize = 32.0f)
##   # ... per-frame: raddyBundleCtx(bundle) for nk_context ptr
##   raddyBundleFree(bundle)

import ../types    ## nk_context, nk_user_font, nk_bool, nk_size
import ../context  ## raddyCtxInit, raddyCtxFree, raddyCtxClear, setRaddyFont
import ../errors   ## RaddyCmdBufBytes, raddyLog
import ./raylib_api ## RFont (ptr only — font is caller-owned), raddyFontLoaded
import ./font      ## raddyInitFont, RaddyFont, raddyFontHandle

# ---------------------------------------------------------------------------
# Bundle type
# ---------------------------------------------------------------------------

type RaddyCtxBundle* {.acyclic.} = ref object
  ## Long-lived container. Holds all Nuklear state that must outlive the context.
  ## Create with raddyBundleCreate; free with raddyBundleFree.
  nkFont*:  nk_user_font
  ctx*:     nk_context
  fontOk*:  bool  ## true if raddyInitFont succeeded (fontPtr was non-nil)
  fontLoaded*: bool  ## true if the font baked a glyph atlas (texture.id != 0).
                     ## STRONGER than fontOk: a non-nil font whose TTF failed to
                     ## bake has fontOk==true but fontLoaded==false (no glyphs).
  ctxOk*:   bool  ## true if raddyCtxInit succeeded; false = UI non-functional
  freed:    bool  ## sentinel: raddyBundleFree sets this; guards against double-free
  when defined(vita) or defined(raddyFixed):
    ## NOTE: embeds RaddyCmdBufBytes (default 64 KiB) inline per bundle heap block.
    ## Create one bundle per context, not one per frame.
    cmdBuf*: array[RaddyCmdBufBytes, byte]

# ---------------------------------------------------------------------------
# Initialise
# ---------------------------------------------------------------------------

proc raddyBundleCreate*(fontPtr: ptr RFont; fontPixelSize: float32): RaddyCtxBundle
    {.raises: [].} =
  ## Create a bundle and initialise the Nuklear context.
  ##
  ## fontPtr: stable address of a caller-owned RFont. MUST outlive the bundle.
  ## fontPixelSize: pixel height the font was loaded at (e.g., font.baseSize).
  ##
  ## Returns a valid bundle even on failure (check bundle.fontOk for font status).
  ## The returned bundle is a Nim ref — it is pinned on the GC heap and its
  ## interior addresses (nkFont, ctx, cmdBuf) are stable for the bundle's lifetime.
  let bundle = RaddyCtxBundle()

  bundle.fontOk = fontPtr != nil
  if not bundle.fontOk:
    raddyLog("raddyBundleCreate: fontPtr is nil — text will not render")

  # Stronger, additive signal: a non-nil font can still have failed to bake its
  # glyph atlas (texture.id == 0), in which case text silently will not render.
  # fontOk keeps its exact semantic (fontPtr != nil); fontLoaded adds the bake check.
  bundle.fontLoaded = raddyFontLoaded(fontPtr)
  if bundle.fontOk and not bundle.fontLoaded:
    raddyLog("raddyBundleCreate: font texture.id == 0 — TTF failed to bake, text will not render")

  # Always call raddyInitFont even when fontPtr is nil: it wires up the width
  # callback (raddyMeasureWidth) which self-guards against a nil font ptr.
  # Skipping the call entirely would leave nkFont.width==nil, causing a null
  # function-pointer crash when Nuklear calls style.font->width during layout.
  raddyInitFont(bundle.nkFont, fontPtr, fontPixelSize)

  when defined(vita) or defined(raddyFixed):
    let ok = raddyCtxInit(addr bundle.ctx, addr bundle.nkFont,
                          addr bundle.cmdBuf[0], nk_size(RaddyCmdBufBytes))
  else:
    let ok = raddyCtxInit(addr bundle.ctx, addr bundle.nkFont)

  bundle.ctxOk = ok
  if not ok:
    raddyLog("raddyBundleCreate: context init failed — UI will be non-functional")

  bundle

# ---------------------------------------------------------------------------
# Per-frame helpers
# ---------------------------------------------------------------------------

proc raddyBundleCtx*(bundle: RaddyCtxBundle): ptr nk_context {.inline, raises: [].} =
  ## Return a pointer to the bundle's nk_context for use in Nuklear API calls.
  ## The pointer is stable for the bundle's lifetime.
  ## Do NOT retain this pointer across raddyBundleFree or past the last live ref to bundle.
  addr bundle.ctx

proc raddyBundleClear*(bundle: RaddyCtxBundle; bufOverflow: var bool) {.inline, raises: [].} =
  ## Call at the end of each frame after the command queue has been consumed.
  ## Delegates to raddyCtxClear which checks for command-buffer overflow on vita/raddyFixed.
  raddyCtxClear(addr bundle.ctx, bufOverflow)

proc raddyBundleSetFont*(bundle: RaddyCtxBundle; font: var RaddyFont) {.inline, raises: [].} =
  ## Switch the bundle's ACTIVE Nuklear font to a caller-owned RaddyFont.
  ##
  ## Thin, additive wrapper over setRaddyFont(addr bundle.ctx, raddyFontHandle(font)).
  ## The bundle's inline nkFont stays the default/initial font wired at
  ## raddyBundleCreate; this does NOT replace it or store `font` in the bundle.
  ## Forward-only, exactly like setRaddyFont: it affects only widgets emitted AFTER
  ## the call. It is written to the GLOBAL ctx.style.font, so it also carries to
  ## later windows in the same frame and persists across frames until the next
  ## switch (nk_clear does not reset ctx.style.font).
  ##
  ## LIFETIME: `font` is taken as `var RaddyFont` — NOT by value — on purpose.
  ## raddyFontHandle returns `addr font.nkFont`, which Nuklear stores and then
  ## dereferences every frame text is laid out until the next switch. Taking the
  ## address of a by-value parameter copy would dangle the instant this proc
  ## returns. The caller must therefore hold `font` at a STABLE address (a global
  ## or long-lived field) for as long as it stays active — the RaddyFont lifetime
  ## contract in font.nim. Multi-size UIs keep one RaddyFont per size and switch
  ## between them with this helper.
  ##
  ## A nil bundle is ignored (no context to switch); setRaddyFont additionally
  ## guards a nil ctx/font internally.
  if bundle == nil: return
  setRaddyFont(addr bundle.ctx, raddyFontHandle(font))

# ---------------------------------------------------------------------------
# Teardown
# ---------------------------------------------------------------------------

proc raddyBundleFree*(bundle: RaddyCtxBundle) {.raises: [].} =
  ## Release Nuklear context state. Does NOT unload the font (caller-owned).
  ## Safe to call with nil bundle. Idempotent — safe to call more than once.
  if bundle == nil or bundle.freed: return
  bundle.freed = true
  raddyCtxFree(addr bundle.ctx)
