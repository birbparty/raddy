## Smoke spec: raddy entry point compiles and is importable.
## Grows as submodules are added.

import bddy
import raddy
{.warning[UnusedImport]: off.}

spec "raddy entry point":
  it "compiles and is importable":
    verify:
      true  # compilation reaching this line is the test; expand as submodules land
