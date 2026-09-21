///|
test "variable expansion retains original and source" {
  let doc = @moonpkgconfig.parse(
    "prefix=/opt/sdk\nlibdir=${prefix}/lib\nLibs: -L${libdir} -lcodec\n",
    source="codec.pc",
  )
  @debug.assert_eq(doc.diagnostics, [])
  let field = doc.field("Libs").unwrap()
  @debug.assert_eq(field.value, "-L/opt/sdk/lib -lcodec")
  @debug.assert_eq(field.raw, "-L${libdir} -lcodec")
  @debug.assert_eq(field.location, { source: "codec.pc", line: 3, column: 1, })
}

///|
test "pcfiledir is supplied explicitly by caller" {
  let doc = @moonpkgconfig.parse(
    "prefix=${pcfiledir}/..\nName: 测试库",
    pcfiledir="/sdk/lib/pkgconfig",
  )
  @debug.assert_eq(
    doc.variable("prefix").unwrap().value,
    "/sdk/lib/pkgconfig/..",
  )
  @debug.assert_eq(doc.field("Name").unwrap().value, "测试库")
}

///|
test "forward reference is rejected and parsing recovers" {
  let doc = @moonpkgconfig.parse("bad=${later}\nlater=ok\nName: works")
  @debug.assert_eq(doc.diagnostics.length(), 1)
  @debug.assert_eq(doc.diagnostics[0].code, "PC004")
  @debug.assert_eq(doc.diagnostics[0].location.column, 5)
  @debug.assert_eq(doc.variable("bad"), None)
  @debug.assert_eq(doc.field("Name").unwrap().value, "works")
}

///|
test "self reference fails without recursion" {
  let doc = @moonpkgconfig.parse("a=${a}")
  @debug.assert_eq(doc.diagnostics[0].code, "PC004")
}

///|
test "literal dollar reference is not recursively substituted" {
  let doc = @moonpkgconfig.parse("literal=$${missing}\nName: ${literal}")
  @debug.assert_eq(doc.diagnostics, [])
  @debug.assert_eq(doc.field("Name").unwrap().value, "${missing}")
}

///|
test "duplicate variables fields and builtins are rejected" {
  for input in ["a=one\na=two", "Name: one\nName: two", "pcfiledir=/wrong"] {
    let doc = @moonpkgconfig.parse(input)
    @debug.assert_eq(doc.diagnostics.length(), 1)
    @debug.assert_eq(doc.diagnostics[0].code, "PC005")
  }
  @debug.assert_eq(
    @moonpkgconfig.parse("Name: one\nName: two").field("Name").unwrap().value,
    "one",
  )
}

///|
test "comments CRLF BOM empty lines and unterminated final line" {
  let doc = @moonpkgconfig.parse(
    "\u{FEFF}# heading\r\n\r\n  Name : hello # comment\r\nVersion: 1.0",
  )
  @debug.assert_eq(doc.diagnostics, [])
  @debug.assert_eq(doc.entries.length(), 2)
  @debug.assert_eq(doc.field("Name").unwrap().value, "hello")
  @debug.assert_eq(doc.field("Name").unwrap().location.line, 3)
  @debug.assert_eq(doc.field("Name").unwrap().location.column, 3)
}

///|
test "continuations support LF and CRLF" {
  for eol in ["\n", "\r\n"] {
    let doc = @moonpkgconfig.parse(
      "Libs: -la \\" + eol + " -lb" + eol + "Name: demo",
    )
    @debug.assert_eq(doc.diagnostics, [])
    @debug.assert_eq(
      @moonpkgconfig.split_flags(doc.field("Libs").unwrap().value),
      Ok(["-la", "-lb"]),
    )
    @debug.assert_eq(doc.field("Name").unwrap().location.line, 3)
  }
}

///|
test "escaped hash is literal and paired slashes do not escape comment" {
  @debug.assert_eq(
    @moonpkgconfig.parse("Name: a\\#b # comment").field("Name").unwrap().value,
    "a#b",
  )
  @debug.assert_eq(
    @moonpkgconfig.parse("Name: a\\\\#comment").field("Name").unwrap().value,
    "a\\\\",
  )
}

