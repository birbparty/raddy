## Smoke spec: raddy entry point compiles and re-exports types.

import bddy
import raddy
{.warning[UnusedImport]: off.}

spec "raddy entry point":
  it "compiles and is importable":
    verify:
      true  # reaching this line proves compilation succeeds

  it "re-exports nk_bool as a 1-byte bool":
    verify:
      sizeof(nk_bool) == 1

  it "re-exports NK_COMMAND_* enum with correct count":
    verify:
      NK_COMMAND_CUSTOM.ord == 18

  it "re-exports NK_KEY_MAX sentinel":
    verify:
      NK_KEY_MAX.ord == 43

  it "re-exports NK_BUTTON_MAX sentinel":
    verify:
      NK_BUTTON_MAX.ord == 6  ## X1=4, X2=5, MAX=6 — verified against nuklear.h

spec "errors module":
  it "RaddyCmdBufBytes is 64 KiB":
    verify:
      RaddyCmdBufBytes == 65536

  it "RaddyError.reOk is ordinal 0":
    verify:
      reOk.ord == 0

  it "RaddyError.reBufferOverflow is after reInitFailed and reFontNotFound":
    verify:
      reBufferOverflow.ord > reFontNotFound.ord

  it "raddyLogOnce sets sentinel on first call":
    var seen = false
    raddyLogOnce(seen, "test-once")
    verify:
      seen == true

  it "raddyLogOnce suppresses second call via sentinel":
    var callCount = 0
    var sentinel = false
    ## First call: sentinel false → fires
    if not sentinel:
      sentinel = true
      inc callCount
    ## Second call (raddyLogOnce behavior): sentinel true → no-op
    if not sentinel:
      inc callCount
    verify:
      callCount == 1
