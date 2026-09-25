///|
fn test_package(name : String, version : String) -> @moonpkgconfig.Document {
  @moonpkgconfig.parse(
    "Name: " + name + "\nDescription: test package\nVersion: " + version,
    source=name + ".pc",
  )
}

///|
test "package set stores validated documents" {
  let packages = @moonpkgconfig.PackageSet::new()
  @debug.assert_eq(packages.add("codec", test_package("Codec", "2.1")), [])
  @debug.assert_eq(
    packages.get("codec").unwrap().document.field("Version").unwrap().value,
    "2.1",
  )
}

///|
test "package set rejects invalid identifiers metadata and duplicates" {
  let packages = @moonpkgconfig.PackageSet::new()
  @debug.assert_eq(
    packages.add("bad id", test_package("Bad", "1")).map(d => d.code),
    ["PC013"],
  )
  @debug.assert_eq(
    packages
    .add("missing", @moonpkgconfig.parse("Name: Missing"))
    .map(d => d.code),
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
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add("codec", test_package("Codec", "2.1")) |> ignore
  packages.add("compression", test_package("Compression", "1.0")) |> ignore
  let requirements = @moonpkgconfig.parse_requirements(
    "codec >= 2.0, compression > 1.0, image-format",
  ).unwrap()
  let diagnostics = packages.check_requirements(requirements, source="image.pc")
  @debug.assert_eq(diagnostics.map(d => d.code), ["PC016", "PC015"])
  @debug.assert_eq(diagnostics[0].location.source, "image.pc")
}

///|
test "package set accepts matching virtual providers" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add(
    "fast-codec",
    @moonpkgconfig.parse(
      "Name: Fast codec\nDescription: test provider\nVersion: 7\nProvides: codec = 3",
      source="fast-codec.pc",
    ),
  )
  |> ignore
  let matching = @moonpkgconfig.parse_requirements("codec >= 2").unwrap()
  let too_new = @moonpkgconfig.parse_requirements("codec >= 4").unwrap()
  @debug.assert_eq(packages.check_requirements(matching), [])
  @debug.assert_eq(packages.check_requirements(too_new).map(d => d.code), [
    "PC015",
  ])
}

///|
fn virtual_provider_accepts(provides : String, request : String) -> Bool {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add(
    "provider",
    @moonpkgconfig.parse(
      "Name: provider\nDescription: virtual provider fixture\nVersion: 9\nProvides: " +
      provides,
      source="provider.pc",
    ),
  )
  |> ignore
  packages
  .check_requirements(@moonpkgconfig.parse_requirements(request).unwrap())
  .is_empty()
}

///|
test "range virtual providers follow pkgconf comparator pairs" {
  @debug.assert_eq(virtual_provider_accepts("virtual > 1.1.0", "virtual"), true)
  @debug.assert_eq(
    virtual_provider_accepts("virtual > 1.1.0", "virtual >= 1.1.1"),
    true,
  )
  @debug.assert_eq(
    virtual_provider_accepts("virtual > 1.1.0", "virtual <= 1.1.1"),
    true,
  )
  @debug.assert_eq(
    virtual_provider_accepts("virtual > 1.1.0", "virtual <= 1.1.0"),
    false,
  )
  @debug.assert_eq(
    virtual_provider_accepts("virtual > 1.1.0", "virtual != 1.1.0"),
    true,
  )
  @debug.assert_eq(
    virtual_provider_accepts("virtual > 1.1.0", "virtual != 1.1.1"),
    false,
  )
  @debug.assert_eq(
    virtual_provider_accepts("virtual < 1.2.0", "virtual >= 1.1.0"),
    true,
  )
  @debug.assert_eq(
    virtual_provider_accepts("virtual < 1.2.0", "virtual >= 1.2.0"),
    false,
  )
  @debug.assert_eq(
    virtual_provider_accepts("virtual <= 1.2.0", "virtual >= 1.2.0"),
    true,
  )
  @debug.assert_eq(
    virtual_provider_accepts("virtual >= 1.1.0", "virtual <= 1.1.0"),
    true,
  )
  @debug.assert_eq(
    virtual_provider_accepts("virtual != 1.3.0", "virtual = 1.2.0"),
    true,
  )
  @debug.assert_eq(
    virtual_provider_accepts("virtual != 1.3.0", "virtual = 1.3.0"),
    false,
  )
}

///|
test "unversioned Provides does not synthesize a usable virtual version" {
  @debug.assert_eq(virtual_provider_accepts("virtual", "virtual"), false)
  @debug.assert_eq(virtual_provider_accepts("virtual", "virtual = 1"), false)
}
