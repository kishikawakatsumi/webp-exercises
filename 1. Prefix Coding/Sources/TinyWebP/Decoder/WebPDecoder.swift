import Foundation
import CoreGraphics

private let fccALPH = FourCC("ALPH")
private let fccVP8 = FourCC("VP8 ")
private let fccVP8L = FourCC("VP8L")
private let fccVP8X = FourCC("VP8X")
private let fccWEBP = FourCC("WEBP")

public struct WebPDecoder {
  public static func decode(_ data: Data) throws -> Image {
    let (formType, reader): (FourCC, RIFFReader)
    do {
      (formType, reader) = try RIFFReader.makeReader(from: data)
    } catch let e as RIFFError {
      throw WebPError.riff(e)
    }

    guard formType == fccWEBP else {
      throw WebPError.invalidFormat
    }

    let wantAlpha = false
    let alphaPixels: [UInt8]? = nil

    while true {
      let (chunkID, chunkData): (FourCC, Data)
      do {
        (chunkID, chunkData) = try reader.next()
      } catch is EOFError {
        throw WebPError.invalidFormat
      } catch let e as RIFFError {
        throw WebPError.riff(e)
      }

      switch chunkID {
      case fccALPH:
        break
      case fccVP8:
        break
      case fccVP8L:
        guard !wantAlpha, alphaPixels == nil else {
          throw WebPError.invalidFormat
        }
        var decoder = VP8LDecoder(data: chunkData)
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
      case fccVP8X:
        break
      default:
        break
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

    public init(
      width: Int,
      height: Int,
      storage: Storage,
      colorSpace: CGColorSpace? = nil
    ) {
      self.width = width
      self.height = height
      self.storage = storage
      self.colorSpace = colorSpace
    }

    public func withUnsafePlanes<R>(_ body: (Planes) throws -> R) rethrows -> R {
      switch storage {
      case .nrgba(let b):
        return try body(.nrgba(b))
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
      }
    }
  }

  public enum Storage {
    case nrgba(NRGBABuffer)
  }

  public struct NRGBABuffer {
    public var data: [UInt8]
    public var stride: Int

    public init(data: [UInt8], stride: Int) {
      self.data = data
      self.stride = stride
    }
  }

  public enum Planes {
    case nrgba(NRGBABuffer)
  }
}
