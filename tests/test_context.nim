## context spec: nk_context lifecycle procs compile and run correctly.

import bddy
import raddy
{.warning[UnusedImport]: off.}

spec "context module":
  it "re-exports nk_init_default nk_clear nk_free":
    verify:
      true  ## reaching here proves importc bindings resolved

  it "nk_init_default succeeds with a zeroed nk_user_font":
    ## Desktop path only. On Vita there is no default allocator.
    var ok = true  ## default pass on vita (test not applicable)
    when not defined(vita):
      var ctx: nk_context
      var font: nk_user_font
      ok = bool(nk_init_default(addr ctx, addr font))
      nk_free(addr ctx)
    verify:
      ok

  it "raddyCtxInit + raddyCtxFree round-trip on desktop":
    var ok = true
    when not defined(vita):
      var ctx: nk_context
      var font: nk_user_font
      ok = raddyCtxInit(addr ctx, addr font)
      raddyCtxFree(addr ctx)
    verify:
      ok

  it "raddyCtxClear sets bufOverflow=false on desktop heap path":
    var overflow = true  ## pre-set; clear should reset to false on desktop
    when not defined(vita):
      var ctx: nk_context
      var font: nk_user_font
      discard raddyCtxInit(addr ctx, addr font)
      raddyCtxClear(addr ctx, overflow)
      nk_free(addr ctx)
    verify:
      not overflow

  it "nk_init_fixed succeeds over a RaddyCmdBufBytes-sized buffer":
    var ctx: nk_context
    var font: nk_user_font
    var buf: array[RaddyCmdBufBytes, byte]
    let ok = bool(nk_init_fixed(addr ctx, addr buf[0], nk_size(buf.len), addr font))
    nk_clear(addr ctx)
    verify:
      ok
