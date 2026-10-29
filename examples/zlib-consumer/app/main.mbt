///|
extern "C" fn compress_bound(length : Int32) -> Int32 = "moonpkg_zlib_compress_bound"

///|
#borrow(source, destination)
extern "C" fn compress(source : Bytes, destination : Bytes) -> Int32 = "moonpkg_zlib_compress"

///|
#borrow(source, destination)
extern "C" fn decompress(
  source : Bytes,
  length : Int32,
  destination : Bytes,
) -> Int32 = "moonpkg_zlib_decompress"

///|
fn fail(message : String) -> Unit {
  println(message)
  @sys.exit(1)
}

///|
fn deflate_file(source : Bytes) -> Bytes {
  let bound = compress_bound(source.length())
  if bound <= 0 {
    fail("Could not determine zlib compression bound")
  }
  let destination = Bytes::new(bound)
  let length = compress(source, destination)
  if length <= 0 || length > bound {
    fail("zlib compression failed: \{length}")
  }
  Bytes::makei(length, i => destination[i])
}

///|
fn inflate_file(source : Bytes) -> Bytes {
  let mut capacity = 65536
  while capacity <= 67108864 {
    let destination = Bytes::new(capacity)
    let length = decompress(source, source.length(), destination)
    if length >= 0 && length <= capacity {
      return Bytes::makei(length, i => destination[i])
    }
    if length != -5 {
      fail("Invalid zlib stream: \{length}")
    }
    capacity = capacity * 2
  }
  fail("Invalid zlib stream or decompressed output exceeds 64 MiB")
  b""
}

///|
fn main {
  let args = @env.args()
  if args.length() != 4 || (args[1] != "compress" && args[1] != "decompress") {
    println("Usage: compressor <compress|decompress> <input> <output>")
    @sys.exit(2)
  }
  if args[2] == args[3] {
    fail("Input and output must be different files")
  }
  if @fs.path_exists(args[3]) {
    fail("Output already exists: \{args[3]}")
  }
  try {
    let source = @fs.read_file_to_bytes(args[2])
    let input_limit = if args[1] == "compress" {
      67108864
    } else {
      compress_bound(67108864)
    }
    if source.length() > input_limit {
      fail("Input exceeds the supported size: \{input_limit} bytes")
    }
    let result = if args[1] == "compress" {
      deflate_file(source)
    } else {
      inflate_file(source)
    }
    @fs.write_bytes_to_file(args[3], result)
    println("\{args[1]}: \{source.length()} -> \{result.length()} bytes")
  } catch {
    @fs.IOError(message) => fail("File operation failed: \{message}")
  }
}
