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

  it "h=0 guard → returns 0.0":
    let r = rectRoundness(5.0f, 50.0f, 0.0f)
    verify:
      r == 0.0f

spec "fixTriWinding":
  it "CW triangle (positive area in Y-down) causes b,c swap":
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

  it "PI/2 radians → ~90.0 degrees (non-cancelling test)":
    ## Uses a literal for PI/2 so this doesn't depend on geom.PI cancelling.
    let deg = radToDeg(1.5707964f)
    let diff = deg - 90.0f
    verify:
      (if diff < 0.0f: -diff else: diff) < 0.001f

spec "bezierTessellate":
  it "P0=(0,0) P3=(1,1) → pts[0]=(0,0), pts[BezierSegs]=(1,1), midpoint in [0.4,0.6]":
    let P0 = RVec2(x: 0.0f, y: 0.0f)
    let P1 = RVec2(x: 0.0f, y: 0.0f)
    let P2 = RVec2(x: 1.0f, y: 1.0f)
    let P3 = RVec2(x: 1.0f, y: 1.0f)
    var pts: array[BezierSegs + 1, RVec2]
    bezierTessellate(P0, P1, P2, P3, pts)
    verify:
      pts[0].x == 0.0f and pts[0].y == 0.0f and
      pts[BezierSegs].x == 1.0f and pts[BezierSegs].y == 1.0f and
      pts[BezierSegs div 2].x >= 0.4f and pts[BezierSegs div 2].x <= 0.6f

  it "straight line P0=(0,0) P1=(0,0) P2=(1,0) P3=(1,0) → all y==0":
    ## A degenerate Bézier where all control points share y=0 should produce flat strip.
    let P0 = RVec2(x: 0.0f, y: 0.0f)
    let P1 = RVec2(x: 0.0f, y: 0.0f)
    let P2 = RVec2(x: 1.0f, y: 0.0f)
    let P3 = RVec2(x: 1.0f, y: 0.0f)
    var pts: array[BezierSegs + 1, RVec2]
    bezierTessellate(P0, P1, P2, P3, pts)
    var allYZero = true
    for i in 0 .. BezierSegs:
      if pts[i].y != 0.0f: allYZero = false
    verify:
      allYZero