///|
test "syntax diagnostics and whitespace in keys" {
  let doc = @moonpkgconfig.parse(
    "not an assignment\nbad key=one\nName: ${unclosed",
  )
  @debug.assert_eq(doc.diagnostics.map(d => d.code), ["PC001", "PC002", "PC003"])
  @debug.assert_eq(doc.entries, [])
}

///|
test "value punctuation and empty values are preserved" {
  let doc = @moonpkgconfig.parse(
    "url=https://example.invalid/a=b\nURL: ${url}\nLibs:\nempty=",
  )
  @debug.assert_eq(doc.diagnostics, [])
  @debug.assert_eq(
    doc.field("URL").unwrap().value,
    "https://example.invalid/a=b",
  )
  @debug.assert_eq(doc.field("Libs").unwrap().value, "")
  @debug.assert_eq(doc.variable("empty").unwrap().value, "")
}

///|
test "variable and property namespaces are separate and case sensitive" {
  let doc = @moonpkgconfig.parse("Name=lower\nName: ${Name}\nname: other")
  @debug.assert_eq(doc.diagnostics, [])
  @debug.assert_eq(doc.field("Name").unwrap().value, "lower")
  @debug.assert_eq(doc.field("name").unwrap().value, "other")
}

///|
test "flags preserve quoted spaces empty args and concatenation" {
  @debug.assert_eq(
    @moonpkgconfig.split_flags(
      "-I'/opt/sdk dir/include' -DNAME=\"a b\" '' pre\"mid\"post",
    ),
    Ok(["-I/opt/sdk dir/include", "-DNAME=a b", "", "premidpost"]),
  )
}

///|
test "flags handle escaped spaces quotes and single quoted backslashes" {
  @debug.assert_eq(
    @moonpkgconfig.split_flags("-I/opt/a\\ b \\\"quoted\\\" 'a\\b' \"a\\qb\""),
    Ok(["-I/opt/a b", "\"quoted\"", "a\\b", "a\\qb"]),
  )
}

///|
test "flags do not execute or @moonpkgconfig.expand shell text" {
  @debug.assert_eq(
    @moonpkgconfig.split_flags("$(touch marker) `cmd` $HOME *.c"),
    Ok(["$(touch", "marker)", "`cmd`", "$HOME", "*.c"]),
  )
}

///|
test "malformed flags return diagnostics" {
  for (input, code) in [("'unfinished", "PC006"), ("trailing\\", "PC007")] {
    match @moonpkgconfig.split_flags(input) {
      Err(d) => @debug.assert_eq(d.code, code)
      Ok(_) => fail("expected invalid flags")
    }
  }
}

///|
test "dependency list supports all version operators and separators" {
  let actual = @moonpkgconfig.parse_requirements(
    "a >= 1, b<=2 c=3 d!=4, e>5 f<6 g",
  )
  @debug.assert_eq(
    actual,
    Ok([
      { name: "a", op: GreaterEqual, version: "1", },
      { name: "b", op: LessEqual, version: "2", },
      { name: "c", op: Equal, version: "3", },
      { name: "d", op: NotEqual, version: "4", },
      { name: "e", op: Greater, version: "5", },
      { name: "f", op: Less, version: "6", },
      { name: "g", op: Any, version: "", },
    ]),
  )
}

///|
test "dependency list diagnoses malformed operators and missing versions" {
  for input in ["foo >=", "foo == 1", ">= 1", "foo >, bar", "foo >= >2"] {
    match @moonpkgconfig.parse_requirements(input) {
      Err(d) => @debug.assert_eq(d.code, "PC008")
      Ok(_) => fail("expected invalid requirement: " + input)
    }
  }
}

///|
test "empty document flags and requirements are valid" {
  @debug.assert_eq(@moonpkgconfig.parse("# just a comment").entries, [])
  @debug.assert_eq(@moonpkgconfig.split_flags(" \t"), Ok([]))
  @debug.assert_eq(@moonpkgconfig.parse_requirements(" , \t"), Ok([]))
}

///|
test "expansion enforces output limit before appending oversized variable" {
  let variables : Map[String, String] = { "huge": "x".repeat(1048577) }
  match
    @moonpkgconfig.expand("${huge}", variables, location={
      source: "limit.pc",
      line: 2,
      column: 4,
    }) {
    Err(d) => @debug.assert_eq(d.code, "PC009")
    Ok(_) => fail("expected expansion limit diagnostic")
  }
}
