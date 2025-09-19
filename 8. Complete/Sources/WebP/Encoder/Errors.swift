public enum FlattenError: Error {
  case unsupportedImage
}

enum WebPEncodeError: Error {
  case invalidImageSize
  case noImages
  case durationsMismatch
  case disposalsMismatch
  case innerEncodeFailed
}
