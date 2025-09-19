import Foundation
import CoreGraphics
import ImageIO

public struct WebPDecoder {
  public static func decode(_ data: Data) throws -> Image {
    let (formType, reader) = try RIFFReader.makeReader(from: data)

    guard formType == .webp else {
      throw WebPError.invalidFormat
    }

    var wantAlpha = false
    var seenVP8X = false
    var alphaPixels: [UInt8]? = nil
    var alphaStride = 0
    var widthMinusOne: UInt32 = 0
    var heightMinusOne: UInt32 = 0

    while true {
      let (chunkID, chunkLen): (FourCC, UInt32)
      do {
        (chunkID, chunkLen) = try reader.next()
      } catch is EOFError {
        throw WebPError.invalidFormat
      }

      func slurpChunk(_ len: UInt32, _ s: RIFFReader) throws -> Data {
        var buf = [UInt8](repeating: 0, count: Int(len))
        let n = s.read(&buf, maxLength: buf.count)
        guard n == buf.count else { throw WebPError.invalidFormat }
        return Data(buf)
      }

      switch chunkID {
      case .alph:
        guard wantAlpha else {
          throw WebPError.invalidFormat
        }
        wantAlpha = false

        guard let ctrl = reader.readByte() else {
          throw WebPError.invalidFormat
        }

        let (rawAlpha, stride) = try readAlpha(
          reader, widthMinusOne: widthMinusOne, heightMinusOne: heightMinusOne, compression: ctrl & 0x03
        )
        alphaPixels = rawAlpha
        alphaStride = stride
        unfilterAlpha(&alphaPixels!, alphaStride, (ctrl >> 2) & 0x03)
      case .vp8:
        guard !wantAlpha else {
          throw WebPError.invalidFormat
        }

        var decoder = VP8Decoder()
        decoder.initStream(stream: reader, limit: Int(chunkLen))
        let header = try decoder.decodeFrameHeader()

        let image = try decoder.decodeFrame()
        if let alphaPixels {
          let subsample: Subsample
          switch image.subsampleRatio {
          case .sub444:
            subsample = .s444
          case .sub422:
            subsample = .s422
          case .sub420:
            subsample = .s420
          case .sub440:
            subsample = .s440
          case .sub411:
            subsample = .s411
          case .sub410:
            subsample = .s410
          }

          return Image(
            width: header.width,
            height: header.height,
            storage: .nycbcra(
              NYCbCrA420Buffer(
                ycbcr: YCbCr420Buffer(
                  y: image.Y,
                  cb: image.Cb,
                  cr: image.Cr,
                  yStride: image.YStride,
                  cStride: image.CStride,
                  subsample: subsample
                ),
                a: Data(alphaPixels),
                aStride: alphaStride
              )
            )
          )
        } else {
          let subsample: Subsample
          switch image.subsampleRatio {
          case .sub444:
            subsample = .s444
          case .sub422:
            subsample = .s422
          case .sub420:
            subsample = .s420
          case .sub440:
            subsample = .s440
          case .sub411:
            subsample = .s411
          case .sub410:
            subsample = .s410
          }

          return Image(
            width: header.width,
            height: header.height,
            storage: .ycbcr(
              YCbCr420Buffer(
                y: image.Y,
                cb: image.Cb,
                cr: image.Cr,
                yStride: image.YStride,
                cStride: image.CStride,
                subsample: subsample
              )
            )
          )
        }
      case .vp8l:
        guard !wantAlpha, alphaPixels == nil else {
          throw WebPError.invalidFormat
        }
        let losslessData = try slurpChunk(chunkLen, reader)

        var decoder = VP8LDecoder(data: losslessData)
        let img = try decoder.decode()

        let bytesPerPixel = 4
        let bytesPerRow = img.width * bytesPerPixel
        return Image(
          width: img.width,
          height: img.height,
          storage: .nrgba(
            NRGBABuffer(
              data: img.pixels,
              stride: bytesPerRow
            )
          )
        )
      case .vp8x:
        guard !seenVP8X else {
          throw WebPError.invalidFormat
        }
        seenVP8X = true
        guard chunkLen == 10 else {
          throw WebPError.invalidFormat
        }

        var hdr = [UInt8](repeating: 0, count: 10)
        let n = reader.read(&hdr, maxLength: 10)
        guard n == 10 else {
          throw WebPError.invalidFormat
        }

        let alphaBit  : UInt8 = 1 << 4
        wantAlpha = (hdr[0] & alphaBit) != 0

        widthMinusOne  = UInt32(hdr[4]) | UInt32(hdr[5]) << 8 | UInt32(hdr[6]) << 16
        heightMinusOne = UInt32(hdr[7]) | UInt32(hdr[8]) << 8 | UInt32(hdr[9]) << 16
      default:
        // Just skip it: Reader.next() already positioned `stream`.
        _ = try slurpChunk(chunkLen, reader)
      }
    }
  }
}

