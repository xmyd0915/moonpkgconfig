///|
#borrow(input)
extern "C" fn checksum_ffi(input : Bytes) -> UInt32 = "project_crc32"

///|
extern "C" fn configuration_ffi() -> Int32 = "project_zlib_configuration"

///|
pub fn checksum(input : Bytes) -> UInt32 {
  checksum_ffi(input)
}

///|
pub fn configuration() -> Int32 {
  configuration_ffi()
}

///|
test "real zlib and existing custom setting" {
  assert_eq(checksum(b"123456789"), 0xcbf43926U)
  assert_eq(configuration(), 7)
}
