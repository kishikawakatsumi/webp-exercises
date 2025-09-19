let nPred: Int = 10

enum Pred: UInt8 {
  case dc = 0 // DC  (average of surrounding samples)
  case tm = 1 // TrueMotion (b + p − a)
  case ve = 2 // Vertical (smoothed)
  case he = 3 // Horizontal (smoothed)
  case rd = 4 // “Right-Down” diagonal
  case vr = 5 // “Vertical-Right” diagonal
  case ld = 6 // “Left-Down” diagonal
  case vl = 7 // “Vertical-Left” diagonal
  case hd = 8 // “Horizontal-Down” diagonal
  case hu = 9 // “Horizontal-Up” diagonal
  // DC variants for edge macro-blocks (8×8 / 16×16 only)
  case dcTop = 10  // No pixels above
  case dcLeft = 11  // No pixels to the left
  case dcTopLeft = 12  // No pixels above *or* to the left
}

@inline(__always)
func checkTopLeftPred(mbx: Int, mby: Int, p: UInt8) -> UInt8 {
  // If not DC, nothing to adjust.
  if p != Pred.dc.rawValue { return p }

  // Top-left corner
  if mbx == 0 {
    return (mby == 0)
    ? Pred.dcTopLeft.rawValue   // no top *and* no left
    : Pred.dcLeft.rawValue      // no left
  }

  if mby == 0 {
    return Pred.dcTop.rawValue
  }

  return Pred.dc.rawValue
}

typealias PredFunc = (inout VP8Decoder, Int, Int) -> Void

nonisolated(unsafe) let predFunc4: [PredFunc?] = [
  predFunc4DC,
  predFunc4TM,
  predFunc4VE,
  predFunc4HE,
  predFunc4RD,
  predFunc4VR,
  predFunc4LD,
  predFunc4VL,
  predFunc4HD,
  predFunc4HU,
  nil, nil, nil
]

nonisolated(unsafe) let predFunc8: [PredFunc?] = [
  predFunc8DC,
  predFunc8TM,
  predFunc8VE,
  predFunc8HE,
  nil, nil, nil, nil, nil, nil,
  predFunc8DCTop,
  predFunc8DCLeft,
  predFunc8DCTopLeft
]

nonisolated(unsafe) let predFunc16: [PredFunc?] = [
  predFunc16DC,
  predFunc16TM,
  predFunc16VE,
  predFunc16HE,
  nil,
  nil,
  nil,
  nil,
  nil,
  nil,
  predFunc16DCTop,
  predFunc16DCLeft,
  predFunc16DCTopLeft
]

func predFunc4DC(_ z: inout VP8Decoder, _ y: Int, _ x: Int) {
  var sum: UInt32 = 4
  for i in 0..<4 {
    sum += UInt32(z.ybr[y - 1][x + i])
  }
  for j in 0..<4 {
    sum += UInt32(z.ybr[y + j][x - 1])
  }

  let avg = UInt8(sum / 8)

  for j in 0..<4 {
    for i in 0..<4 {
      z.ybr[y + j][x + i] = avg
    }
  }
}

@inline(__always)
private func clip(_ v: Int32, min lo: Int32 = 0, max hi: Int32 = 255) -> UInt8 {
  if v < lo { return UInt8(lo) }
  if v > hi { return UInt8(hi) }
  return UInt8(v)
}

func predFunc4TM(_ z: inout VP8Decoder, _ y: Int, _ x: Int) {
  let minusTL = -Int32(z.ybr[y - 1][x - 1])

  for j in 0..<4 {
    let delta1 = minusTL + Int32(z.ybr[y + j][x - 1])

    for i in 0..<4 {
      let delta2 = delta1 + Int32(z.ybr[y - 1][x + i])
      z.ybr[y + j][x + i] = clip(delta2)
    }
  }
}

func predFunc4VE(_ z: inout VP8Decoder, _ y: Int, _ x: Int) {
  let a = Int32(z.ybr[y - 1][x - 1])
  let b = Int32(z.ybr[y - 1][x + 0])
  let c = Int32(z.ybr[y - 1][x + 1])
  let d = Int32(z.ybr[y - 1][x + 2])
  let e = Int32(z.ybr[y - 1][x + 3])
  let f = Int32(z.ybr[y - 1][x + 4])

  let col0 = UInt8((a + 2 * b + c + 2) >> 2)
  let col1 = UInt8((b + 2 * c + d + 2) >> 2)
  let col2 = UInt8((c + 2 * d + e + 2) >> 2)
  let col3 = UInt8((d + 2 * e + f + 2) >> 2)

  for j in 0..<4 {
    z.ybr[y + j][x + 0] = col0
    z.ybr[y + j][x + 1] = col1
    z.ybr[y + j][x + 2] = col2
    z.ybr[y + j][x + 3] = col3
  }
}

