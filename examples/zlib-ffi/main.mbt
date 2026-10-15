///|
extern "C" fn compress_bound(length : Int) -> Int = "moonpkg_zlib_compress_bound"

///|
#borrow(source)
extern "C" fn checksum(source : Bytes) -> UInt = "moonpkg_zlib_crc32"

///|
#borrow(source, destination)
extern "C" fn compress(source : Bytes, destination : Bytes) -> Int = "moonpkg_zlib_compress"

///|
#borrow(source, destination)
extern "C" fn decompress(
  source : Bytes,
  length : Int,
  destination : Bytes,
) -> Int = "moonpkg_zlib_decompress"

///|
fn round_trip(source : Bytes) -> Unit {
  let bound = compress_bound(source.length())
  if bound <= 0 {
    abort("zlib did not return a valid compression bound")
  }
  let compressed = Bytes::new(bound)
  let length = compress(source, compressed)
  if length <= 0 || length > bound {
    abort("zlib compression failed")
  }
  // A nonempty destination also permits checking the empty-input case.
  let restored = Bytes::new(source.length() + 1)
  if decompress(compressed, length, restored) != source.length() {
    abort("zlib decompression length differs")
  }
  for i in 0..<source.length() {
    if restored[i] != source[i] {
      abort("zlib round trip changed the input")
    }
  }
}

///|
fn main {
  if checksum(b"123456789") != 0xcbf43926U {
    abort("CRC-32 check vector differs")
  }
  round_trip(b"")
  round_trip(b"MoonBit calls zlib through flags from MoonPkgConfig.")
  round_trip(Bytes::makei(4096, i => (i % 251).to_byte()))
  let invalid = b"not a zlib stream"
  if decompress(invalid, invalid.length(), Bytes::new(64)) != -3 {
    abort("corrupt input should return Z_DATA_ERROR")
  }
  let source = b"destination buffer is too small"
  let compressed = Bytes::new(compress_bound(source.length()))
  let length = compress(source, compressed)
  if length <= 0 {
    abort("compression for buffer-size check failed")
  }
  if decompress(compressed, length, Bytes::new(1)) != -5 {
    abort("small destination should return Z_BUF_ERROR")
  }
  if decompress(compressed, -1, Bytes::new(64)) != -2 {
    abort("negative source length should return Z_STREAM_ERROR")
  }
  println("MoonBit zlib FFI: CRC-32, 3 round trips and 3 error cases passed")
}
