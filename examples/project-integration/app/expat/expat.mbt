///|
#borrow(input)
extern "C" fn valid_ffi(input : Bytes) -> Bool = "project_xml_valid"

///|
extern "C" fn configuration_ffi() -> Int32 = "project_expat_configuration"

///|
pub fn valid(input : Bytes) -> Bool {
  valid_ffi(input)
}

///|
pub fn configuration() -> Int32 {
  configuration_ffi()
}

///|
test "real Expat and existing custom setting" {
  assert_true(valid(b"<root/>") && !valid(b"<root>"))
  assert_eq(configuration(), 11)
}
