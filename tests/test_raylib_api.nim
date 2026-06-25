## raylib_api spec: Nim-level type aliases are correct and importc bindings compile.
##
## These tests only verify raddy's R* types — no raylib draw calls are made.
## C-level verification (linking against libraylib) happens when a game imports
## raddy and compiles with naylib. Proc signatures are verified by nim check in
## verify.sh; the importc names are verified at game link time.
##
## Note: the test binary is compiled with --passC:"-I<naylib_raylib_dir>" in
## the nimble task (config.nims) so raylib.h is found for the importc types.

import bddy
import raddy/backend/raylib_api
{.warning[UnusedImport]: off.}

spec "raylib_api: type aliases":
  it "RColor has correct r g b a uint8 fields":
    var c = RColor(r: 255'u8, g: 128'u8, b: 0'u8, a: 200'u8)
    verify:
      c.r == 255'u8 and c.g == 128'u8 and c.b == 0'u8 and c.a == 200'u8

  it "RVec2 has correct x y float32 fields":
    var v = RVec2(x: 3.14f, y: -1.0f)
    verify:
      v.x == 3.14f and v.y == -1.0f

  it "RRect has correct x y width height float32 fields":
    var r = RRect(x: 10.0f, y: 20.0f, width: 100.0f, height: 50.0f)
    verify:
      r.x == 10.0f and r.y == 20.0f and r.width == 100.0f and r.height == 50.0f

  it "RColor sizeof is 4 bytes (matches C Color struct)":
    verify:
      sizeof(RColor) == 4

  it "RVec2 sizeof is 8 bytes (matches C Vector2 struct)":
    verify:
      sizeof(RVec2) == 8

  it "RRect sizeof is 16 bytes (matches C rlRectangle struct)":
    verify:
      sizeof(RRect) == 16
