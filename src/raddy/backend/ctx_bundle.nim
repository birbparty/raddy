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
## Usage:
##   var bundle = raddyBundleCreate(addr myFont, fontPixelSize = 32.0f)
##   # ... per-frame: raddyBundleCtx(bundle) for nk_context ptr
##   raddyBundleFree(bundle)

import ../types    ## nk_context, nk_user_font, nk_bool, nk_size
import ../context  ## raddyCtxInit, raddyCtxFree, raddyCtxClear
import ../errors   ## RaddyCmdBufBytes, raddyLog
import ./raylib_api ## RFont (ptr only — font is caller-owned)
import ./font      ## raddyInitFont

# ---------------------------------------------------------------------------
# Bundle type
# ---------------------------------------------------------------------------

type RaddyCtxBundle* = ref object
  ## Long-lived container. Holds all Nuklear state that must outlive the context.
  ## Create with raddyBundleCreate; free with raddyBundleFree.
  nkFont*:  nk_user_font
  ctx*:     nk_context
  fontOk*:  bool  ## true if raddyInitFont succeeded (fontPtr was non-nil)
  when defined(vita) or defined(raddyFixed):
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

  raddyInitFont(bundle.nkFont, fontPtr, fontPixelSize)

  when defined(vita) or defined(raddyFixed):
    let ok = raddyCtxInit(addr bundle.ctx, addr bundle.nkFont,
                          addr bundle.cmdBuf[0], nk_size(RaddyCmdBufBytes))
  else:
    let ok = raddyCtxInit(addr bundle.ctx, addr bundle.nkFont)

  if not ok:
    raddyLog("raddyBundleCreate: context init failed — UI will be non-functional")

  bundle

# ---------------------------------------------------------------------------
# Per-frame helpers
# ---------------------------------------------------------------------------

proc raddyBundleCtx*(bundle: RaddyCtxBundle): ptr nk_context {.inline, raises: [].} =
  ## Return a pointer to the bundle's nk_context for use in Nuklear API calls.
  ## The pointer is stable for the bundle's lifetime.
  addr bundle.ctx

proc raddyBundleClear*(bundle: RaddyCtxBundle; bufOverflow: var bool) {.inline, raises: [].} =
  ## Call at the end of each frame after the command queue has been consumed.
  ## Delegates to raddyCtxClear which checks for command-buffer overflow on vita/raddyFixed.
  raddyCtxClear(addr bundle.ctx, bufOverflow)

# ---------------------------------------------------------------------------
# Teardown
# ---------------------------------------------------------------------------

proc raddyBundleFree*(bundle: RaddyCtxBundle) {.raises: [].} =
  ## Release Nuklear context state. Does NOT unload the font (caller-owned).
  ## Safe to call with nil bundle.
  if bundle == nil: return
  raddyCtxFree(addr bundle.ctx)