func predFunc4HE(_ z: inout VP8Decoder, _ y: Int, _ x: Int) {
  let s = Int32(z.ybr[y + 3][x - 1])
  let r = Int32(z.ybr[y + 2][x - 1])
  let q = Int32(z.ybr[y + 1][x - 1])
  let p = Int32(z.ybr[y + 0][x - 1])
  let a = Int32(z.ybr[y - 1][x - 1])

  let ssr = UInt8((s + 2*s + r + 2) >> 2)
  let srq = UInt8((s + 2*r + q + 2) >> 2)
  let rqp = UInt8((r + 2*q + p + 2) >> 2)
  let apq = UInt8((a + 2*p + q + 2) >> 2)

  for i in 0..<4 {
    z.ybr[y + 0][x + i] = apq
    z.ybr[y + 1][x + i] = rqp
    z.ybr[y + 2][x + i] = srq
    z.ybr[y + 3][x + i] = ssr
  }
}

func predFunc4RD(_ z: inout VP8Decoder, _ y: Int, _ x: Int) {
  let s = Int32(z.ybr[y + 3][x - 1])
  let r = Int32(z.ybr[y + 2][x - 1])
  let q = Int32(z.ybr[y + 1][x - 1])
  let p = Int32(z.ybr[y + 0][x - 1])

  let a = Int32(z.ybr[y - 1][x - 1])
  let b = Int32(z.ybr[y - 1][x + 0])
  let c = Int32(z.ybr[y - 1][x + 1])
  let d = Int32(z.ybr[y - 1][x + 2])
  let e = Int32(z.ybr[y - 1][x + 3])

  @inline(__always) func avg(_ u: Int32, _ v: Int32, _ w: Int32) -> UInt8 {
    return UInt8((u + 2*v + w + 2) >> 2)
  }

  let srq = avg(s, r, q)
  let rqp = avg(r, q, p)
  let qpa = avg(q, p, a)
  let pab = avg(p, a, b)
  let abc = avg(a, b, c)
  let bcd = avg(b, c, d)
  let cde = avg(c, d, e)

  z.ybr[y + 0][x + 0] = pab
  z.ybr[y + 0][x + 1] = abc
  z.ybr[y + 0][x + 2] = bcd
  z.ybr[y + 0][x + 3] = cde

  z.ybr[y + 1][x + 0] = qpa
  z.ybr[y + 1][x + 1] = pab
  z.ybr[y + 1][x + 2] = abc
  z.ybr[y + 1][x + 3] = bcd

  z.ybr[y + 2][x + 0] = rqp
  z.ybr[y + 2][x + 1] = qpa
  z.ybr[y + 2][x + 2] = pab
  z.ybr[y + 2][x + 3] = abc

  z.ybr[y + 3][x + 0] = srq
  z.ybr[y + 3][x + 1] = rqp
  z.ybr[y + 3][x + 2] = qpa
  z.ybr[y + 3][x + 3] = pab
}

func predFunc4VR(_ z: inout VP8Decoder, _ y: Int, _ x: Int) {
  let r = Int32(z.ybr[y + 2][x - 1])
  let q = Int32(z.ybr[y + 1][x - 1])
  let p = Int32(z.ybr[y + 0][x - 1])

  let a = Int32(z.ybr[y - 1][x - 1])
  let b = Int32(z.ybr[y - 1][x + 0])
  let c = Int32(z.ybr[y - 1][x + 1])
  let d = Int32(z.ybr[y - 1][x + 2])
  let e = Int32(z.ybr[y - 1][x + 3])

  let ab = UInt8((a + b + 1) >> 1)
  let bc = UInt8((b + c + 1) >> 1)
  let cd = UInt8((c + d + 1) >> 1)
  let de = UInt8((d + e + 1) >> 1)

  let rqp = UInt8((r + 2*q + p + 2) >> 2)
  let qpa = UInt8((q + 2*p + a + 2) >> 2)
  let pab = UInt8((p + 2*a + b + 2) >> 2)
  let abc = UInt8((a + 2*b + c + 2) >> 2)
  let bcd = UInt8((b + 2*c + d + 2) >> 2)
  let cde = UInt8((c + 2*d + e + 2) >> 2)

  z.ybr[y + 0][x + 0] = ab
  z.ybr[y + 0][x + 1] = bc
  z.ybr[y + 0][x + 2] = cd
  z.ybr[y + 0][x + 3] = de

  z.ybr[y + 1][x + 0] = pab
  z.ybr[y + 1][x + 1] = abc
  z.ybr[y + 1][x + 2] = bcd
  z.ybr[y + 1][x + 3] = cde

  z.ybr[y + 2][x + 0] = qpa
  z.ybr[y + 2][x + 1] = ab
  z.ybr[y + 2][x + 2] = bc
  z.ybr[y + 2][x + 3] = cd

  z.ybr[y + 3][x + 0] = rqp
  z.ybr[y + 3][x + 1] = pab
  z.ybr[y + 3][x + 2] = abc
  z.ybr[y + 3][x + 3] = bcd
}

