## test_geom.nim — bddy spec for src/raddy/backend/geom.nim

import bddy
import raddy/types
import raddy/backend/raylib_api
import raddy/backend/geom

spec "toRColor":
  it "converts nk_color fields 1:1 to RColor":
    let c = nk_color(r: 255, g: 128, b: 0, a: 200)
    let rc = toRColor(c)
    verify:
      rc.r == 255 and rc.g == 128 and rc.b == 0 and rc.a == 200

spec "rectRoundness":
  it "rounding=5, w=100, h=50 → 2*5/50 = 0.2":
    let r = rectRoundness(5.0f, 100.0f, 50.0f)
    verify:
      r > 0.19f and r < 0.21f

  it "rounding=100, w=10, h=10 → clamped to 1.0":
    let r = rectRoundness(100.0f, 10.0f, 10.0f)
    verify:
      r == 1.0f

  it "w=0 guard → returns 0.0":
    let r = rectRoundness(5.0f, 0.0f, 50.0f)
    verify:
      r == 0.0f

spec "fixTriWinding":
  it "CW triangle (positive area in Y-down) causes b,c swap":
    ## In Y-down, a=(0,0) b=(10,0) c=(0,10) is CCW (area < 0), so pick a CW one.
    ## a=(0,0) b=(0,10) c=(10,0): area = (0-0)*(0-0)-(10-0)*(10-0) = 0-100 = -100 → CCW
    ## a=(0,0) b=(10,0) c=(0,-10): area = (10-0)*(-10-0)-(0-0)*(0-0) = -100 → CCW
    ## CW in Y-down: a=(0,0) b=(0,10) c=(10,10) → area=(0)*(10)-(10)*(10)=-100 ... hmm
    ## Let's be explicit: area=(b.x-a.x)*(c.y-a.y)-(c.x-a.x)*(b.y-a.y)
    ## a=(0,0) b=(1,0) c=(1,1): area=(1)*(1)-(1)*(0)=1 > 0 → CW → swap expected
    var a = RVec2(x: 0.0f, y: 0.0f)
    var b = RVec2(x: 1.0f, y: 0.0f)
    var c = RVec2(x: 1.0f, y: 1.0f)
    let bBefore = b
    let cBefore = c
    fixTriWinding(a, b, c)
    verify:
      b.x == cBefore.x and b.y == cBefore.y and c.x == bBefore.x and c.y == bBefore.y

  it "CCW triangle (negative area in Y-down) causes no swap":
    ## a=(0,0) b=(1,1) c=(1,0): area=(1)*(0)-(1)*(1)=-1 < 0 → CCW → no swap
    var a = RVec2(x: 0.0f, y: 0.0f)
    var b = RVec2(x: 1.0f, y: 1.0f)
    var c = RVec2(x: 1.0f, y: 0.0f)
    let bBefore = b
    let cBefore = c
    fixTriWinding(a, b, c)
    verify:
      b.x == bBefore.x and b.y == bBefore.y and c.x == cBefore.x and c.y == cBefore.y

spec "radToDeg":
  it "0.0 radians → 0.0 degrees":
    verify:
      radToDeg(0.0f) == 0.0f

  it "PI radians → ~180.0 degrees (abs diff < 0.001)":
    let deg = radToDeg(PI)
    let diff = deg - 180.0f
    verify:
      (if diff < 0.0f: -diff else: diff) < 0.001f

spec "bezierTessellate":
  it "P0=(0,0) P3=(1,1) → pts[0]=(0,0), pts[20]=(1,1), pts[10].x in [0.4,0.6]":
    let P0 = RVec2(x: 0.0f, y: 0.0f)
    let P1 = RVec2(x: 0.0f, y: 0.0f)
    let P2 = RVec2(x: 1.0f, y: 1.0f)
    let P3 = RVec2(x: 1.0f, y: 1.0f)
    var pts: array[21, RVec2]
    bezierTessellate(P0, P1, P2, P3, pts)
    verify:
      pts[0].x == 0.0f and pts[0].y == 0.0f and
      pts[20].x == 1.0f and pts[20].y == 1.0f and
      pts[10].x >= 0.4f and pts[10].x <= 0.6f
