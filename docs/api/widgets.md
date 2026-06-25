# raddy Widget API Reference

## Critical contracts

**Windows (`raddyBegin`/`raddyEnd`):**
`raddyEnd` **must always be called**, even when `raddyBegin` returns `false`. Nuklear's internal state machine requires the paired close call regardless of whether the window is visible or collapsed.

```nim
# Correct pattern
if not raddyBegin(ctx, "name", bounds, flags):
  raddyEnd(ctx)   # still required
  return
# ... widgets ...
raddyEnd(ctx)
```

**Groups (`raddyGroupBegin`/`raddyGroupEnd`):**
`raddyGroupEnd` must **only** be called when `raddyGroupBegin` returns `true`. Groups behave differently from windows in this respect — calling `raddyGroupEnd` on a non-visible group corrupts context state.

```nim
# Correct pattern
if raddyGroupBegin(ctx, "panel", NK_WINDOW_BORDER.nk_flags):
  # ... widgets ...
  raddyGroupEnd(ctx)   # only here
```

---

## Window procs

### raddyBegin

```nim
proc raddyBegin(ctx: ptr nk_context; title: string; bounds: nk_rect;
                flags: nk_flags): bool
```

Opens a Nuklear window. Returns `true` if the window is open and should be populated with widgets. `flags` is a bitfield of `NkWindowFlags` values combined with `or`:

```nim
let flags = NK_WINDOW_BORDER.nk_flags or NK_WINDOW_TITLE.nk_flags or
            NK_WINDOW_MOVABLE.nk_flags or NK_WINDOW_SCALABLE.nk_flags
if not raddyBegin(ctx, "Settings", nk_rect(x: 50, y: 50, w: 300, h: 400), flags):
  raddyEnd(ctx); return
# widgets go here
raddyEnd(ctx)
```

### raddyEnd

```nim
proc raddyEnd(ctx: ptr nk_context)
```

Closes a window opened with `raddyBegin`. Must be called unconditionally after every `raddyBegin`.

---

## Layout procs

Layout must be set before adding widgets to a row.

### raddyLayoutRowDynamic

```nim
proc raddyLayoutRowDynamic(ctx: ptr nk_context; height: float32; cols: int)
```

Divides the available row width equally among `cols` columns. `height` is in pixels (pass `0` for natural height).

```nim
raddyLayoutRowDynamic(ctx, height = 30, cols = 2)
raddyLabel(ctx, "Name:", NK_TEXT_LEFT)
raddyEdit(ctx, NK_EDIT_FIELD_FLAGS, nameBuf, maxLen = 64)
```

### raddyLayoutRowStatic

```nim
proc raddyLayoutRowStatic(ctx: ptr nk_context; height: float32;
                           itemWidth: int; cols: int)
```

Each column has a fixed pixel width of `itemWidth`.

```nim
raddyLayoutRowStatic(ctx, height = 25, itemWidth = 80, cols = 3)
```

### raddyLayoutRowBegin / Push / End

```nim
proc raddyLayoutRowBegin(ctx: ptr nk_context; fmt: NkLayoutFormat;
                          rowHeight: float32; cols: int)
proc raddyLayoutRowPush(ctx: ptr nk_context; value: float32)
proc raddyLayoutRowEnd(ctx: ptr nk_context)
```

Manual per-column sizing. `fmt` is `NK_STATIC` (pixel widths) or `NK_DYNAMIC` (ratios 0.0–1.0). Call `raddyLayoutRowPush` once per column before the corresponding widget, then `raddyLayoutRowEnd` to close the row.

```nim
raddyLayoutRowBegin(ctx, NK_STATIC, rowHeight = 30, cols = 2)
raddyLayoutRowPush(ctx, 120)   # label column: 120px
raddyLabel(ctx, "Volume", NK_TEXT_LEFT)
raddyLayoutRowPush(ctx, 180)   # slider column: 180px
raddySlider(ctx, minVal = 0, val = volume, maxVal = 100, step = 1)
raddyLayoutRowEnd(ctx)
```

---

## Widget procs

### raddyLabel

```nim
proc raddyLabel(ctx: ptr nk_context; text: string; align: nk_flags)
```

Draws a static text label. `align` is one of `NK_TEXT_LEFT`, `NK_TEXT_CENTERED`, `NK_TEXT_RIGHT`.

```nim
raddyLabel(ctx, "Hello, world!", NK_TEXT_LEFT)
```

### raddyButton

```nim
proc raddyButton(ctx: ptr nk_context; label: string): bool
```

Draws a push button. Returns `true` on the frame the button is clicked.

```nim
if raddyButton(ctx, "Apply"):
  applySettings()
```

