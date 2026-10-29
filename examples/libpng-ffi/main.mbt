///|
#borrow(pixels)
extern "C" fn encoded_size(
  width : Int32,
  height : Int32,
  pixels : Bytes,
) -> Int32 = "moonpkg_png_size"

///|
#borrow(pixels, destination)
extern "C" fn encode_rgba(
  width : Int32,
  height : Int32,
  pixels : Bytes,
  destination : Bytes,
) -> Int32 = "moonpkg_png_encode"

///|
#borrow(encoded, destination)
extern "C" fn decode_rgba(
  encoded : Bytes,
  length : Int32,
  width : Int32,
  height : Int32,
  destination : Bytes,
) -> Int32 = "moonpkg_png_decode"

///|
fn encode(width : Int32, height : Int32, pixels : Bytes) -> (Bytes, Int32) {
  let capacity = encoded_size(width, height, pixels)
  if capacity <= 0 {
    abort("libpng could not measure the encoded image")
  }
  let encoded = Bytes::new(capacity)
  let length = encode_rgba(width, height, pixels, encoded)
  if length <= 0 || length > capacity {
    abort("libpng encoding failed")
  }
  (encoded, length)
}

///|
fn pixels(width : Int32, height : Int32) -> Bytes {
  Bytes::makei(width * height * 4, i => {
    if i % 4 == 3 {
      b'\xff'
    } else {
      ((i * 37 + i / 4) % 256).to_byte()
    }
  })
}

///|
fn round_trip(width : Int32, height : Int32) -> Unit {
  let original = pixels(width, height)
  let (encoded, length) = encode(width, height, original)
  let restored = Bytes::new(original.length())
  if decode_rgba(encoded, length, width, height, restored) != original.length() {
    abort("libpng decoded size differs")
  }
  for i in 0..<original.length() {
    if restored[i] != original[i] {
      abort("PNG round trip changed a pixel")
    }
  }
}

///|
fn main {
  round_trip(1, 1)
  round_trip(8, 8)
  round_trip(17, 9)
  let (encoded, length) = encode(8, 8, pixels(8, 8))
  if decode_rgba(b"not a PNG", 9, 8, 8, Bytes::new(256)) != -2 {
    abort("corrupt PNG should fail decoding")
  }
  if decode_rgba(encoded, length, 7, 8, Bytes::new(256)) != -3 {
    abort("unexpected PNG dimensions should be rejected")
  }
  if decode_rgba(encoded, length, 8, 8, Bytes::new(1)) != -4 {
    abort("small output buffer should be rejected")
  }
  if decode_rgba(encoded, encoded.length() + 1, 8, 8, Bytes::new(256)) != -1 {
    abort("out-of-bounds input length should be rejected")
  }
  println("MoonBit libpng FFI: 3 RGBA round trips and 4 error cases passed")
}