extension WebPDecoder {
  public struct Image {
    public let width: Int
    public let height: Int
    public let storage: Storage
    public let colorSpace: CGColorSpace?
    public let metadata: Metadata

    public init(
      width: Int,
      height: Int,
      storage: Storage,
      colorSpace: CGColorSpace? = nil,
      metadata: Metadata = .init()
    ) {
      self.width = width
      self.height = height
      self.storage = storage
      self.colorSpace = colorSpace
      self.metadata = metadata
    }

    public func withUnsafePlanes<R>(_ body: (Planes) throws -> R) rethrows -> R {
      switch storage {
      case .nrgba(let b):
        return try body(.nrgba(b))
      case .ycbcr(let y):
        return try body(.ycbcr(y))
      case .nycbcra(let a):
        return try body(.nycbcra(a))
      }
    }

    public func makeCGImage() -> CGImage? {
      switch storage {
      case .nrgba(let buffer):
        var pixels = buffer.data
        let channels = 4

        let data = CFDataCreate(nil, &pixels, width * height * channels)!
        let dataProvider = CGDataProvider(data: data)!
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.last.rawValue
        let image = CGImage(
          width: width,
          height: height,
          bitsPerComponent: 8,
          bitsPerPixel: 8 * channels,
          bytesPerRow: width * channels,
          space: colorSpace,
          bitmapInfo: CGBitmapInfo.init(rawValue: bitmapInfo),
          provider: dataProvider,
          decode: nil,
          shouldInterpolate: false,
          intent: .defaultIntent
        )
        return image
      case .ycbcr(let yuv):
        func makeRGBA() -> [UInt8] {
          let w = width
          let h = height
          var out = [UInt8](repeating: 0, count: w * h * 4)

          /// Returns the index of the first element in `Y` for `(x, y)`.
          @inline(__always)
          func yIndex(_ x: Int, _ y: Int) -> Int {
            return y * yuv.yStride + x
          }

          /// Returns the index of the first element in `Cb/Cr` for `(x, y)`.
          @inline(__always)
          func cIndex(_ x: Int, _ y: Int) -> Int {
            switch yuv.subsample {
            case .s444:
              return y  * yuv.cStride + x
            case .s422:
              return y * yuv.cStride + (x >> 1)
            case .s420:
              return (y >> 1) * yuv.cStride + (x >> 1)
            case .s440:
              return (y >> 1) * yuv.cStride + x
            case .s411:
              return y * yuv.cStride + (x >> 2)
            case .s410:
              return (y >> 1) * yuv.cStride + (x >> 2)
            @unknown default:
              return y * yuv.cStride + x
            }
          }

          for y in 0..<h {
            for x in 0..<w {
              let Yval  = Int(yuv.y[yIndex(x, y)])
              let Cbval = Int(yuv.cb[cIndex(x, y)])
              let Crval = Int(yuv.cr[cIndex(x, y)])

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
              out[dst + 0] = UInt8(r)
              out[dst + 1] = UInt8(g)
              out[dst + 2] = UInt8(b)
              out[dst + 3] = 255
            }
          }
          return out
        }

        var pixels = makeRGBA()
        let channels = 4

        let data = CFDataCreate(nil, &pixels, width * height * channels)!
        let dataProvider = CGDataProvider(data: data)!
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.last.rawValue
        let image = CGImage(
          width: width,
          height: height,
          bitsPerComponent: 8,
          bitsPerPixel: 8 * channels,
          bytesPerRow: width * channels,
          space: colorSpace,
          bitmapInfo: CGBitmapInfo.init(rawValue: bitmapInfo),
          provider: dataProvider,
          decode: nil,
          shouldInterpolate: false,
          intent: .defaultIntent
        )
        return image
      case .nycbcra(let yuvA):
        func makeRGBABytes() -> [UInt8] {
          var out = [UInt8](repeating: 0, count: width * height * 4)

          @inline(__always) func clip(_ v: Int) -> UInt8 {
            v < 0 ? 0 : (v > 255 ? 255 : UInt8(v))
          }

          var dst = 0
          for yy in 0..<height {
            let yRow = yy * yuvA.ycbcr.yStride
            let aRow = yy * yuvA.aStride
            let cRow = (yuvA.ycbcr.subsample == .s422 || yuvA.ycbcr.subsample == .s444) ? yy * yuvA.ycbcr.cStride : (yy >> 1) * yuvA.ycbcr.cStride

            for xx in 0..<width {
              let yIdx = yRow + xx
              let aIdx = aRow + xx
              let cIdx = cRow + {
                switch yuvA.ycbcr.subsample {
                case .s444, .s440:
                  return xx
                case .s422, .s420:
                  return xx >> 1
                case .s411, .s410:
                  return xx >> 2
                }
              }()

              let Y = Int(yuvA.ycbcr.y[yIdx])
              let Cb = Int(yuvA.ycbcr.cb[cIdx]) - 128
              let Cr = Int(yuvA.ycbcr.cr[cIdx]) - 128

              // ITU‑R BT.601 (full range) 係数：結果は 0‑255 にクリップ
              let r = clip((298 * (Y - 16) + 409 * Cr + 128) >> 8)
              let g = clip((298 * (Y - 16) - 100 * Cb - 208 * Cr + 128) >> 8)
              let b = clip((298 * (Y - 16) + 516 * Cb + 128) >> 8)
              let α = yuvA.a[aIdx]

              out[dst + 0] = r
              out[dst + 1] = g
              out[dst + 2] = b
              out[dst + 3] = α
              dst += 4
            }
          }
          return out
        }

        var pixels = makeRGBABytes()
        let channels = 4

        let data = CFDataCreate(nil, &pixels, width * height * channels)!
        let dataProvider = CGDataProvider(data: data)!
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.last.rawValue
        let image = CGImage(
          width: width,
          height: height,
          bitsPerComponent: 8,
          bitsPerPixel: 8 * channels,
          bytesPerRow: width * channels,
          space: colorSpace,
          bitmapInfo: CGBitmapInfo.init(rawValue: bitmapInfo),
          provider: dataProvider,
          decode: nil,
          shouldInterpolate: false,
          intent: .defaultIntent
        )
        return image
      }
    }
  }

