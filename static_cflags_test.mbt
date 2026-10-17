///|
test "static compiler flags include private fields across dependency edges" {
  let packages = @moonpkgconfig.PackageSet::new()
  for (id, requires) in [("app", "helper"), ("helper", "")] {
    let document = @moonpkgconfig.parse(
      "Name: " +
      id +
      "\nDescription: static fixture\nVersion: 1\n" +
      "Requires.private: " +
      requires +
      "\nCflags: -I/" +
      id +
      "\nCflags.private: -D" +
      id +
      "_STATIC",
      source=id + ".pc",
    )
    @debug.assert_eq(packages.add(id, document), [])
  }
  @debug.assert_eq(packages.collect_cflags("app").flags.map(f => f.value), [
    "-I/app", "-I/helper",
  ])
  let result = packages.collect_cflags("app", static_linking=true)
  @debug.assert_eq(result.diagnostics, [])
  @debug.assert_eq(result.flags.map(f => f.value), [
    "-I/app", "-I/helper", "-Dapp_STATIC", "-Dhelper_STATIC",
  ])
  @debug.assert_eq(result.flags.map(f => f.field), [
    "Cflags", "Cflags", "Cflags.private", "Cflags.private",
  ])
  @debug.assert_eq(result.flags[2].location, {
    source: "app.pc",
    line: 6,
    column: 1,
  })
  @debug.assert_eq(result.select(OtherCflags).flags.map(f => f.value), [
    "-Dapp_STATIC", "-Dhelper_STATIC",
  ])
}

///|
test "private compiler fragment errors are checked only in static queries" {
  let packages = @moonpkgconfig.PackageSet::new()
  let document = @moonpkgconfig.parse(
    "Name: app\nDescription: private fragment\nVersion: 1\n" +
    "Cflags: -I/app\n  Cflags.private: 'unfinished",
    source="private.pc",
  )
  @debug.assert_eq(packages.add("app", document), [])
  @debug.assert_eq(packages.collect_cflags("app").diagnostics, [])
  let result = packages.collect_cflags("app", static_linking=true)
  @debug.assert_eq(result.diagnostics.map(d => d.code), ["PC006"])
  @debug.assert_eq(result.diagnostics[0].location, {
    source: "private.pc",
    line: 5,
    column: 30,
  })
}

///|
test "private compiler operands cannot bind public field operands" {
  let packages = @moonpkgconfig.PackageSet::new()
  let document = @moonpkgconfig.parse(
    "Name: app\nDescription: origin boundary\nVersion: 1\n" +
    "Cflags: -I\nCflags.private: /private -I /private -DSTATIC",
  )
  @debug.assert_eq(packages.add("app", document), [])
  let result = packages.collect_cflags("app", static_linking=true)
  @debug.assert_eq(
    result.with_sysroot("/sdk").deduplicate_search_paths().flags.map(f => {
      f.value
    }),
    ["-I", "/private", "-I", "/sdk/private", "-DSTATIC"],
  )
}
