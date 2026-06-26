## types.nim — Nuklear C type bindings for raddy.
##
## Importing this module (directly or via raddy.nim) has a side effect:
## vendor.nim is pulled in, which triggers {.compile.} for nuklear_impl.c and
## {.passC: "-include nk_config.h".} so every translation unit gets the same
## NK_* macro set. No Nim consumer needs to repeat those pragmas.
##
## Decoupled-core rule: this module MUST NOT import naylib, raylib_console,
## inputty, or any game-specific module. Types only.

import ./vendor  ## side-effect: compile nuklear_impl.c; inject nk_config.h

# ---------------------------------------------------------------------------
# Header shorthand
# ---------------------------------------------------------------------------

const nkH = "nuklear.h"

# ---------------------------------------------------------------------------
# nk_bool — C99 bool via NK_INCLUDE_STANDARD_BOOL (1 byte, not cint)
# ---------------------------------------------------------------------------

type nk_bool* {.importc: "nk_bool", header: nkH.} = bool

static:
  doAssert sizeof(nk_bool) == 1,
    "nk_bool must be 1 byte (C99 bool). Verify NK_INCLUDE_STANDARD_BOOL is set in nk_config.h."

# ---------------------------------------------------------------------------
# Primitive typedefs
# ---------------------------------------------------------------------------

type
  nk_byte*   {.importc: "nk_byte",   header: nkH.} = uint8
  nk_short*  {.importc: "nk_short",  header: nkH.} = int16
  nk_ushort* {.importc: "nk_ushort", header: nkH.} = uint16
  nk_int*    {.importc: "nk_int",    header: nkH.} = int32
  nk_uint*   {.importc: "nk_uint",   header: nkH.} = uint32
  nk_size*   {.importc: "nk_size",   header: nkH.} = uint   ## uintptr_t
  nk_flags*  {.importc: "nk_flags",  header: nkH.} = uint32
  nk_rune*   {.importc: "nk_rune",   header: nkH.} = uint32
  nk_hash*   {.importc: "nk_hash",   header: nkH.} = uint32

# ---------------------------------------------------------------------------
# nk_handle — union { void *ptr; int id; }
# ---------------------------------------------------------------------------

type nk_handle* {.importc: "nk_handle", header: nkH, union.} = object
  `ptr`* {.importc: "ptr".}: pointer
  id*: cint

# ---------------------------------------------------------------------------
# Core geometric / color value types
# ---------------------------------------------------------------------------

type
  nk_color* {.importc: "struct nk_color", header: nkH.} = object
    r*, g*, b*, a*: nk_byte

  nk_vec2* {.importc: "struct nk_vec2", header: nkH.} = object
    x*, y*: float32

  nk_vec2i* {.importc: "struct nk_vec2i", header: nkH.} = object
    x*, y*: nk_short

  nk_rect* {.importc: "struct nk_rect", header: nkH.} = object
    x*, y*, w*, h*: float32

  nk_image* {.importc: "struct nk_image", header: nkH.} = object
    handle*: nk_handle
    w*, h*:  nk_ushort
    region*: array[4, nk_ushort]

# ---------------------------------------------------------------------------
# Font types
# ---------------------------------------------------------------------------

type
  ## C `const char*`. Distinct codegen from Nim's `cstring` (which emits a
  ## non-const `char*`): the importc spelling makes width-callback function
  ## pointers match Nuklear's nk_text_width_f typedef
  ## (`float(*)(nk_handle, float, const char*, int)`, nuklear.h) at the C level,
  ## so no `-Wno-error=incompatible-function-pointer-types` flag is needed (and
  ## downstream consumers who C-compile src/ under Apple clang build clean too).
  ## Aliased to `cstring`, so Nim-level use (nil-check, copyMem) is unchanged.
  ## Intended for the const-char callback PARAMETER position only — the importc
  ## spelling substitutes textually, so derived forms (e.g. `ptr cstringConst`,
  ## arrays) would emit surprising types; use a purpose-built type for those.
  cstringConst* {.importc: "const char*", nodecl.} = cstring

  ## Width callback: (userdata, font_height, text_ptr, text_byte_len) -> pixel width
  nk_text_width_f* =
    proc(handle: nk_handle; h: float32; text: cstringConst; len: cint): float32 {.cdecl.}

  nk_user_font* {.importc: "struct nk_user_font", header: nkH.} = object
    userdata*: nk_handle       ## opaque handle forwarded to `width`
    height*:   float32         ## max font height in pixels (same for every glyph)
    width*:    nk_text_width_f ## measure text width; must match DrawTextEx spacing

# ---------------------------------------------------------------------------
# Clipboard types — used by text-edit widget clipboard hooks
# ---------------------------------------------------------------------------