  public enum Storage {
    case nrgba(NRGBABuffer)
    case ycbcr(YCbCr420Buffer)
    case nycbcra(NYCbCrA420Buffer)
  }

  public struct NRGBABuffer {
    public var data: [UInt8]
    public var stride: Int

    public init(data: [UInt8], stride: Int) {
      self.data = data
      self.stride = stride
    }
  }

  public struct YCbCr420Buffer {
    public var y: [UInt8]
    public var cb: [UInt8]
    public var cr: [UInt8]
    public var yStride: Int
    public var cStride: Int
    public var subsample: Subsample
  }

  public struct NYCbCrA420Buffer {
    public var ycbcr: YCbCr420Buffer
    public var a: Data
    public var aStride: Int
  }

  public enum Subsample {
    case s410
    case s411
    case s440
    case s420
    case s422
    case s444
  }

  public enum Planes {
    case nrgba(NRGBABuffer)
    case ycbcr(YCbCr420Buffer)
    case nycbcra(NYCbCrA420Buffer)
  }

  public struct Metadata {
    public var orientation: CGImagePropertyOrientation = .up
    public var icc: Data? = nil
    public var exif: Data? = nil
    public var xmp: Data? = nil
    public init() {}
  }
}

func readAlpha(
  _ stream: RIFFReader,
  widthMinusOne w1: UInt32,
  heightMinusOne h1: UInt32,
  compression: UInt8
) throws -> (alpha: [UInt8], stride: Int) {
  switch compression {
    // ------------------------------------------------------------------ //
    // 0) Uncompressed alpha                                              //
    // ------------------------------------------------------------------ //
  case 0:
    let width  = Int(w1) + 1
    let height = Int(h1) + 1
    var alpha  = [UInt8](repeating: 0, count: width * height)
    let got    = stream.read(&alpha, maxLength: alpha.count)
    guard got == alpha.count else { throw WebPError.invalidFormat }
    return (alpha, width)
  case 1:
    guard w1 <= 0x3FFF, h1 <= 0x3FFF else {
      throw WebPError.invalidFormat
    }

    let w = w1 & 0x3FFF
    let h = h1 & 0x3FFF

    let header: [UInt8] = [
      0x2F,
      UInt8(truncatingIfNeeded: w & 0xFF),
      UInt8(truncatingIfNeeded: (w >> 8) & 0x3F) |
      UInt8(truncatingIfNeeded: (h & 0x3) << 6),
      UInt8(truncatingIfNeeded: h >> 2 & 0xFF),
      UInt8(truncatingIfNeeded: h >> 10 & 0x0F)
    ]

    var compressed = [UInt8]()
    var tmp = [UInt8](repeating: 0, count: 4096)
    while true {
      let n = stream.read(&tmp, maxLength: tmp.count)
      if n <= 0 { break }
      compressed.append(contentsOf: tmp[0..<n])
    }

    let payload = Data(header + compressed)
    var decoder = VP8LDecoder(data: payload)
    let lossless = try decoder.decode()

    let pix = lossless.pixels

    var alpha = [UInt8](repeating: 0, count: pix.count / 4)
    for i in 0..<alpha.count { alpha[i] = pix[4 * i + 1] }

    return (alpha, Int(w1) + 1)
  default:
    throw WebPError.invalidFormat
  }
}

