import Foundation
import CoreGraphics

extension FixedWidthInteger {
  @inline(__always)
  func clamped(to range: ClosedRange<Self>) -> Self {
    return self < range.lowerBound ? range.lowerBound
    : self > range.upperBound ? range.upperBound
    : self
  }
}

enum YCbCrSubsampleRatio {
  case sub444
  case sub422
  case sub420
  case sub440
  case sub411
  case sub410
}

struct YCbCrPixel { var y, cb, cr: UInt8 }
struct RGBA64Pixel { var r, g, b, a: UInt16 }

struct YCbCrImage {
  var Y: [UInt8]
  var Cb: [UInt8]
  var Cr: [UInt8]

  var YStride: Int
  var CStride: Int

  var subsampleRatio: YCbCrSubsampleRatio
  var rect: CGRect

  init(Y: [UInt8], Cb: [UInt8], Cr: [UInt8], YStride: Int, CStride: Int, subsampleRatio: YCbCrSubsampleRatio, rect: CGRect) {
    self.Y = Y
    self.Cb = Cb
    self.Cr = Cr
    self.YStride = YStride
    self.CStride = CStride
    self.subsampleRatio = subsampleRatio
    self.rect = rect
  }

  func makeRGBA() -> [UInt8] {
    let w  = Int(rect.width.rounded(.towardZero))
    let h  = Int(rect.height.rounded(.towardZero))
    var out = [UInt8](repeating: 0, count: w * h * 4)

    @inline(__always)
    func yIndex(_ x: Int, _ y: Int) -> Int {
      return (y - Int(rect.minY)) * YStride + (x - Int(rect.minX))
    }

    @inline(__always)
    func cIndex(_ x: Int, _ y: Int) -> Int {
      switch subsampleRatio {
      case .sub444:
        return (y - Int(rect.minY)) * CStride + (x - Int(rect.minX))
      case .sub422:
        return (y - Int(rect.minY)) * CStride + (x >> 1  - Int(rect.minX) >> 1)
      case .sub420:
        return (y >> 1 - Int(rect.minY) >> 1) * CStride + (x >> 1  - Int(rect.minX) >> 1)
      case .sub440:
        return (y >> 1 - Int(rect.minY) >> 1) * CStride + (x - Int(rect.minX))
      case .sub411:
        return (y - Int(rect.minY)) * CStride + (x >> 2 - Int(rect.minX) >> 2)
      case .sub410:
        return (y >> 1 - Int(rect.minY) >> 1) * CStride + (x >> 2 - Int(rect.minX) >> 2)
      @unknown default: // Fallback to 4:4:4
        return (y - Int(rect.minY)) * CStride + (x - Int(rect.minX))
      }
    }

    for y in 0..<h {
      for x in 0..<w {
        let Yval = Int(Y[yIndex(x, y)])
        let Cbval = Int(Cb[cIndex(x, y)])
        let Crval = Int(Cr[cIndex(x, y)])

        let c = Yval - 16
        let d = Cbval - 128
        let e = Crval - 128

        var r = (298 * c + 409 * e + 128) >> 8
        var g = (298 * c - 100 * d - 208 * e + 128) >> 8
        var b = (298 * c + 516 * d + 128) >> 8

        r = r.clamped(to: 0...255)
        g = g.clamped(to: 0...255)
        b = b.clamped(to: 0...255)

        let dst = 4 * (y * w + x)
        out[dst + 0] = UInt8(r)  // R
        out[dst + 1] = UInt8(g)  // G
        out[dst + 2] = UInt8(b)  // B
        out[dst + 3] = 255       // A (opaque)
      }
    }
    return out
  }

  init(_ r: CGRect, subsampleRatio ss: YCbCrSubsampleRatio) {
    let (w, h, cw, ch) = yCbCrSize(r, subsampleRatio: ss)

    let totalLength = add2NonNeg(
      mul3NonNeg(1, w,  h),
      mul3NonNeg(2, cw, ch)
    )
    guard totalLength >= 0 else {
      fatalError("image: NewYCbCr Rectangle has huge or negative dimensions")
    }

    let i0 = w * h
    let i1 = i0 + cw * ch
    let i2 = i1 + cw * ch

    let buf = [UInt8](repeating: 0, count: i2)

    let ySlice  = Array(buf[0 ..< i0])
    let cbSlice = Array(buf[i0 ..< i1])
    let crSlice = Array(buf[i1 ..< i2])

    self.Y = ySlice
    self.Cb = cbSlice
    self.Cr = crSlice
    self.YStride = w
    self.CStride = cw
    self.subsampleRatio = ss
    self.rect = r
  }

  @inline(__always)
  func yOffset(_ x: Int, _ y: Int) -> Int {
    return y * YStride + x
  }

  @inline(__always)
  func cOffset(_ x: Int, _ y: Int) -> Int {
    switch subsampleRatio {
    case .sub444:
      return y * CStride + x
    case .sub422:
      return y * CStride + (x >> 1)
    case .sub420:
      return (y >> 1) * CStride + (x >> 1)
    case .sub440:
      return (y >> 1) * CStride + x
    case .sub411:
      return y * CStride + (x >> 2)
    case .sub410:
      return (y >> 1) * CStride + (x >> 2)
    }
  }

