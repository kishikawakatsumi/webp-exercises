enum VP8LHeaderError: Error {
  case invalidHeader
  case invalidVersion
}

enum VP8LError: Error {
  case invalidCodeLengths
  case invalidHuffmanTree
  case invalidColorCacheParameters
  case invalidLZ77Parameters
  case invalidColorCacheIndex

  case invalidBitstream
  case notImplemented
}

enum HuffBuildError: Error {
  case invalidTree
  case lengthOutOfRange
}

enum VP8LDecodingError: Error {
  case repeatedTransform
}

enum BitStreamError: Error {
  case unexpectedEOF
}