func unfilterAlpha(_ alpha: inout [UInt8], _ stride: Int, _ filter: UInt8) {
  guard !alpha.isEmpty, stride > 0 else { return }

  switch filter {
  case 1:
    for i in 1..<stride {
      alpha[i] &+= alpha[i - 1]
    }

    var rowStart = stride
    while rowStart < alpha.count {
      // Col-0: vertical predictor.
      alpha[rowStart] &+= alpha[rowStart - stride]

      for j in 1..<stride {
        alpha[rowStart + j] &+= alpha[rowStart + j - 1]
      }
      rowStart += stride
    }
  case 2:
    for i in 1..<stride {
      alpha[i] &+= alpha[i - 1]
    }

    for i in stride..<alpha.count {
      alpha[i] &+= alpha[i - stride]
    }
  case 3:
    for i in 1..<stride {
      alpha[i] &+= alpha[i - 1]
    }
    var rowStart = stride
    while rowStart < alpha.count {
      alpha[rowStart] &+= alpha[rowStart - stride]

      for j in 1..<stride {
        let c = Int(alpha[rowStart + j - stride - 1])
        let b = Int(alpha[rowStart + j - stride])
        let a = Int(alpha[rowStart + j - 1])
        var x = a + b - c
        if x < 0   { x = 0 }
        if x > 255 { x = 255 }
        alpha[rowStart + j] &+= UInt8(x)
      }
      rowStart += stride
    }

  default:
    break
  }
}
