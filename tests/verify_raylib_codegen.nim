## verify_raylib_codegen.nim — C-level importc name verification for raylib_api.nim.
##
## This file is compiled with `nim c --compileOnly --passC:"-I<naylib>/raylib"`.
## It is NOT linked or run — it exists solely so gcc sees each r* proc call site
## and verifies the importc C names against the real raylib.h declarations.
##
## Nim semantic analysis alone (nim check) does NOT verify importc names: procs
## that are unused get dead-code eliminated before C codegen, so a misspelled
## importc name would silently pass check + nimble test. Module-level statements
## force Nim to emit every call to the generated C, where gcc catches typos.
##
## Usage (via verify.sh — do not call directly):
##   nim c --compileOnly --mm:orc --passC:"-I<naylib>/raylib" tests/verify_raylib_codegen.nim

import raddy/backend/raylib_api

## Zero-value locals used as arguments. Types must match proc signatures exactly.
var c:  RColor
var v:  RVec2
var r:  RRect
var f:  RFont
var t:  RTexture
var s:  cstring = nil
var p:  ptr RVec2 = nil

## Module-level proc calls — each must appear in generated C for gcc to verify.
## Calls are unreachable at link/run time (no main window, no display); this
## file is compiled with --compileOnly only.
rDrawRectangleRec(r, c)
rDrawRectangleLinesEx(r, 0f, c)
rDrawRectangleRounded(r, 0f, 0i32, c)
rDrawRectangleRoundedLinesEx(r, 0f, 0i32, 0f, c)
rDrawRectangleGradientEx(r, c, c, c, c)
rDrawLineEx(v, v, 0f, c)
rDrawLineStrip(p, 0i32, c)
rDrawTriangle(v, v, v, c)
rDrawTriangleLines(v, v, v, c)
rDrawRing(v, 0f, 0f, 0f, 0f, 0i32, c)
rDrawCircleSector(v, 0f, 0f, 0f, 0i32, c)
rDrawEllipse(0i32, 0i32, 0f, 0f, c)
rDrawEllipseLines(0i32, 0i32, 0f, 0f, c)
rDrawTextEx(f, s, v, 0f, 0f, c)
rDrawTextureRec(t, r, v, c)
rBeginScissorMode(0i32, 0i32, 0i32, 0i32)
rEndScissorMode()
