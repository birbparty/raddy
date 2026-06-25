## context spec: nk_context lifecycle procs compile and run correctly.

import bddy
import raddy
{.warning[UnusedImport]: off.}

spec "context module":
  it "re-exports nk_init_fixed nk_clear nk_free":
    verify:
      true  ## reaching here proves importc bindings resolved

  it "nk_init_fixed succeeds over a RaddyCmdBufBytes-sized buffer":
    ## buf must outlive ctx — both are on the stack here so lifetimes match.
    ## Zeroed font: width callback is nil, but it's only invoked during text layout.
    ## This test never renders text, so the nil callback is not triggered.
    var ctx: nk_context
    var font: nk_user_font
    var buf: array[RaddyCmdBufBytes, byte]
    let ok = bool(nk_init_fixed(addr ctx, addr buf[0], nk_size(buf.len), addr font))
    nk_clear(addr ctx)
    verify:
      ok

  it "raddyCtxInit round-trip passes a buffer on fixed paths":
    ## Works on desktop, -d:raddyFixed, and vita — always provides a buffer.
    ## On desktop (non-fixed), buf/bufLen are silently ignored by raddyCtxInit.
    var ctx: nk_context
    var font: nk_user_font
    var buf: array[RaddyCmdBufBytes, byte]
    let ok = raddyCtxInit(addr ctx, addr font, addr buf[0], nk_size(buf.len))
    raddyCtxFree(addr ctx)
    verify:
      ok

  it "raddyCtxClear sets bufOverflow=false when no commands pushed":
    var ctx: nk_context
    var font: nk_user_font
    var buf: array[RaddyCmdBufBytes, byte]
    discard raddyCtxInit(addr ctx, addr font, addr buf[0], nk_size(buf.len))
    var overflow = true  ## pre-set; should be reset to false (no commands → no overflow)
    raddyCtxClear(addr ctx, overflow)
    raddyCtxFree(addr ctx)
    verify:
      not overflow

  it "nk_buffer.needed field binding is accessible (overflow predicate regression)":
    ## Verifies that ctx.memory.needed is accessible via the types.nim partial binding.
    ## The correct overflow predicate is `needed > size` (not `allocated >= size`):
    ## nk_buffer_alloc increments `needed` BEFORE the full check, then returns 0
    ## without advancing `allocated` on overflow. So allocated < size even when
    ## commands were dropped; needed > size is the signal.
    ## This test confirms the field resolves and starts at 0 after init.
    var ctx: nk_context
    var font: nk_user_font
    var buf: array[RaddyCmdBufBytes, byte]
    discard nk_init_fixed(addr ctx, addr buf[0], nk_size(buf.len), addr font)
    let neededAtInit = ctx.memory.needed  ## should be 0: no commands pushed yet
    nk_clear(addr ctx)
    verify:
      neededAtInit == nk_size(0)

  when not defined(vita):
    it "nk_init_default succeeds with a zeroed nk_user_font (desktop only)":
      var ctx: nk_context
      var font: nk_user_font
      let ok = bool(nk_init_default(addr ctx, addr font))
      nk_free(addr ctx)
      verify:
        ok
