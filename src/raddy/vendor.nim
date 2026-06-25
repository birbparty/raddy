## vendor.nim — compile nuklear_impl.c as the sole NK_IMPLEMENTATION translation unit.
## Every Nim module that needs Nuklear types imports this (directly or transitively).
## nk_config.h is injected via -include so the macro set stays consistent.

import std/os

const vendorDir = currentSourcePath().parentDir() / "vendor"

{.passC: "-include \"" & vendorDir & "/nk_config.h\"".}
{.compile: vendorDir & "/nuklear_impl.c".}
