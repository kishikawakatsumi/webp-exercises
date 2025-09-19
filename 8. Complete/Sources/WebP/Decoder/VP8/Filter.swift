import Foundation

@inline(__always)
func absInt(_ x: Int) -> Int {
  let m = x >> (Int.bitWidth - 1)
  return (x ^ m) &- m
}

@inline(__always)
func clamp15(_ x: Int) -> Int {
  if x < -16 { return -16 }
  if x >  15 { return  15 }
  return x
}

@inline(__always)
func clamp127(_ x: Int) -> Int {
  if x < -128 { return -128 }
  if x >  127 { return  127 }
  return x
}

@inline(__always)
func clamp255(_ x: Int) -> UInt8 {
  if x <   0 { return 0 }
  if x > 255 { return 255 }
  return UInt8(x)
}

@inline(__always)
func filter2(
  pix: inout [UInt8],
  level: Int,
  index start: Int,
  iStep: Int,
  jStep: Int) {
    var idx = start
    for _ in 0..<16 {

      let p1 = Int(pix[idx - 2 * jStep])
      let p0 = Int(pix[idx - 1 * jStep])
      let q0 = Int(pix[idx + 0 * jStep])
      let q1 = Int(pix[idx + 1 * jStep])

      if (abs(p0 - q0) << 1) + (abs(p1 - q1) >> 1) <= level {

        let a  = 3 * (q0 - p0) + clamp127(p1 - q1)
        let a1 = clamp15((a + 4) >> 3)
        let a2 = clamp15((a + 3) >> 3)

        pix[idx - 1 * jStep] = clamp255(p0 + a2)
        pix[idx + 0 * jStep] = clamp255(q0 - a1)
      }

      idx += iStep
    }
  }

func filter246(
  pix: inout [UInt8],
  n: Int,
  level: Int,
  ilevel: Int,
  hlevel: Int,
  index start: Int,
  iStep: Int,
  jStep: Int,
  fourNotSix: Bool)
{
  var count = n
  var index = start
  while count > 0 {
    count -= 1

    let p3 = Int(pix[index - 4 * jStep])
    let p2 = Int(pix[index - 3 * jStep])
    let p1 = Int(pix[index - 2 * jStep])
    let p0 = Int(pix[index - 1 * jStep])
    let q0 = Int(pix[index + 0 * jStep])
    let q1 = Int(pix[index + 1 * jStep])
    let q2 = Int(pix[index + 2 * jStep])
    let q3 = Int(pix[index + 3 * jStep])

    if (abs(p0 - q0) << 1) + (abs(p1 - q1) >> 1) > level {
      index += iStep
      continue
    }

    if abs(p3 - p2) > ilevel ||
        abs(p2 - p1) > ilevel ||
        abs(p1 - p0) > ilevel ||
        abs(q1 - q0) > ilevel ||
        abs(q2 - q1) > ilevel ||
        abs(q3 - q2) > ilevel {
      index += iStep
      continue
    }

    if abs(p1 - p0) > hlevel || abs(q1 - q0) > hlevel {
      let a = 3 * (q0 - p0) + clamp127(p1 - q1)
      let a1 = clamp15((a + 4) >> 3)
      let a2 = clamp15((a + 3) >> 3)
      pix[index - 1 * jStep] = clamp255(p0 + a2)
      pix[index + 0 * jStep] = clamp255(q0 - a1)

    } else if fourNotSix {
      let a = 3 * (q0 - p0)
      let a1 = clamp15((a + 4) >> 3)
      let a2 = clamp15((a + 3) >> 3)
      let a3 = (a1 + 1) >> 1
      pix[index - 2 * jStep] = clamp255(p1 + a3)
      pix[index - 1 * jStep] = clamp255(p0 + a2)
      pix[index + 0 * jStep] = clamp255(q0 - a1)
      pix[index + 1 * jStep] = clamp255(q1 - a3)
    } else {
      let a = clamp127(3 * (q0 - p0) + clamp127(p1 - q1))
      let a1 = (27 * a + 63) >> 7
      let a2 = (18 * a + 63) >> 7
      let a3 = (9 * a + 63) >> 7
      pix[index - 3 * jStep] = clamp255(p2 + a3)
      pix[index - 2 * jStep] = clamp255(p1 + a2)
      pix[index - 1 * jStep] = clamp255(p0 + a1)
      pix[index + 0 * jStep] = clamp255(q0 - a1)
      pix[index + 1 * jStep] = clamp255(q1 - a2)
      pix[index + 2 * jStep] = clamp255(q2 - a3)
    }

    index += iStep
  }
}