type
  ## Opaque Nuklear text-edit state. Passed by pointer to nk_plugin_paste handlers
  ## and to nk_textedit_paste. Do not construct or sizeof from Nim.
  nk_text_edit* {.importc: "struct nk_text_edit", header: nkH.} = object

  ## Called by Nuklear when the user presses Ctrl+C/X over a text selection.
  ## `text` points to the selected UTF-8 bytes (NOT null-terminated); `len` is
  ## the byte count. The handler must null-terminate before passing to the OS.
  nk_plugin_copy* = proc(handle: nk_handle; text: cstring; len: cint) {.cdecl.}

  ## Called by Nuklear when the user presses Ctrl+V in a text-edit field.
  ## The handler fetches text from the OS clipboard and inserts it via
  ## nk_textedit_paste (binding in pump_naylib.nim).
  nk_plugin_paste* = proc(handle: nk_handle; edit: ptr nk_text_edit) {.cdecl.}

  nk_clipboard* {.importc: "struct nk_clipboard", header: nkH.} = object
    userdata*: nk_handle       ## forwarded to copy/paste handlers
    paste*:    nk_plugin_paste ## nil = Ctrl+V is a no-op
    copy*:     nk_plugin_copy  ## nil = Ctrl+C/X is a no-op

# ---------------------------------------------------------------------------
# Buffer and context — expose only fields required by the overflow check
# ---------------------------------------------------------------------------

type
  ## nk_buffer: PARTIAL VIEW — allocated/needed/size exposed for overflow detection.
  ## Overflow check: ctx.memory.needed > ctx.memory.size (NOT allocated >= size).
  ## Why: on NK_BUFFER_FIXED, nk_buffer_alloc advances `needed` BEFORE the full check
  ## then returns 0 without advancing `allocated`. So allocated stays below size even
  ## when commands were dropped; needed exceeds size.
  ## Do NOT sizeof, construct-by-value, or copyMem this type from Nim;
  ## sizeof is deferred to C (correct 120-byte struct via nuklear.h).
  nk_buffer* {.importc: "struct nk_buffer", header: nkH.} = object
    allocated*: nk_size  ## bytes successfully committed this frame
    needed*:    nk_size  ## bytes requested (including dropped on overflow)
    size*:      nk_size  ## total capacity

  ## nk_input: opaque; passed by pointer to nk_input_* procs only.
  nk_input* {.importc: "struct nk_input", header: nkH.} = object

  ## nk_context: PARTIAL VIEW — input and memory fields only.
  ## nk_style sits between input and memory in C but is not declared here;
  ## field access is by name in generated C (correct), not by Nim-computed offset.
  ## sizeof is deferred to C (correct full 18456-byte struct via nuklear.h).
  nk_context* {.importc: "struct nk_context", header: nkH.} = object
    input*:  nk_input     ## keyboard + mouse snapshot (fed inside begin/end boundary)
    memory*: nk_buffer    ## command buffer — check .allocated vs .size after UI build
    clip*:   nk_clipboard ## text-edit clipboard; wire via raddyWireClipboard (desktop)

# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

