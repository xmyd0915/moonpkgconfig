///|
test "document JSON keeps raw expanded and source values" {
  let doc = @moonpkgconfig.parse(
    "prefix=/opt/sdk\nLibs: -L${prefix}/lib",
    source="codec.pc",
  )
  guard doc.as_json() is Object(root) else { fail("expected JSON object") }
  guard root.get("entries") is Some(Array(entries)) else {
    fail("expected entries array")
  }
  guard entries[1] is Object(field) else { fail("expected entry object") }
  @debug.assert_eq(field.get("raw"), Some(Json("-L${prefix}/lib")))
  @debug.assert_eq(field.get("value"), Some(Json("-L/opt/sdk/lib")))
  guard field.get("location") is Some(Object(location)) else {
    fail("expected location object")
  }
  @debug.assert_eq(location.get("source"), Some(Json("codec.pc")))
  @debug.assert_eq(location.get("line"), Some(Json(2)))
}

///|
test "diagnostics are available in compact and pretty JSON" {
  let doc = @moonpkgconfig.parse("Name: ${missing}", source="broken.pc")
  let compact = doc.json_text()
  let pretty = doc.json_text(pretty=true)
  assert_true(compact.contains("\"code\":\"PC004\""))
  assert_true(pretty.contains("\n"))
  assert_true(pretty.contains("broken.pc"))
}

///|
test "flag JSON includes package field and location" {
  let result : @moonpkgconfig.FlagResult = {
    flags: [
      {
        value: "-lcodec",
        package_id: "codec",
        field: "Libs",
        location: { source: "codec.pc", line: 4, column: 1, },
      },
    ],
    diagnostics: [],
  }
  let text = result.json_text()
  assert_true(text.contains("\"package\":\"codec\""))
  assert_true(text.contains("\"field\":\"Libs\""))
  assert_true(text.contains("\"line\":4"))
}