extension VP8Decoder {

  mutating func simpleFilter() {
    var Y = img.Y

    let stride = img.YStride

    for mby in 0..<mbh {
      for mbx in 0..<mbw {

        let fp = perMBFilterParams[mbw * mby + mbx]
        guard fp.level != 0 else {
          continue
        }

        let L = Int(fp.level)
        let yIndex = (mby * stride + mbx) * 16

        if mbx > 0 {
          filter2(pix: &Y,
                  level: L + 4,
                  index: yIndex,
                  iStep: stride,
                  jStep: 1)
        }

        if fp.inner {
          filter2(pix: &Y, level: L, index: yIndex + 0x4, iStep: stride, jStep: 1)
          filter2(pix: &Y, level: L, index: yIndex + 0x8, iStep: stride, jStep: 1)
          filter2(pix: &Y, level: L, index: yIndex + 0xc, iStep: stride, jStep: 1)
        }

        if mby > 0 {
          filter2(
            pix: &Y,
            level: L + 4,
            index: yIndex,
            iStep: 1,
            jStep: stride
          )
        }

        if fp.inner {
          filter2(
            pix: &Y, level: L,
            index: yIndex + stride * 0x4,
            iStep: 1,
            jStep: stride
          )
          filter2(
            pix: &Y, level: L,
            index: yIndex + stride * 0x8,
            iStep: 1,
            jStep: stride
          )
          filter2(
            pix: &Y, level: L,
            index: yIndex + stride * 0xc,
            iStep: 1,
            jStep: stride
          )
        }
      }
    }

    img.Y = Y
  }
}

