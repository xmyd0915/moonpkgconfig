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
test "compiler flags keep dependency order and origin" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add("codec", flag_package("codec", "", "-I/codec", "-lcodec"))
  |> ignore
  packages.add("app", flag_package("app", "codec", "-I/app -DAPP=1", "-lapp"))
  |> ignore
  let result = packages.collect_cflags("app")
  @debug.assert_eq(result.diagnostics, [])
  @debug.assert_eq(result.flags.map(f => f.value), [
    "-I/codec", "-I/app", "-DAPP=1",
  ])
  @debug.assert_eq(result.flags.map(f => f.package_id), ["codec", "app", "app"])
  @debug.assert_eq(result.flags[0].location.source, "codec.pc")
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
  packages.add("bad", flag_package("bad", "", "'unfinished", "")) |> ignore
  let result = packages.collect_cflags("bad")
  @debug.assert_eq(result.diagnostics.map(d => d.code), ["PC006"])
  @debug.assert_eq(result.diagnostics[0].location.source, "bad.pc")
  @debug.assert_eq(result.flags, [])
}

///|
test "search path deduplication keeps other repeated flags and first origin" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add(
    "dependency",
    flag_package(
      "dependency", "", "-I/shared -I /split -DVALUE=1", "-L/shared -L /split -lrepeat",
    ),
  )
  |> ignore
  packages.add(
    "app",
    flag_package(
      "app", "dependency", "-I/shared -I /split -DVALUE=1", "-L/shared -L /split -lrepeat",
    ),
  )
  |> ignore
  let cflags = packages.collect_cflags("app").deduplicate_search_paths()
  @debug.assert_eq(cflags.flags.map(f => f.value), [
    "-I/shared", "-I", "/split", "-DVALUE=1", "-DVALUE=1",
  ])
  @debug.assert_eq(cflags.flags[0].package_id, "dependency")
  let libs = packages.collect_libs("app").deduplicate_search_paths()
  @debug.assert_eq(libs.flags.map(f => f.value), [
    "-L/shared", "-L", "/split", "-lrepeat", "-lrepeat",
  ])
  @debug.assert_eq(libs.flags[0].package_id, "app")
}