@inline(__always)
private func avg(_ u: Int32, _ v: Int32, _ w: Int32) -> UInt8 {
  UInt8((u + 2*v + w + 2) >> 2)
}

func predFunc4LD(_ z: inout VP8Decoder, _ y: Int, _ x: Int) {
  let a = Int32(z.ybr[y - 1][x + 0])
  let b = Int32(z.ybr[y - 1][x + 1])
  let c = Int32(z.ybr[y - 1][x + 2])
  let d = Int32(z.ybr[y - 1][x + 3])
  let e = Int32(z.ybr[y - 1][x + 4])
  let f = Int32(z.ybr[y - 1][x + 5])
  let g = Int32(z.ybr[y - 1][x + 6])
  let h = Int32(z.ybr[y - 1][x + 7])

  let abc = avg(a, b, c)
  let bcd = avg(b, c, d)
  let cde = avg(c, d, e)
  let def = avg(d, e, f)
  let efg = avg(e, f, g)
  let fgh = avg(f, g, h)
  let ghh = UInt8((g + 3*h + 2) >> 2)

  z.ybr[y + 0][x + 0] = abc
  z.ybr[y + 0][x + 1] = bcd
  z.ybr[y + 0][x + 2] = cde
  z.ybr[y + 0][x + 3] = def

  z.ybr[y + 1][x + 0] = bcd
  z.ybr[y + 1][x + 1] = cde
  z.ybr[y + 1][x + 2] = def
  z.ybr[y + 1][x + 3] = efg

  z.ybr[y + 2][x + 0] = cde
  z.ybr[y + 2][x + 1] = def
  z.ybr[y + 2][x + 2] = efg
  z.ybr[y + 2][x + 3] = fgh

  z.ybr[y + 3][x + 0] = def
  z.ybr[y + 3][x + 1] = efg
  z.ybr[y + 3][x + 2] = fgh
  z.ybr[y + 3][x + 3] = ghh
}

@inline(__always)
private func avgHalf(_ u: Int32, _ v: Int32) -> UInt8 {
  UInt8((u + v + 1) >> 1)                 // (u + v + 1) / 2
}

@inline(__always)
private func avgQuarter(_ u: Int32, _ v: Int32, _ w: Int32) -> UInt8 {
  UInt8((u + 2*v + w + 2) >> 2)           // (u + 2v + w + 2) / 4
}

func predFunc4VL(_ z: inout VP8Decoder, _ y: Int, _ x: Int) {
  let a = Int32(z.ybr[y - 1][x + 0])
  let b = Int32(z.ybr[y - 1][x + 1])
  let c = Int32(z.ybr[y - 1][x + 2])
  let d = Int32(z.ybr[y - 1][x + 3])
  let e = Int32(z.ybr[y - 1][x + 4])
  let f = Int32(z.ybr[y - 1][x + 5])
  let g = Int32(z.ybr[y - 1][x + 6])
  let h = Int32(z.ybr[y - 1][x + 7])

  let ab  = avgHalf(a, b)
  let bc  = avgHalf(b, c)
  let cd  = avgHalf(c, d)
  let de  = avgHalf(d, e)

  let abc = avgQuarter(a, b, c)
  let bcd = avgQuarter(b, c, d)
  let cde = avgQuarter(c, d, e)
  let def = avgQuarter(d, e, f)
  let efg = avgQuarter(e, f, g)
  let fgh = avgQuarter(f, g, h)

  z.ybr[y + 0][x + 0] = ab
  z.ybr[y + 0][x + 1] = bc
  z.ybr[y + 0][x + 2] = cd
  z.ybr[y + 0][x + 3] = de

  z.ybr[y + 1][x + 0] = abc
  z.ybr[y + 1][x + 1] = bcd
  z.ybr[y + 1][x + 2] = cde
  z.ybr[y + 1][x + 3] = def

  z.ybr[y + 2][x + 0] = bc
  z.ybr[y + 2][x + 1] = cd
  z.ybr[y + 2][x + 2] = de
  z.ybr[y + 2][x + 3] = efg

  z.ybr[y + 3][x + 0] = bcd
  z.ybr[y + 3][x + 1] = cde
  z.ybr[y + 3][x + 2] = def
  z.ybr[y + 3][x + 3] = fgh
}

