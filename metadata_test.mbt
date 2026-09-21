///|
test "complete package metadata is valid" {
  let doc = @moonpkgconfig.parse(
    "Name: demo\nDescription: example package\nVersion: 1.2.0",
  )
  @debug.assert_eq(doc.validate_metadata(), [])
}

///|
test "metadata validation reports every missing required field" {
  let diagnostics = @moonpkgconfig.parse("Libs: -ldemo").validate_metadata(
    source="demo.pc",
  )
  @debug.assert_eq(diagnostics.map(d => d.code), ["PC010", "PC010", "PC010"])
  @debug.assert_eq(diagnostics[0].message, "Missing required field: Name")
  @debug.assert_eq(diagnostics[0].location.source, "demo.pc")
}

///|
test "metadata validation distinguishes empty and malformed values" {
  let doc = @moonpkgconfig.parse(
    "Name:\nDescription: usable\nVersion: 1.0 beta",
    source="bad.pc",
  )
  let diagnostics = doc.validate_metadata(source="bad.pc")
  @debug.assert_eq(diagnostics.map(d => d.code), ["PC011", "PC012"])
  @debug.assert_eq(diagnostics[0].location.line, 1)
  @debug.assert_eq(diagnostics[1].location.line, 3)
}
