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
`raddyGroupEnd` must **only** be called when `raddyGroupBegin` returns `true`. Groups behave differently from windows in this respect — calling `raddyGroupEnd` on a collapsed group corrupts context state.

```nim
# Correct pattern
if raddyGroupBegin(ctx, "panel", flags):
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

Opens a Nuklear window. Returns `true` if the window is open and should be populated with widgets. `flags` is a bitfield of `NkWindowFlags` values (e.g. `NK_WINDOW_BORDER`, `NK_WINDOW_TITLE`, `NK_WINDOW_MOVABLE`, `NK_WINDOW_SCALABLE`, `NK_WINDOW_CLOSABLE`).

`raddyEnd` must always follow, regardless of the return value.

```nim
let flags = NK_WINDOW_BORDER.nk_flags or NK_WINDOW_TITLE.nk_flags or NK_WINDOW_MOVABLE.nk_flags
if not raddyBegin(ctx, "Settings", nk_rect(x:50, y:50, w:300, h:400), flags):
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

Layout must be set before adding widgets to a row. A new layout call is required for each row (or reused across rows when using `raddyLayoutRowBegin`).

### raddyLayoutRowDynamic

```nim
proc raddyLayoutRowDynamic(ctx: ptr nk_context; height: float32; cols: int32)
```

Divides the available row width equally among `cols` columns. `height` is in pixels. Most common layout for forms and toolbars.

```nim
raddyLayoutRowDynamic(ctx, height=30, cols=2)
raddyLabel(ctx, "Name:", NK_TEXT_LEFT)
raddyEdit(ctx, NK_EDIT_FIELD, nameBuffer, maxLen)
```

### raddyLayoutRowStatic

```nim
proc raddyLayoutRowStatic(ctx: ptr nk_context; height: float32;
                           itemWidth: int32; cols: int32)
```

Each column has a fixed pixel width of `itemWidth`. Useful when columns must not resize.

```nim
raddyLayoutRowStatic(ctx, height=25, itemWidth=80, cols=3)
```

### raddyLayoutRowBegin / Push / End

```nim
proc raddyLayoutRowBegin(ctx: ptr nk_context; fmt: nk_layout_format;
                          rowHeight: float32; cols: int32)
proc raddyLayoutRowPush(ctx: ptr nk_context; value: float32)
proc raddyLayoutRowEnd(ctx: ptr nk_context)
```

Manual per-column sizing. `fmt` is `NK_STATIC` (pixels) or `NK_DYNAMIC` (ratio 0.0–1.0). Call `raddyLayoutRowPush` once per column before the corresponding widget.

```nim
raddyLayoutRowBegin(ctx, NK_STATIC, rowHeight=30, cols=2)
raddyLayoutRowPush(ctx, 120)   # label column: 120px
raddyLabel(ctx, "Volume", NK_TEXT_LEFT)
raddyLayoutRowPush(ctx, 180)   # slider column: 180px
raddySlider(ctx, min=0, val=addr volume, max=100, step=1)
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

**Returns:** nothing.

### raddyButton

```nim
proc raddyButton(ctx: ptr nk_context; title: string): bool
```

Draws a push button. Returns `true` on the frame the button is clicked.

```nim
if raddyButton(ctx, "Apply"):
  applySettings()
```

**Returns:** `true` when clicked (single frame).

### raddyCheckbox

```nim
proc raddyCheckbox(ctx: ptr nk_context; label: string;
                   active: ptr nk_bool): bool
```

Draws a labeled checkbox. `active` is the current checked state; Nuklear writes the new state back through the pointer each frame. Returns `true` when the value changes.

```nim
var showGrid: nk_bool = nk_false
# in frame loop:
discard raddyCheckbox(ctx, "Show grid", addr showGrid)
```

**Returns:** `true` if the checkbox state changed this frame.

### raddySlider

```nim
proc raddySlider(ctx: ptr nk_context; min: float32; val: ptr float32;
                 max: float32; step: float32): bool
```

Draws a horizontal slider. `val` is read and written each frame. Returns `true` when the value changes.

```nim
var brightness: float32 = 0.8
discard raddySlider(ctx, min=0.0, val=addr brightness, max=1.0, step=0.05)
```

**Returns:** `true` if the value changed this frame.

### raddyEdit

```nim
proc raddyEdit(ctx: ptr nk_context; flags: nk_flags;
               buffer: ptr char; len: ptr int32;
               maxLen: int32): nk_flags
```

Draws a single-line or multi-line text editor. `flags` controls mode (e.g. `NK_EDIT_FIELD` for single-line, `NK_EDIT_BOX` for multi-line). `buffer` is a fixed-size char array; `len` tracks current length; `maxLen` is the buffer capacity.

```nim
var inputBuf: array[256, char]
var inputLen: int32 = 0
discard raddyEdit(ctx, NK_EDIT_FIELD, addr inputBuf[0], addr inputLen, 256)
```

**Returns:** `nk_flags` bitmask indicating edit state (active, committed, etc.).

### raddyCombo

```nim
proc raddyCombo(ctx: ptr nk_context; items: openArray[string];
                selected: int32; itemHeight: int32;
                size: nk_vec2): int32
```

Draws a drop-down combo box. `selected` is the currently active index. `size` is the popup dimensions. Returns the newly selected index (may equal `selected` if unchanged).

```nim
const modes = ["Windowed", "Fullscreen", "Borderless"]
var modeIdx: int32 = 0
modeIdx = raddyCombo(ctx, modes, modeIdx, itemHeight=25,
                     size=nk_vec2(x:200, y:100))
```

**Returns:** index of the selected item.

### raddyProperty

```nim
proc raddyProperty(ctx: ptr nk_context; name: string;
                   min: float64; val: ptr float64; max: float64;
                   step: float64; incPerPixel: float32)
```

Draws a labeled numeric property (drag-to-edit or click-to-type). `name` is displayed as-is; prefix with `#` to hide the label but keep it as an ID. `incPerPixel` controls drag sensitivity.

```nim
var mass: float64 = 1.0
raddyProperty(ctx, "Mass (kg)", min=0.01, val=addr mass,
              max=1000.0, step=0.1, incPerPixel=0.5)
```

**Returns:** nothing (value written through `val`).

### raddySpacing

```nim
proc raddySpacing(ctx: ptr nk_context; cols: int32)
```

Skips `cols` column slots in the current layout row, inserting blank space.

```nim
raddyLayoutRowDynamic(ctx, height=30, cols=3)
raddyButton(ctx, "Back")
raddySpacing(ctx, 1)   # empty middle column
raddyButton(ctx, "Next")
```

---

## Group procs

Groups provide scrollable sub-regions within a window. Unlike windows, the close contract is reversed: `raddyGroupEnd` is only called when `raddyGroupBegin` returned `true`.

### raddyGroupBegin

```nim
proc raddyGroupBegin(ctx: ptr nk_context; title: string;
                     flags: nk_flags): bool
```

Opens a scrollable group. Returns `true` if the group should be populated. `flags` supports `NK_WINDOW_BORDER`, `NK_WINDOW_TITLE`, `NK_WINDOW_NO_SCROLLBAR`.

### raddyGroupEnd

```nim
proc raddyGroupEnd(ctx: ptr nk_context)
```

Closes a group. Call **only** when `raddyGroupBegin` returned `true`.

```nim
if raddyGroupBegin(ctx, "Items", NK_WINDOW_BORDER.nk_flags):
  for item in itemList:
    raddyLayoutRowDynamic(ctx, height=24, cols=1)
    raddyLabel(ctx, item, NK_TEXT_LEFT)
  raddyGroupEnd(ctx)
```