func predFunc4HD(_ z: inout VP8Decoder, _ y: Int, _ x: Int) {
  let s = Int32(z.ybr[y + 3][x - 1])
  let r = Int32(z.ybr[y + 2][x - 1])
  let q = Int32(z.ybr[y + 1][x - 1])
  let p = Int32(z.ybr[y + 0][x - 1])

  let a = Int32(z.ybr[y - 1][x - 1])
  let b = Int32(z.ybr[y - 1][x + 0])
  let c = Int32(z.ybr[y - 1][x + 1])
  let d = Int32(z.ybr[y - 1][x + 2])

  let sr = avgHalf(s, r)
  let rq = avgHalf(r, q)
  let qp = avgHalf(q, p)
  let pa = avgHalf(p, a)

  let srq = avgQuarter(s, r, q)
  let rqp = avgQuarter(r, q, p)
  let qpa = avgQuarter(q, p, a)
  let pab = avgQuarter(p, a, b)
  let abc = avgQuarter(a, b, c)
  let bcd = avgQuarter(b, c, d)

  z.ybr[y + 0][x + 0] = pa
  z.ybr[y + 0][x + 1] = pab
  z.ybr[y + 0][x + 2] = abc
  z.ybr[y + 0][x + 3] = bcd

  z.ybr[y + 1][x + 0] = qp
  z.ybr[y + 1][x + 1] = qpa
  z.ybr[y + 1][x + 2] = pa
  z.ybr[y + 1][x + 3] = pab

  z.ybr[y + 2][x + 0] = rq
  z.ybr[y + 2][x + 1] = rqp
  z.ybr[y + 2][x + 2] = qp
  z.ybr[y + 2][x + 3] = qpa

  z.ybr[y + 3][x + 0] = sr
  z.ybr[y + 3][x + 1] = srq
  z.ybr[y + 3][x + 2] = rq
  z.ybr[y + 3][x + 3] = rqp
}

func predFunc4HU(_ z: inout VP8Decoder, _ y: Int, _ x: Int) {
  let s = Int32(z.ybr[y + 3][x - 1])
  let r = Int32(z.ybr[y + 2][x - 1])
  let q = Int32(z.ybr[y + 1][x - 1])
  let p = Int32(z.ybr[y + 0][x - 1])

  let pq  = avgHalf(p, q)
  let qr  = avgHalf(q, r)
  let rs  = avgHalf(r, s)

  let pqr = avgQuarter(p, q, r)
  let qrs = avgQuarter(q, r, s)
  let rss = UInt8((r + 3*s + 2) >> 2)

  let sss = UInt8(s)

  z.ybr[y + 0][x + 0] = pq
  z.ybr[y + 0][x + 1] = pqr
  z.ybr[y + 0][x + 2] = qr
  z.ybr[y + 0][x + 3] = qrs

  z.ybr[y + 1][x + 0] = qr
  z.ybr[y + 1][x + 1] = qrs
  z.ybr[y + 1][x + 2] = rs
  z.ybr[y + 1][x + 3] = rss

  z.ybr[y + 2][x + 0] = rs
  z.ybr[y + 2][x + 1] = rss
  z.ybr[y + 2][x + 2] = sss
  z.ybr[y + 2][x + 3] = sss

  z.ybr[y + 3][x + 0] = sss
  z.ybr[y + 3][x + 1] = sss
  z.ybr[y + 3][x + 2] = sss
  z.ybr[y + 3][x + 3] = sss
}

func predFunc8DC(_ z: inout VP8Decoder, _ y: Int, _ x: Int) {
  var sum: UInt32 = 8
  for i in 0..<8 {
    sum += UInt32(z.ybr[y - 1][x + i])
  }
  for j in 0..<8 {
    sum += UInt32(z.ybr[y + j][x - 1])
  }
  let avg = UInt8(sum >> 4)
  for j in 0..<8 {
    for i in 0..<8 {
      z.ybr[y + j][x + i] = avg
    }
  }
}

