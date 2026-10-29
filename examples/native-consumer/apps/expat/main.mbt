///|
#borrow(input, summary)
extern "C" fn parse_xml(
  input : Bytes,
  length : Int32,
  chunk_size : Int32,
  summary : Bytes,
) -> Int32 = "moonpkg_expat_parse"

///|
fn read_u32(bytes : Bytes, offset : Int32) -> Int32 {
  bytes[offset].to_int() |
  (bytes[offset + 1].to_int() << 8) |
  (bytes[offset + 2].to_int() << 16) |
  (bytes[offset + 3].to_int() << 24)
}

///|
fn check_document(input : Bytes, chunk_size : Int32, valid : Bool) -> Json {
  let summary = Bytes::new(24)
  let status = parse_xml(input, input.length(), chunk_size, summary)
  if status != (if valid { 1 } else { 0 }) {
    abort("Expat returned an unexpected parse status")
  }
  let bytes : Array[Json] = []
  for byte in input {
    bytes.push(Json(byte.to_int()))
  }
  Json::object({
    "input": Json::array(bytes),
    "chunk_size": Json(chunk_size),
    "status": Json(status),
    "elements": Json(read_u32(summary, 0)),
    "attributes": Json(read_u32(summary, 4)),
    "text_bytes": Json(read_u32(summary, 8)),
    "error": Json(read_u32(summary, 12)),
    "line": Json(read_u32(summary, 16)),
    "column": Json(read_u32(summary, 20)),
  })
}

///|
fn main {
  let cases : Array[Json] = []
  for
    text in [
      "<root/>", "<?xml version=\"1.0\"?><root id=\"7\"><item>hello &amp; 喵</item><item/></root>",
      "<root><a x=\"1\" y=\"2\">é😀</a><b>tail</b></root>",
    ] {
    let input = @utf8.encode(text)
    for chunk_size in [1, 7, 4096] {
      cases.push(check_document(input, chunk_size, true))
    }
  }
  for input in [b"", b"<root>", b"<root>\n<item></root>", b"<root>\xff</root>"] {
    cases.push(check_document(input, 3, false))
  }
  let summary = Bytes::new(24)
  let input = b"<root/>"
  for
    (length, chunk_size) in [
      (-1, 1),
      (input.length() + 1, 1),
      (input.length(), 0),
    ] {
    if parse_xml(input, length, chunk_size, summary) != -1 {
      abort("Invalid FFI input bounds were not rejected")
    }
  }
  if parse_xml(input, input.length(), 1, Bytes::new(23)) != -1 {
    abort("Short FFI summary buffer was not rejected")
  }
  println(
    Json::object({ "cases": Json::array(cases), "boundary_checks": Json(4) }).stringify(),
  )
}
