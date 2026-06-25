## raylib_api spec: Nim-level type aliases are correct and importc bindings compile.
##
## These tests only verify raddy's R* types — no raylib draw calls are made.
## C-level importc NAME verification is done in verify.sh via
## tests/verify_raylib_codegen.nim compiled with --compileOnly + naylib passC:
## that file references every r* proc so gcc checks the C names against raylib.h.
## Full signature type-checking happens at game build time.
##
## Note: the test binary needs --passC:"-I<naylib_raylib_dir>" so raylib.h is
## found by gcc when compiling the importc completeStruct types. The nimble task
## discovers naylib's path automatically via `find ~/.nimble/pkgs2 -name naylib-*`.

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
