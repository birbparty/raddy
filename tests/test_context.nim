## context spec: nk_context lifecycle procs compile and run correctly.

import bddy
import raddy
{.warning[UnusedImport]: off.}

spec "context module":
  it "re-exports nk_init_fixed nk_clear nk_free":
    verify:
      true  ## reaching here proves importc bindings resolved

  it "re-exports setRaddyFont + nk_style_set_font (font switch binding)":
    ## Compile-time proof the core font-switch wrapper is reachable as
    ## raddy.setRaddyFont (auto re-exported via `export context`). The VALUE of
    ## this test is the typed proc binding below: it pins setRaddyFont's signature
    ## at compile time. The runtime `not f.isNil` is incidental — do not
    ## "strengthen" it away, the symbol resolution is what is being asserted.
    let f: proc(ctx: ptr nk_context; font: ptr nk_user_font) {.raises: [].} =
      setRaddyFont
    verify:
      not f.isNil

  it "setRaddyFont switches the active font mid-frame without crashing":
    ## Exercises the wrapper over a live fixed context: a mid-frame switch from
    ## font1 to font2 is forward-only and must not crash (nk_style_set_font sets
    ## ctx.style.font directly and resets the current layout's min row height).
    ## ctx.style is not exposed by the partial nk_context binding, so this asserts
    ## runtime safety (no crash, guards hold) rather than the field value.
    ##
    ## The zeroed nk_user_font values are safe here ONLY because no text is laid
    ## out before nk_clear — a zeroed font has a nil `width` callback that nuklear
    ## would dereference during text measurement. Do not add text widgets to this
    ## test without supplying a real width callback.
    var ctx: nk_context
    var font1, font2: nk_user_font
    var buf: array[RaddyCmdBufBytes, byte]
    discard nk_init_fixed(addr ctx, addr buf[0], nk_size(buf.len), addr font1)
    setRaddyFont(addr ctx, addr font2)  ## switch to a second font
    setRaddyFont(addr ctx, nil)         ## nil font: guard makes it a true no-op
    setRaddyFont(nil, addr font2)       ## nil ctx: wrapper guard returns early
    nk_clear(addr ctx)
    verify:
      true  ## reaching here proves the switch path is crash-free

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
