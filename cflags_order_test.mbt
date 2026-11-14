///|
fn compiler_order_packages(
  graph : Array[(String, String, String)],
) -> @moonpkgconfig.PackageSet {
  let packages = @moonpkgconfig.PackageSet::new()
  for (id, public, private) in graph {
    packages.add(
      id,
      flag_package(
        id,
        public,
        "-I/include/" + id + " -D" + id,
        "",
        private_requires=private,
        private_cflags="-D" + id + "_private",
      ),
    )
    |> ignore
  }
  packages
}

///|
test "compiler search precedence completes independent branches before siblings" {
  let packages = compiler_order_packages([
    ("root", "a, b", ""),
    ("a", "x", ""),
    ("x", "", ""),
    ("b", "", "y"),
    ("y", "", ""),
  ])
  let result = packages.collect_cflags("root")
  @debug.assert_eq(result.diagnostics, [])
  @debug.assert_eq(result.flags.map(flag => flag.value), [
    "-I/include/root", "-Droot", "-I/include/a", "-Da", "-I/include/x", "-Dx", "-I/include/b",
    "-Db", "-I/include/y", "-Dy",
  ])
  @debug.assert_eq(
    result.select(@moonpkgconfig.IncludePaths).flags.map(flag => flag.value),
    [
      "-I/include/root", "-I/include/a", "-I/include/x", "-I/include/b", "-I/include/y",
    ],
  )
  // Querying another root in the same set cannot retain the first root's order.
  @debug.assert_eq(packages.collect_cflags("b").flags.map(flag => flag.value), [
    "-I/include/b", "-Db", "-I/include/y", "-Dy",
  ])
  @debug.assert_eq(packages.collect_cflags("a").flags.map(flag => flag.value), [
    "-I/include/a", "-Da", "-I/include/x", "-Dx",
  ])
}

///|
test "private compiler branches constrain public siblings and keep private fields last" {
  let packages = compiler_order_packages([
    ("root", "a, b", "hidden"),
    ("hidden", "b", "a"),
    ("a", "", ""),
    ("b", "", ""),
  ])
  let result = packages.collect_cflags("root", static_linking=true)
  @debug.assert_eq(result.diagnostics, [])
  @debug.assert_eq(result.flags.map(flag => flag.value), [
    "-I/include/root", "-Droot", "-I/include/hidden", "-Dhidden", "-I/include/b",
    "-Db", "-I/include/a", "-Da", "-Droot_private", "-Dhidden_private", "-Db_private",
    "-Da_private",
  ])
  @debug.assert_eq(result.flags.map(flag => flag.field), [
    "Cflags", "Cflags", "Cflags", "Cflags", "Cflags", "Cflags", "Cflags", "Cflags",
    "Cflags.private", "Cflags.private", "Cflags.private", "Cflags.private",
  ])
  @debug.assert_eq(result.flags.map(flag => flag.location.source), [
    "root.pc", "root.pc", "hidden.pc", "hidden.pc", "b.pc", "b.pc", "a.pc", "a.pc",
    "root.pc", "hidden.pc", "b.pc", "a.pc",
  ])
}

///|
test "repeated compiler dependency declarations retain last graph position and original flags" {
  let packages = compiler_order_packages([
    ("root", "a, b, a", ""),
    ("a", "", ""),
    ("b", "", ""),
  ])
  @debug.assert_eq(
    packages.collect_cflags("root").flags.map(flag => flag.value),
    ["-I/include/root", "-Droot", "-I/include/b", "-Db", "-I/include/a", "-Da"],
  )
  // Repeated arguments inside one field are lossless; callers can opt into
  // search-path deduplication independently of graph ordering.
  packages.add(
    "repeat",
    flag_package("repeat", "", "-I/same -I/same -DVALUE=1 -DVALUE=1", ""),
  )
  |> ignore
  let result = packages.collect_cflags("repeat")
  @debug.assert_eq(result.flags.map(flag => flag.value), [
    "-I/same", "-I/same", "-DVALUE=1", "-DVALUE=1",
  ])
  @debug.assert_eq(
    result.deduplicate_search_paths().flags.map(flag => flag.value),
    ["-I/same", "-DVALUE=1", "-DVALUE=1"],
  )
}

///|
test "compiler order resolves virtual private providers and preserves failures" {
  let packages = compiler_order_packages([
    ("root", "base, mid", ""),
    ("mid", "", "virtual >= 1"),
    ("base", "", ""),
  ])
  let provider = @moonpkgconfig.parse(
    "Name: provider\nDescription: compiler provider\nVersion: 1\nProvides: virtual = 1\nRequires: base\nCflags: -I/include/provider",
    source="provider.pc",
  )
  packages.add("provider", provider) |> ignore
  let result = packages.collect_cflags("root")
  @debug.assert_eq(result.diagnostics, [])
  @debug.assert_eq(result.flags.map(flag => flag.value), [
    "-I/include/root", "-Droot", "-I/include/mid", "-Dmid", "-I/include/provider",
    "-I/include/base", "-Dbase",
  ])
  let problem : @moonpkgconfig.Diagnostic = {
    code: "PC004",
    message: "Undefined variable: sdk",
    location: { source: "virtual.pc", line: 4, column: 8, },
  }
  @debug.assert_eq(
    packages.collect_cflags("root", unavailable={ "virtual": [problem] }).diagnostics,
    [problem],
  )
}

///|
test "compiler failures keep ordered partial flags and observe caller repairs" {
  let packages = compiler_order_packages([
    ("root", "base, mid", ""),
    ("mid", "", "base, missing"),
    ("base", "", ""),
  ])
  let failed = packages.collect_cflags("root")
  @debug.assert_eq(failed.diagnostics.map(problem => problem.code), ["PC015"])
  @debug.assert_eq(failed.diagnostics[0].location.source, "mid.pc")
  @debug.assert_eq(failed.flags.map(flag => flag.value), [
    "-I/include/root", "-Droot", "-I/include/mid", "-Dmid", "-I/include/base", "-Dbase",
  ])
  packages.add("missing", flag_package("missing", "", "-I/missing", ""))
  |> ignore
  @debug.assert_eq(packages.collect_cflags("root").diagnostics, [])
  packages.packages["mid"] = {
    id: "mid",
    document: @moonpkgconfig.parse(
      "Name: mid\nDescription: no version",
      source="mid.pc",
    ),
  }
  let invalid = packages.collect_cflags("root")
  @debug.assert_eq(invalid.diagnostics.map(problem => problem.code), ["PC010"])
  @debug.assert_eq(invalid.flags.map(flag => flag.value), [
    "-I/include/root", "-Droot", "-I/include/base", "-Dbase",
  ])
  packages.packages["mid"] = {
    id: "mid",
    document: flag_package("mid", "base", "-I/repaired", ""),
  }
  let repaired = packages.collect_cflags("root")
  @debug.assert_eq(repaired.diagnostics, [])
  @debug.assert_eq(repaired.flags.map(flag => flag.value), [
    "-I/include/root", "-Droot", "-I/repaired", "-I/include/base", "-Dbase",
  ])
  let cyclic = compiler_order_packages([
    ("root", "a", ""),
    ("a", "", "b"),
    ("b", "a", ""),
  ])
  let result = cyclic.collect_cflags("root")
  @debug.assert_eq(result.diagnostics.map(problem => problem.code), ["PC017"])
  assert_eq(result.flags.length(), 6)
}