type
  NkCommandType* {.importc: "enum nk_command_type", header: nkH,
                   size: sizeof(cint).} = enum
    NK_COMMAND_NOP             = 0
    NK_COMMAND_SCISSOR         = 1
    NK_COMMAND_LINE            = 2
    NK_COMMAND_CURVE           = 3
    NK_COMMAND_RECT            = 4
    NK_COMMAND_RECT_FILLED     = 5
    NK_COMMAND_RECT_MULTI_COLOR = 6
    NK_COMMAND_CIRCLE          = 7
    NK_COMMAND_CIRCLE_FILLED   = 8
    NK_COMMAND_ARC             = 9
    NK_COMMAND_ARC_FILLED      = 10
    NK_COMMAND_TRIANGLE        = 11
    NK_COMMAND_TRIANGLE_FILLED = 12
    NK_COMMAND_POLYGON         = 13
    NK_COMMAND_POLYGON_FILLED  = 14
    NK_COMMAND_POLYLINE        = 15
    NK_COMMAND_TEXT            = 16
    NK_COMMAND_IMAGE           = 17
    NK_COMMAND_CUSTOM          = 18

  NkButtons* {.importc: "enum nk_buttons", header: nkH,
               size: sizeof(cint).} = enum
    NK_BUTTON_LEFT   = 0
    NK_BUTTON_MIDDLE = 1
    NK_BUTTON_RIGHT  = 2
    NK_BUTTON_DOUBLE = 3  ## double-click of the left mouse button
    NK_BUTTON_X1     = 4  ## "Back" (mouse button 4)
    NK_BUTTON_X2     = 5  ## "Forward" (mouse button 5)
    NK_BUTTON_MAX    = 6

  NkKeys* {.importc: "enum nk_keys", header: nkH,
            size: sizeof(cint).} = enum
    NK_KEY_NONE              = 0
    NK_KEY_SHIFT             = 1
    NK_KEY_CTRL              = 2
    NK_KEY_DEL               = 3
    NK_KEY_ENTER             = 4
    NK_KEY_TAB               = 5
    NK_KEY_BACKSPACE         = 6
    NK_KEY_COPY              = 7
    NK_KEY_CUT               = 8
    NK_KEY_PASTE             = 9
    NK_KEY_UP                = 10
    NK_KEY_DOWN              = 11
    NK_KEY_LEFT              = 12
    NK_KEY_RIGHT             = 13
    NK_KEY_TEXT_INSERT_MODE  = 14
    NK_KEY_TEXT_REPLACE_MODE = 15
    NK_KEY_TEXT_RESET_MODE   = 16
    NK_KEY_TEXT_LINE_START   = 17
    NK_KEY_TEXT_LINE_END     = 18
    NK_KEY_TEXT_START        = 19
    NK_KEY_TEXT_END          = 20
    NK_KEY_TEXT_UNDO         = 21
    NK_KEY_TEXT_REDO         = 22
    NK_KEY_TEXT_SELECT_ALL   = 23
    NK_KEY_TEXT_WORD_LEFT    = 24
    NK_KEY_TEXT_WORD_RIGHT   = 25
    NK_KEY_SCROLL_START      = 26
    NK_KEY_SCROLL_END        = 27
    NK_KEY_SCROLL_DOWN       = 28
    NK_KEY_SCROLL_UP         = 29
    NK_KEY_ALT               = 30
    NK_KEY_F1                = 31
    NK_KEY_F2                = 32
    NK_KEY_F3                = 33
    NK_KEY_F4                = 34
    NK_KEY_F5                = 35
    NK_KEY_F6                = 36
    NK_KEY_F7                = 37
    NK_KEY_F8                = 38
    NK_KEY_F9                = 39
    NK_KEY_F10               = 40
    NK_KEY_F11               = 41
    NK_KEY_F12               = 42
    NK_KEY_MAX               = 43

  NkTextAlign* {.importc: "enum nk_text_align", header: nkH,
                 size: sizeof(cint).} = enum
    NK_TEXT_ALIGN_LEFT     = 0x01
    NK_TEXT_ALIGN_CENTERED = 0x02
    NK_TEXT_ALIGN_RIGHT    = 0x04
    NK_TEXT_ALIGN_TOP      = 0x08
    NK_TEXT_ALIGN_MIDDLE   = 0x10
    NK_TEXT_ALIGN_BOTTOM   = 0x20

## Convenience combinations (bitmask OR of NkTextAlign values).
## These are raddy-defined constants, NOT re-exported macros from nuklear.h.
const
  NK_TEXT_LEFT*: nk_flags =
    nk_flags(NK_TEXT_ALIGN_MIDDLE) or nk_flags(NK_TEXT_ALIGN_LEFT)
  NK_TEXT_CENTERED*: nk_flags =
    nk_flags(NK_TEXT_ALIGN_MIDDLE) or nk_flags(NK_TEXT_ALIGN_CENTERED)
  NK_TEXT_RIGHT*: nk_flags =
    nk_flags(NK_TEXT_ALIGN_MIDDLE) or nk_flags(NK_TEXT_ALIGN_RIGHT)

## NK_* constants are intentionally unpure (no {.pure.}) for C-name parity — do not add {.pure.}.
## Enum ordinal cross-checks live in tests/test_smoke.nim (NK_COMMAND_CUSTOM==18, NK_BUTTON_MAX==6, NK_KEY_MAX==43).

# ---------------------------------------------------------------------------
# Command base and header
# ---------------------------------------------------------------------------

