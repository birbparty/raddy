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
      NK_BUTTON_MAX.ord == 4