func predFunc8TM(_ z: inout VP8Decoder, _ y: Int, _ x: Int) {
  let minusTL = -Int32(z.ybr[y - 1][x - 1])
  for j in 0..<8 {
    let delta1 = minusTL + Int32(z.ybr[y + j][x - 1])
    for i in 0..<8 {
      let delta2 = delta1 + Int32(z.ybr[y - 1][x + i])
      z.ybr[y + j][x + i] = clip(delta2)
    }
  }
}

func predFunc8VE(_ z: inout VP8Decoder, _ y: Int, _ x: Int) {
  for j in 0..<8 {
    for i in 0..<8 {
      z.ybr[y + j][x + i] = z.ybr[y - 1][x + i]
    }
  }
}

func predFunc8HE(_ z: inout VP8Decoder, _ y: Int, _ x: Int) {
  for j in 0..<8 {
    let v = z.ybr[y + j][x - 1]
    for i in 0..<8 { z.ybr[y + j][x + i] = v }
  }
}

func predFunc8DCTop(_ z: inout VP8Decoder, _ y: Int, _ x: Int) {
  var sum: UInt32 = 4
  for j in 0..<8 {
    sum += UInt32(z.ybr[y + j][x - 1])
  } // only left column
  let avg = UInt8(sum >> 3)
  for j in 0..<8 {
    for i in 0..<8 {
      z.ybr[y + j][x + i] = avg
    }
  }
}

func predFunc8DCLeft(_ z: inout VP8Decoder, _ y: Int, _ x: Int) {
  var sum: UInt32 = 4
  for i in 0..<8 {
    sum += UInt32(z.ybr[y - 1][x + i])
  } // only top row
  let avg = UInt8(sum >> 3)
  for j in 0..<8 {
    for i in 0..<8 {
      z.ybr[y + j][x + i] = avg
    }
  }
}

func predFunc8DCTopLeft(_ z: inout VP8Decoder, _ y: Int, _ x: Int) {
  for j in 0..<8 {
    for i in 0..<8 {
      z.ybr[y + j][x + i] = 0x80
    }
  }
}

func predFunc16DC(_ z: inout VP8Decoder, _ y: Int, _ x: Int) {
  var sum: UInt32 = 16
  for i in 0..<16 {
    sum += UInt32(z.ybr[y - 1][x + i])
  }
  for j in 0..<16 {
    sum += UInt32(z.ybr[y + j][x - 1])
  }
  let avg = UInt8(sum >> 5)
  for j in 0..<16 {
    for i in 0..<16 {
      z.ybr[y + j][x + i] = avg
    }
  }
}

func predFunc16TM(_ z: inout VP8Decoder, _ y: Int, _ x: Int) {
  let minusTL = -Int32(z.ybr[y - 1][x - 1])
  for j in 0..<16 {
    let delta1 = minusTL + Int32(z.ybr[y + j][x - 1])
    for i in 0..<16 {
      let delta2 = delta1 + Int32(z.ybr[y - 1][x + i])
      z.ybr[y + j][x + i] = clip(delta2)
    }
  }
}

func predFunc16VE(_ z: inout VP8Decoder, _ y: Int, _ x: Int) {
  for j in 0..<16 {
    for i in 0..<16 {
      z.ybr[y + j][x + i] = z.ybr[y - 1][x + i]
    }
  }
}

func predFunc16HE(_ z: inout VP8Decoder, _ y: Int, _ x: Int) {
  for j in 0..<16 {
    let v = z.ybr[y + j][x - 1]
    for i in 0..<16 {
      z.ybr[y + j][x + i] = v
    }
  }
}

func predFunc16DCTop(_ z: inout VP8Decoder, _ y: Int, _ x: Int) {
  var sum: UInt32 = 8
  for j in 0..<16 {
    sum += UInt32(z.ybr[y + j][x - 1])
  }  // left column only
  let avg = UInt8(sum >> 4)
  for j in 0..<16 {
    for i in 0..<16 {
      z.ybr[y + j][x + i] = avg
    }
  }
}

func predFunc16DCLeft(_ z: inout VP8Decoder, _ y: Int, _ x: Int) {
  var sum: UInt32 = 8
  for i in 0..<16 {
    sum += UInt32(z.ybr[y - 1][x + i])
  }  // top row only
  let avg = UInt8(sum >> 4)
  for j in 0..<16 {
    for i in 0..<16 {
      z.ybr[y + j][x + i] = avg
    }
  }
}

func predFunc16DCTopLeft(_ z: inout VP8Decoder, _ y: Int, _ x: Int) {
  for j in 0..<16 {
    for i in 0..<16 {
      z.ybr[y + j][x + i] = 0x80
    }
  }
}
