struct NRGBA: Equatable {
  var r: UInt8
  var g: UInt8
  var b: UInt8
  var a: UInt8

  init(r: UInt8 = 0, g: UInt8 = 0, b: UInt8 = 0, a: UInt8 = 255) {
    self.r = r
    self.g = g
    self.b = b
    self.a = a
  }
}
