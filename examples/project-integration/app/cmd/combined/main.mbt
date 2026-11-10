///|
fn main {
  println(
    "crc=\{@zlib.checksum(b"123456789")} xml=\{@expat.valid(b"<root/>")} custom=\{@zlib.configuration()},\{@expat.configuration()}",
  )
}
