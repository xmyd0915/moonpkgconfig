///|
extern "C" fn compress_bound(length : Int) -> Int = "moonpkg_zlib_compress_bound"

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
#borrow(path, status)
extern "C" fn read_bounded(
  path : Bytes,
  limit : Int,
  status : FixedArray[Int],
) -> Bytes = "moonpkg_read_bounded"

///|
#borrow(path, content)
extern "C" fn write_new(path : Bytes, content : Bytes) -> Int = "moonpkg_write_new"

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
  let input_limit = if args[1] == "compress" {
    67108864
  } else {
    compress_bound(67108864)
  }
  let status : FixedArray[Int] = [0]
  let source = read_bounded(@utf8.encode(args[2]), input_limit, status)
  if status[0] == 2 {
    fail("Input exceeds the supported size: \{input_limit} bytes")
  }
  if status[0] != 0 {
    fail("Could not read input: \{args[2]}")
  }
  let result = if args[1] == "compress" {
    deflate_file(source)
  } else {
    inflate_file(source)
  }
  let written = write_new(@utf8.encode(args[3]), result)
  if written == 1 {
    fail("Output already exists: \{args[3]}")
  }
  if written != 0 {
    fail("Could not write output: \{args[3]}")
  }
  println("\{args[1]}: \{source.length()} -> \{result.length()} bytes")
}
