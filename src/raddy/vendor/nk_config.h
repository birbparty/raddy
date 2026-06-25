/* nk_config.h — raddy's canonical Nuklear macro configuration.
 *
 * This header MUST be included (via -include or explicit #include) by:
 *   - nuklear_impl.c (before #define NK_IMPLEMENTATION and #include "nuklear.h")
 *   - every Nim module that imports nuklear.h types via {.passC: "-include .../nk_config.h".}
 *
 * Do NOT add any other macro that enables vertex-buffer output, font baking, or the
 * default font — see architecture.md for rationale.
 *
 * Guard against double-inclusion.
 */
#ifndef RADDY_NK_CONFIG_H
#define RADDY_NK_CONFIG_H

/* --- always-on features --------------------------------------------------- */

#define NK_INCLUDE_FIXED_TYPES        /* stdint.h types: nk_uint, nk_int, etc. */
#define NK_INCLUDE_STANDARD_BOOL      /* nk_bool = C99 _Bool (1 byte) — bind to Nim bool */
#define NK_INCLUDE_STANDARD_VARARGS   /* needed by nk_layout_row and friends */

/* NK_INCLUDE_DEFAULT_ALLOCATOR: desktop only (heap-backed nk_init_default).
 * On Vita use nk_init_fixed with a pre-allocated buffer instead.
 * Controlled by the consumer build — define -DNK_VITA or -Dvita to opt out. */
#if !defined(__vita__) && !defined(NK_VITA)
#  define NK_INCLUDE_DEFAULT_ALLOCATOR
#endif

/* --- explicitly NEVER defined --------------------------------------------- */

/* NK_INCLUDE_VERTEX_BUFFER_OUTPUT — would require rlgl / GL buffer upload;
 *   PS Vita backend only exposes high-level draw procs.  Do not add.          */
/* NK_INCLUDE_FONT_BAKING          — pulls in glyph atlas; bloats binary;
 *   raddy uses host raylib Font objects instead.  Do not add.                 */
/* NK_INCLUDE_DEFAULT_FONT         — embedded bitmap font; bloats binary.
 *   Do not add.                                                                */

#endif /* RADDY_NK_CONFIG_H */