  func ycbcrAt(x: Int, y: Int) -> YCbCrPixel {
    guard rect.contains(CGPoint(x: x, y: y)) else { return .init(y: 0, cb: 0, cr: 0) }
    let yi = yOffset(x, y)
    let ci = cOffset(x, y)
    return YCbCrPixel(y: Y[yi], cb: Cb[ci], cr: Cr[ci])
  }

  func rgba64At(x: Int, y: Int) -> RGBA64Pixel {
    let p = ycbcrAt(x: x, y: y)
    let c = Double(Int(p.cb) - 128)
    let d = Double(Int(p.cr) - 128)
    let yD = Double(p.y)

    var r = yD + 1.402 * d
    var g = yD - 0.344136 * c - 0.714136 * d
    var b = yD + 1.772 * c

    r = min(max(r, 0), 255)
    g = min(max(g, 0), 255)
    b = min(max(b, 0), 255)

    return RGBA64Pixel(
      r: UInt16(r) << 8,
      g: UInt16(g) << 8,
      b: UInt16(b) << 8,
      a: 0xffff
    )
  }

  @inline(__always)
  func yOffset(x: Int, y: Int) -> Int {
    return (y - Int(rect.minY)) * YStride + (x - Int(rect.minX))
  }

  @inline(__always)
  func cOffset(x: Int, y: Int) -> Int {
    switch subsampleRatio {
    case .sub422:
      return (y - Int(rect.minY)) * CStride
      + (x >> 1) - (Int(rect.minX) >> 1)
    case .sub420:
      return ((y >> 1) - (Int(rect.minY) >> 1)) * CStride
      + (x >> 1) - (Int(rect.minX) >> 1)
    case .sub440:
      return ((y >> 1) - (Int(rect.minY) >> 1)) * CStride
      +  x       -  Int(rect.minX)
    case .sub411:
      return (y - Int(rect.minY)) * CStride
      + (x >> 2) - (Int(rect.minX) >> 2)
    case .sub410:
      return ((y >> 1) - (Int(rect.minY) >> 1)) * CStride
      + (x >> 2) - (Int(rect.minX) >> 2)
    default:
      return (y - Int(rect.minY)) * CStride + (x - Int(rect.minX))
    }
  }

  func subImage(_ r: CGRect) -> YCbCrImage {
    let clipped = r.intersection(rect)

    guard !clipped.isEmpty else {
      return YCbCrImage(
        Y: [],
        Cb: [],
        Cr: [],
        YStride: YStride,
        CStride: CStride,
        subsampleRatio: subsampleRatio,
        rect: clipped
      )
    }

    let yOffset = yOffset(x: Int(clipped.minX), y: Int(clipped.minY))
    let cOffset = cOffset(x: Int(clipped.minX), y: Int(clipped.minY))

    let yView  = Y[yOffset...]
    let cbView = Cb[cOffset...]
    let crView = Cr[cOffset...]

    return YCbCrImage(
      Y: [UInt8](yView),
      Cb: [UInt8](cbView),
      Cr: [UInt8](crView),
      YStride: YStride,
      CStride: CStride,
      subsampleRatio: subsampleRatio,
      rect: clipped
    )
  }

  var isOpaque: Bool { true }
}

@inline(__always)
func yCbCrSize(
  _ r: CGRect,
  subsampleRatio ss: YCbCrSubsampleRatio
) -> (w: Int, h: Int, cw: Int, ch: Int) {
  let w = r.width
  let h = r.height

  switch ss {
  case .sub422:
    let cw =  (r.maxX + 1) / 2 - r.minX / 2
    return (Int(w), Int(h), Int(cw), Int(h))
  case .sub420:
    let cw =  (r.maxX + 1) / 2 - r.minX / 2
    let ch =  (r.maxY + 1) / 2 - r.minY / 2
    return (Int(w), Int(h), Int(cw), Int(ch))
  case .sub440:
    let ch =  (r.maxY + 1) / 2 - r.minY / 2
    return (Int(w), Int(h), Int(w), Int(ch))
  case .sub411:
    let cw =  (r.maxX + 3) / 4 - r.minX / 4
    return (Int(w), Int(h), Int(cw), Int(h))
  case .sub410:
    let cw =  (r.maxX + 3) / 4 - r.minX / 4
    let ch =  (r.maxY + 1) / 2 - r.minY / 2
    return (Int(w), Int(h), Int(cw), Int(ch))
  default:
    return (Int(w), Int(h), Int(w), Int(h))
  }
}

@inline(__always)
func add2NonNeg(_ x: Int, _ y: Int) -> Int {
  guard x >= 0, y >= 0 else {
    return -1
  }

  let (sum, overflow) = x.addingReportingOverflow(y)
  return overflow ? -1 : sum
}

@inline(__always)
func mul3NonNeg(_ x: Int, _ y: Int, _ z: Int) -> Int {
  guard x >= 0, y >= 0, z >= 0 else { return -1 }

  let (prod1, overflow1) = x.multipliedReportingOverflow(by: y)
  guard !overflow1 else {
    return -1
  }

  let (prod2, overflow2) = prod1.multipliedReportingOverflow(by: z)
  guard !overflow2 else {
    return -1
  }

  return prod2
}
