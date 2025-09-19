public struct NRGBA: Equatable {
  public var r: UInt8
  public var g: UInt8
  public var b: UInt8
  public var a: UInt8

  public init(r: UInt8 = 0, g: UInt8 = 0, b: UInt8 = 0, a: UInt8 = 255) {
    self.r = r; self.g = g; self.b = b; self.a = a
  }
}