### raddyCheckbox

```nim
proc raddyCheckbox(ctx: ptr nk_context; label: string;
                   active: var bool): bool
```

Draws a labeled checkbox. `active` is read and written each frame (Nuklear updates it through the `var` reference). Returns `true` when the value changes.

```nim
var showGrid = false
# in frame loop:
discard raddyCheckbox(ctx, "Show grid", showGrid)
```

### raddySlider

```nim
proc raddySlider(ctx: ptr nk_context; minVal: float32; val: var float32;
                 maxVal: float32; step: float32): bool
```

Draws a horizontal slider. `val` is read and written each frame. Returns `true` when the value changes.

```nim
var brightness = 0.8f
discard raddySlider(ctx, minVal = 0.0f, val = brightness, maxVal = 1.0f, step = 0.05f)
```

### raddyEdit

```nim
proc raddyEdit(ctx: ptr nk_context; flags: nk_flags; buf: var string;
               maxLen: int; filter: NkPluginFilter = nil): nk_flags
```

Draws a text editor. `buf` is a Nim `string` that Nuklear reads and writes directly. `maxLen` is the maximum number of editable characters (one extra byte is reserved internally for Nuklear's NUL terminator). `filter` restricts which characters are accepted; `nil` accepts any character.

`flags` is typically `NK_EDIT_FIELD_FLAGS` for a single-line field or `NK_EDIT_BOX_FLAGS` for multi-line.

```nim
var inputBuf = "Hello!"
discard raddyEdit(ctx, NK_EDIT_FIELD_FLAGS, inputBuf, maxLen = 127)
```

Returns a bitmask of `NkEditEvents` (e.g. `NK_EDIT_COMMITTED` when the user presses Enter).

### raddyCombo

```nim
proc raddyCombo(ctx: ptr nk_context; items: openArray[string]; selected: int;
                itemHeight: int; size: nk_vec2): int
```

Draws a drop-down combo box. `selected` is the currently active index. `size` is the popup panel dimensions. Returns the newly selected index (may equal `selected` if unchanged).

Note: allocates a `seq[cstring]` on every call — avoid in tight inner loops.

```nim
const modes = ["Windowed", "Fullscreen", "Borderless"]
var modeIdx = 0
modeIdx = raddyCombo(ctx, modes, modeIdx, itemHeight = 25,
                     size = nk_vec2(x: 200, y: 100))
```

### raddyProperty

```nim
proc raddyProperty(ctx: ptr nk_context; name: string; minVal: float32;
                   val: var float32; maxVal: float32; step: float32;
                   incPerPixel: float32 = 1.0): bool
```

Draws a labeled numeric property (drag-to-edit or click-to-type). `val` is read and written each frame. `incPerPixel` controls drag sensitivity. Prefix `name` with `#` to hide the label while keeping it as a unique ID.

Returns `true` if the value changed this frame.

```nim
var mass = 1.0f
discard raddyProperty(ctx, "Mass (kg)", minVal = 0.01f, val = mass,
                      maxVal = 1000.0f, step = 0.1f, incPerPixel = 0.5f)
```

### raddySpacing

```nim
proc raddySpacing(ctx: ptr nk_context; cols: int)
```

Skips `cols` column slots in the current layout row, inserting blank space.

```nim
raddyLayoutRowDynamic(ctx, height = 30, cols = 3)
raddyButton(ctx, "Back")
raddySpacing(ctx, 1)   # empty middle column
raddyButton(ctx, "Next")
```

---

## Group procs

Groups provide scrollable sub-regions within a window. Unlike windows, `raddyGroupEnd` is only called when `raddyGroupBegin` returned `true`.

### raddyGroupBegin

```nim
proc raddyGroupBegin(ctx: ptr nk_context; title: string;
                     flags: nk_flags = 0): bool
```

Opens a scrollable group. Returns `true` if the group should be populated. The `title` also serves as the group's unique scroll-state ID within the window — two groups with the same title share scroll state.

`flags` supports `NK_WINDOW_BORDER`, `NK_WINDOW_TITLE`, `NK_WINDOW_NO_SCROLLBAR`.

### raddyGroupEnd

```nim
proc raddyGroupEnd(ctx: ptr nk_context)
```

Closes a group. Call **only** when `raddyGroupBegin` returned `true`.

```nim
if raddyGroupBegin(ctx, "Items", NK_WINDOW_BORDER.nk_flags):
  raddyLayoutRowDynamic(ctx, height = 24, cols = 1)
  for item in itemList:
    raddyLabel(ctx, item, NK_TEXT_LEFT)
  raddyGroupEnd(ctx)
```
