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
 * Build integration: src/raddy/vendor.nim sets
 *   {.compile: currentSourcePath().parentDir() / "vendor" / "nuklear_impl.c".}
 * so any module importing vendor.nim (directly or transitively) triggers compilation.
 */

/* Explicit #include so standalone gcc syntax-checks work without -include.
 * When built via vendor.nim the same header also arrives via -include; the
 * include-guard (RADDY_NK_CONFIG_H) makes this a safe no-op in that case. */
#include "nk_config.h"
#define NK_IMPLEMENTATION
#include "nuklear.h"
