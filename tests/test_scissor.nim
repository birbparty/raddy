## test_scissor.nim — bddy spec for src/raddy/backend/scissor.nim

import bddy
import raddy/backend/scissor

spec "scissorYFlip":
  it "y=0, h=100, H=100 → y'=0":
    let (_, ry, _, _) = scissorYFlip(10, 0, 80, 100, 100)
    verify:
      ry == 0

  it "y=10, h=50, H=480 → y'=420":
    let (_, ry, _, _) = scissorYFlip(0, 10, 100, 50, 480)
    verify:
      ry == 420

  it "x, w, h pass through unchanged":
    let (rx, _, rw, rh) = scissorYFlip(42, 10, 200, 50, 480)
    verify:
      rx == 42 and rw == 200 and rh == 50

  it "bottom rect: y=H-h → y'=0":
    let (_, ry, _, _) = scissorYFlip(0, 430, 100, 50, 480)
    verify:
      ry == 0
