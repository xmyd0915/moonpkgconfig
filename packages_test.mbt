///|
fn test_package(name : String, version : String) -> Document {
  parse(
    "Name: " + name + "\nDescription: test package\nVersion: " + version,
    source=name + ".pc",
  )
}

///|
test "package set stores validated documents" {
  let packages = PackageSet::new()
  @debug.assert_eq(packages.add("codec", test_package("Codec", "2.1")), [])
  @debug.assert_eq(
    packages.get("codec").unwrap().document.field("Version").unwrap().value,
    "2.1",
  )
}

///|
test "package set rejects invalid identifiers metadata and duplicates" {
  let packages = PackageSet::new()
  @debug.assert_eq(
    packages.add("bad id", test_package("Bad", "1")).map(d => d.code),
    ["PC013"],
  )
  @debug.assert_eq(
    packages.add("missing", parse("Name: Missing")).map(d => d.code),
    ["PC010", "PC010"],
  )
  @debug.assert_eq(packages.add("codec", test_package("Codec", "2.1")), [])
  @debug.assert_eq(
    packages.add("codec", test_package("Other", "3")).map(d => d.code),
    ["PC014"],
  )
}

///|
test "package set reports missing and incompatible direct dependencies" {
  let packages = PackageSet::new()
  packages.add("codec", test_package("Codec", "2.1")) |> ignore
  packages.add("compression", test_package("Compression", "1.0")) |> ignore
  let requirements = parse_requirements(
    "codec >= 2.0, compression > 1.0, image-format",
  ).unwrap()
  let diagnostics = packages.check_requirements(requirements, source="image.pc")
  @debug.assert_eq(diagnostics.map(d => d.code), ["PC016", "PC015"])
  @debug.assert_eq(diagnostics[0].location.source, "image.pc")
}