extension VP8Decoder {
  mutating func normalFilter() {
    var Y  = img.Y          // luma plane (copy-on-write)
    var Cb = img.Cb         // chroma B
    var Cr = img.Cr         // chroma R

    let yStride = img.YStride
    let cStride = img.CStride

    for mby in 0..<mbh {
      for mbx in 0..<mbw {

        let f = perMBFilterParams[mbw * mby + mbx]
        if f.level == 0 {
          continue
        }

        let l = Int(f.level)
        let il = Int(f.ilevel)
        let hl = Int(f.hlevel)

        let yIndex = (mby * yStride + mbx) * 16
        let cIndex = (mby * cStride + mbx) * 8

        if mbx > 0 {
          filter246(
            pix: &Y , n: 16, level: l+4, ilevel: il, hlevel: hl,
            index: yIndex, iStep: yStride, jStep: 1, fourNotSix: false
          )
          filter246(
            pix: &Cb, n:  8, level: l+4, ilevel: il, hlevel: hl,
            index: cIndex, iStep: cStride, jStep: 1, fourNotSix: false
          )
          filter246(
            pix: &Cr, n:  8, level: l+4, ilevel: il, hlevel: hl,
            index: cIndex, iStep: cStride, jStep: 1, fourNotSix: false
          )
        }
        if f.inner {
          filter246(
            pix: &Y , n: 16, level: l, ilevel: il, hlevel: hl,
            index: yIndex + 0x4, iStep: yStride, jStep: 1, fourNotSix: true
          )
          filter246(
            pix: &Y , n: 16, level: l, ilevel: il, hlevel: hl,
            index: yIndex + 0x8, iStep: yStride, jStep: 1, fourNotSix: true
          )
          filter246(
            pix: &Y , n: 16, level: l, ilevel: il, hlevel: hl,
            index: yIndex + 0xc, iStep: yStride, jStep: 1, fourNotSix: true
          )

          filter246(
            pix: &Cb, n:  8, level: l, ilevel: il, hlevel: hl,
            index: cIndex + 0x4, iStep: cStride, jStep: 1, fourNotSix: true
          )
          filter246(
            pix: &Cr, n:  8, level: l, ilevel: il, hlevel: hl,
            index: cIndex + 0x4, iStep: cStride, jStep: 1, fourNotSix: true
          )
        }

        if mby > 0 {
          filter246(
            pix: &Y , n: 16, level: l+4, ilevel: il, hlevel: hl,
            index: yIndex, iStep: 1, jStep: yStride, fourNotSix: false
          )
          filter246(
            pix: &Cb, n:  8, level: l+4, ilevel: il, hlevel: hl,
            index: cIndex, iStep: 1, jStep: cStride, fourNotSix: false
          )
          filter246(
            pix: &Cr, n:  8, level: l+4, ilevel: il, hlevel: hl,
            index: cIndex, iStep: 1, jStep: cStride, fourNotSix: false
          )
        }
        if f.inner {
          filter246(
            pix: &Y , n: 16, level: l, ilevel: il, hlevel: hl,
            index: yIndex + yStride*0x4, iStep: 1, jStep: yStride, fourNotSix: true
          )
          filter246(
            pix: &Y , n: 16, level: l, ilevel: il, hlevel: hl,
            index: yIndex + yStride*0x8, iStep: 1, jStep: yStride, fourNotSix: true
          )
          filter246(
            pix: &Y , n: 16, level: l, ilevel: il, hlevel: hl,
            index: yIndex + yStride*0xc, iStep: 1, jStep: yStride, fourNotSix: true
          )

          filter246(
            pix: &Cb, n:  8, level: l, ilevel: il, hlevel: hl,
            index: cIndex + cStride*0x4, iStep: 1, jStep: cStride, fourNotSix: true
          )
          filter246(
            pix: &Cr, n:  8, level: l, ilevel: il, hlevel: hl,
            index: cIndex + cStride*0x4, iStep: 1, jStep: cStride, fourNotSix: true
          )
        }
      }
    }

    img.Y  = Y
    img.Cb = Cb
    img.Cr = Cr
  }
}

struct FilterParam {
  var level: UInt8 = 0
  var ilevel: UInt8 = 0
  var hlevel: UInt8 = 0
  var inner: Bool = false
}

extension VP8Decoder {
  mutating func computeFilterParams() {
    for i in 0..<filterParams.count {
      var baseLevel = Int(filterHeader.level)

      if segmentHeader.useSegment {
        baseLevel = Int(segmentHeader.filterStrength[i])
        if segmentHeader.relativeDelta {
          baseLevel += Int(filterHeader.level)
        }
      }

      for j in 0..<filterParams[i].count {
        var p = filterParams[i][j]
        p.inner = (j != 0)

        var level = baseLevel
        if filterHeader.useLFDelta {
          level += Int(filterHeader.refLFDelta[0])
          if j != 0 {
            level += Int(filterHeader.modeLFDelta[0])
          }
        }

        guard level > 0 else {
          p.level = 0
          filterParams[i][j] = p
          continue
        }

        if level > 63 {
          level = 63
        }

        var ilevel = level
        if filterHeader.sharpness > 0 {
          if filterHeader.sharpness > 4 {
            ilevel >>= 2
          } else {
            ilevel >>= 1
          }
          let maxI = Int(9 - filterHeader.sharpness)
          if ilevel > maxI {
            ilevel = maxI
          }
        }
        if ilevel < 1 {
          ilevel = 1
        }

        p.ilevel = UInt8(ilevel)
        p.level  = UInt8(2 * level + ilevel)

        if frameHeader.keyFrame {
          switch level {
          case ..<15:  p.hlevel = 0
          case ..<40:  p.hlevel = 1
          default:     p.hlevel = 2
          }
        } else {
          switch level {
          case ..<15:  p.hlevel = 0
          case ..<20:  p.hlevel = 1
          case ..<40:  p.hlevel = 2
          default:     p.hlevel = 3
          }
        }

        filterParams[i][j] = p
      }
    }
  }
}
