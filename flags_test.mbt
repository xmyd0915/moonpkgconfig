///|
fn flag_package(
  id : String,
  requires : String,
  cflags : String,
  libs : String,
  private_requires? : String = "",
  private_libs? : String = "",
) -> @moonpkgconfig.Document {
  let text = StringBuilder()
  text.write_string("Name: " + id + "\nDescription: flag fixture\nVersion: 1")
  if !requires.is_empty() {
    text.write_string("\nRequires: " + requires)
  }
  if !private_requires.is_empty() {
    text.write_string("\nRequires.private: " + private_requires)
  }
  if !libs.is_empty() {
    text.write_string("\nLibs: " + libs)
  }
  if !private_libs.is_empty() {
    text.write_string("\nLibs.private: " + private_libs)
  }
  if !cflags.is_empty() {
    text.write_string("\nCflags: " + cflags)
  }
  @moonpkgconfig.parse(text.to_string(), source=id + ".pc")
}

///|
test "compiler flags put dependants before dependencies" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add("codec", flag_package("codec", "", "-I/codec", "-lcodec"))
  |> ignore
  packages.add("app", flag_package("app", "codec", "-I/app -DAPP=1", "-lapp"))
  |> ignore
  let result = packages.collect_cflags("app")
  @debug.assert_eq(result.diagnostics, [])
  @debug.assert_eq(result.flags.map(f => f.value), [
    "-I/app", "-DAPP=1", "-I/codec",
  ])
  @debug.assert_eq(result.flags.map(f => f.package_id), ["app", "app", "codec"])
  @debug.assert_eq(result.flags[0].location.source, "app.pc")
}

///|
test "linker flags put dependants before dependencies" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add("codec", flag_package("codec", "", "", "-lcodec")) |> ignore
  packages.add("app", flag_package("app", "codec", "", "-lapp")) |> ignore
  @debug.assert_eq(packages.collect_libs("app").flags.map(f => f.value), [
    "-lapp", "-lcodec",
  ])
}

///|
test "static linker flags include private edges and fields" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add("helper", flag_package("helper", "", "", "-lhelper")) |> ignore
  packages.add(
    "app",
    flag_package(
      "app",
      "",
      "",
      "-lapp",
      private_requires="helper",
      private_libs="-pthread",
    ),
  )
  |> ignore
  @debug.assert_eq(packages.collect_libs("app").flags.map(f => f.value), [
    "-lapp",
  ])
  @debug.assert_eq(
    packages.collect_libs("app", static_linking=true).flags.map(f => f.value),
    ["-lapp", "-pthread", "-lhelper"],
  )
}

///|
test "flag tokenization errors retain the field source" {
  let packages = @moonpkgconfig.PackageSet::new()
  let bad = @moonpkgconfig.parse(
    "Name: bad\nDescription: bad flags\nVersion: 1\n  Cflags: 'unfinished",
    source="bad.pc",
  )
  packages.add("bad", bad) |> ignore
  let result = packages.collect_cflags("bad")
  @debug.assert_eq(result.diagnostics.map(d => d.code), ["PC006"])
  @debug.assert_eq(result.diagnostics[0].location.source, "bad.pc")
  @debug.assert_eq(result.diagnostics[0].location.line, 4)
  @debug.assert_eq(result.diagnostics[0].location.column, 22)
  @debug.assert_eq(result.flags, [])
}

///|
test "search path deduplication keeps other repeated flags and first origin" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add(
    "dependency",
    flag_package(
      "dependency", "", "-I/shared -I /split -I/mixed -DVALUE=1", "-L/shared -L /split -L/mixed -lrepeat",
    ),
  )
  |> ignore
  packages.add(
    "app",
    flag_package(
      "app", "dependency", "-I/shared -I /split -I /mixed -DVALUE=1", "-L/shared -L /split -L /mixed -lrepeat",
    ),
  )
  |> ignore
  let cflags = packages.collect_cflags("app").deduplicate_search_paths()
  @debug.assert_eq(cflags.flags.map(f => f.value), [
    "-I/shared", "-I", "/split", "-I", "/mixed", "-DVALUE=1", "-DVALUE=1",
  ])
  @debug.assert_eq(cflags.flags[0].package_id, "app")
  let libs = packages.collect_libs("app").deduplicate_search_paths()
  @debug.assert_eq(libs.flags.map(f => f.value), [
    "-L/shared", "-L", "/split", "-L", "/mixed", "-lrepeat", "-lrepeat",
  ])
  @debug.assert_eq(libs.flags[0].package_id, "app")
}

///|
test "search path operands never cross package or field boundaries" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add(
    "dependency",
    flag_package("dependency", "", "/dependency-first", "-ldependency"),
  )
  |> ignore
  packages.add("app", flag_package("app", "dependency", "-I", "-lapp"))
  |> ignore
  let result = packages.collect_cflags("app").deduplicate_search_paths()
  @debug.assert_eq(result.flags.map(flag => flag.value), [
    "-I", "/dependency-first",
  ])
  @debug.assert_eq(result.flags.map(flag => flag.package_id), [
    "app", "dependency",
  ])
}

///|
test "flag order keeps declared siblings stable in a diamond graph" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add("common", flag_package("common", "", "-I/common", "-lcommon"))
  |> ignore
  packages.add("left", flag_package("left", "common", "-I/left", "-lleft"))
  |> ignore
  packages.add("right", flag_package("right", "common", "-I/right", "-lright"))
  |> ignore
  packages.add("root", flag_package("root", "left, right", "-I/root", "-lroot"))
  |> ignore
  @debug.assert_eq(packages.collect_cflags("root").flags.map(f => f.value), [
    "-I/root", "-I/left", "-I/right", "-I/common",
  ])
  @debug.assert_eq(packages.collect_libs("root").flags.map(f => f.value), [
    "-lroot", "-lleft", "-lright", "-lcommon",
  ])
}

///|
test "shell output preserves argument boundaries and literal characters" {
  let location : @moonpkgconfig.Location = {
    source: "quoted.pc",
    line: 1,
    column: 1,
  }
  let result : @moonpkgconfig.FlagResult = {
    flags: [
      {
        value: "-I/opt/sdk dir/include",
        package_id: "quoted",
        field: "Cflags",
        location,
      },
      { value: "-DNAME=a b", package_id: "quoted", field: "Cflags", location, },
      { value: "", package_id: "quoted", field: "Cflags", location, },
      { value: "plain", package_id: "quoted", field: "Cflags", location, },
      { value: "a'b", package_id: "quoted", field: "Cflags", location, },
      { value: "$HOME", package_id: "quoted", field: "Cflags", location, },
    ],
    diagnostics: [],
  }
  @debug.assert_eq(
    result.shell_text(),
    "'-I/opt/sdk dir/include' '-DNAME=a b' '' plain 'a'\\''b' '$HOME'",
  )
}