type
  nk_command* {.importc: "struct nk_command", header: nkH.} = object
    `type`*: NkCommandType  ## discriminator; use case statement in renderer
    next*:   nk_size        ## byte offset to next command in the buffer

  # --- Scissor ---
  nk_command_scissor* {.importc: "struct nk_command_scissor", header: nkH.} = object
    header*:  nk_command
    x*, y*:   int16
    w*, h*:   uint16

  # --- Line ---
  nk_command_line* {.importc: "struct nk_command_line", header: nkH.} = object
    header*:         nk_command
    line_thickness*: uint16
    `begin`*:        nk_vec2i  ## Nim keyword; C field: begin
    `end`*:          nk_vec2i  ## Nim keyword; C field: end
    color*:          nk_color

  # --- Cubic Bézier curve ---
  nk_command_curve* {.importc: "struct nk_command_curve", header: nkH.} = object
    header*:         nk_command
    line_thickness*: uint16
    `begin`*:        nk_vec2i     ## C: begin
    `end`*:          nk_vec2i     ## C: end
    ctrl*:           array[2, nk_vec2i]
    color*:          nk_color

  # --- Rectangle outline ---
  nk_command_rect* {.importc: "struct nk_command_rect", header: nkH.} = object
    header*:         nk_command
    rounding*:       uint16
    line_thickness*: uint16
    x*, y*:          int16
    w*, h*:          uint16
    color*:          nk_color

  # --- Rectangle filled ---
  nk_command_rect_filled* {.importc: "struct nk_command_rect_filled", header: nkH.} = object
    header*:   nk_command
    rounding*: uint16
    x*, y*:    int16
    w*, h*:    uint16
    color*:    nk_color

  # --- Rectangle multi-color gradient ---
  nk_command_rect_multi_color* {.importc: "struct nk_command_rect_multi_color", header: nkH.} = object
    header*:  nk_command
    x*, y*:   int16
    w*, h*:   uint16
    left*:    nk_color
    top*:     nk_color
    bottom*:  nk_color
    right*:   nk_color

  # --- Triangle outline ---
  nk_command_triangle* {.importc: "struct nk_command_triangle", header: nkH.} = object
    header*:         nk_command
    line_thickness*: uint16
    a*, b*, c*:      nk_vec2i
    color*:          nk_color

  # --- Triangle filled ---
  nk_command_triangle_filled* {.importc: "struct nk_command_triangle_filled", header: nkH.} = object
    header*:    nk_command
    a*, b*, c*: nk_vec2i
    color*:     nk_color

  # --- Circle / ellipse outline ---
  nk_command_circle* {.importc: "struct nk_command_circle", header: nkH.} = object
    header*:         nk_command
    x*, y*:          int16
    line_thickness*: uint16
    w*, h*:          uint16
    color*:          nk_color

  # --- Circle / ellipse filled ---
  nk_command_circle_filled* {.importc: "struct nk_command_circle_filled", header: nkH.} = object
    header*: nk_command
    x*, y*:  int16
    w*, h*:  uint16
    color*:  nk_color

  # --- Arc outline ---
  nk_command_arc* {.importc: "struct nk_command_arc", header: nkH.} = object
    header*:         nk_command
    cx*, cy*:        int16
    r*:              uint16
    line_thickness*: uint16
    a*:              array[2, float32]  ## [start_radians, end_radians]
    color*:          nk_color

  # --- Arc filled ---
  nk_command_arc_filled* {.importc: "struct nk_command_arc_filled", header: nkH.} = object
    header*:  nk_command
    cx*, cy*: int16
    r*:       uint16
    a*:       array[2, float32]
    color*:   nk_color

  # --- Polygon outline (flexible-array points: access via UncheckedArray cast) ---
  nk_command_polygon* {.importc: "struct nk_command_polygon", header: nkH.} = object
    header*:         nk_command
    color*:          nk_color
    line_thickness*: uint16
    point_count*:    uint16
    points*:         array[1, nk_vec2i]  ## FAM sentinel; cast to UncheckedArray for traversal

  # --- Polygon filled ---
  nk_command_polygon_filled* {.importc: "struct nk_command_polygon_filled", header: nkH.} = object
    header*:      nk_command
    color*:       nk_color
    point_count*: uint16
    points*:      array[1, nk_vec2i]

  # --- Polyline (open path) ---
  nk_command_polyline* {.importc: "struct nk_command_polyline", header: nkH.} = object
    header*:         nk_command
    color*:          nk_color
    line_thickness*: uint16
    point_count*:    uint16
    points*:         array[1, nk_vec2i]

  # --- Text ---
  nk_command_text* {.importc: "struct nk_command_text", header: nkH.} = object
    header*:     nk_command
    font*:       ptr nk_user_font
    background*: nk_color
    foreground*: nk_color
    x*, y*:      int16
    w*, h*:      uint16
    height*:     float32  ## draw size (equals cmd.font.height under pinned-font contract)
    length*:     cint     ## byte count — NOT null-terminated
    `string`*:   array[2, char]  ## FAM sentinel; read via copyMem(buf, addr cmd.`string`[0], cmd.length)

  # --- Image (texture blit) ---
  nk_command_image* {.importc: "struct nk_command_image", header: nkH.} = object
    header*: nk_command
    x*, y*:  int16
    w*, h*:  uint16
    img*:    nk_image
    col*:    nk_color

  ## nk_command_custom: PARTIAL VIEW — callback field omitted (raddy never invokes it).
  ## Do not sizeof or construct-by-value; the real C struct has a trailing function
  ## pointer that is not declared here.
  nk_command_custom* {.importc: "struct nk_command_custom", header: nkH.} = object
    header*:        nk_command
    x*, y*:         int16
    w*, h*:         uint16
    callback_data*: nk_handle
