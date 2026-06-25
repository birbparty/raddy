/*
 * nuklear_impl.c — SOLE translation unit defining NK_IMPLEMENTATION.
 *
 * ODR rule: NK_IMPLEMENTATION MUST appear in EXACTLY ONE .c file.
 * No other .c file and no Nim module may define NK_IMPLEMENTATION.
 *
 * The macro configuration is in nk_config.h; it must be consistent with
 * every other TU that includes nuklear.h (Nim modules use
 *   {.passC: "-include path/to/nk_config.h".}
 * to guarantee this without repeating the #defines).
 *
 * Build integration (raddy.nimble / nim c):
 *   {.compile: "vendor/nuklear_impl.c".}
 * in src/raddy/types.nim (or a dedicated import shim).
 */

#include "nk_config.h"
#define NK_IMPLEMENTATION
#include "nuklear.h"
