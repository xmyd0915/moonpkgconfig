///|
fn main {
  println("crc=\{@zlib.checksum(b"123456789")} custom=\{@zlib.configuration()}")
}
