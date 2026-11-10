///|
test "public native API links from a blackbox test" {
  assert_eq(@zlib.checksum(b"123456789"), 0xcbf43926U)
  assert_eq(@zlib.configuration(), 7)
}
