///|
fn private_order_packages(
  graph : Array[(String, String, String)],
) -> @moonpkgconfig.PackageSet {
  let packages = @moonpkgconfig.PackageSet::new()
  for (id, public, private) in graph {
    packages.add(
      id,
      flag_package(
        id,
        public,
        "-I/" + id,
        "-l" + id,
        private_requires=private,
        private_libs="-l" + id + "_private",
      ),
    )
    |> ignore
  }
  packages
}

///|
test "dynamic link order includes private constraints between public libraries" {
  let packages = private_order_packages([
    ("root", "base, mid", ""),
    ("mid", "", "base"),
    ("base", "", ""),
  ])
  let dynamic = packages.collect_libs("root")
  @debug.assert_eq(dynamic.diagnostics, [])
  @debug.assert_eq(dynamic.flags.map(flag => flag.value), [
    "-lroot", "-lmid", "-lbase",
  ])
  @debug.assert_eq(dynamic.flags.map(flag => flag.location.source), [
    "root.pc", "mid.pc", "base.pc",
  ])
  @debug.assert_eq(
    packages.collect_libs("root", static_linking=true).flags.map(flag => {
      flag.value
    }),
    [
      "-lroot", "-lroot_private", "-lmid", "-lmid_private", "-lbase", "-lbase_private",
    ],
  )
  @debug.assert_eq(
    packages.collect_cflags("root").flags.map(flag => flag.value),
    ["-I/root", "-I/base", "-I/mid"],
  )
}

///|
test "hidden private chains constrain shared libraries without emitting hidden flags" {
  let packages = private_order_packages([
    ("root", "base, mid", ""),
    ("mid", "", "hidden"),
    ("hidden", "base", ""),
    ("base", "", ""),
  ])
  @debug.assert_eq(
    packages.collect_libs("root").flags.map(flag => flag.value),
    ["-lroot", "-lmid", "-lbase"],
  )
  @debug.assert_eq(
    packages.collect_libs("root", static_linking=true).flags.map(flag => {
      flag.value
    }),
    [
      "-lroot", "-lroot_private", "-lmid", "-lmid_private", "-lhidden", "-lhidden_private",
      "-lbase", "-lbase_private",
    ],
  )
}

///|
test "private root branches preserve full graph tie ordering after filtering" {
  let packages = private_order_packages([
    ("root", "a, b", "hidden"),
    ("hidden", "b", "a"),
    ("a", "", ""),
    ("b", "", ""),
  ])
  @debug.assert_eq(
    packages.collect_libs("root").flags.map(flag => flag.value),
    ["-lroot", "-lb", "-la"],
  )
  let independent = private_order_packages([
    ("root", "a, b", ""),
    ("a", "x", ""),
    ("x", "", ""),
    ("b", "", "hidden"),
    ("hidden", "", ""),
  ])
  @debug.assert_eq(
    independent.collect_libs("root").flags.map(flag => flag.value),
    ["-lroot", "-la", "-lx", "-lb"],
  )
}

///|
test "private ordering uses virtual providers without making them public" {
  let packages = private_order_packages([
    ("root", "base, mid", ""),
    ("mid", "", "virtual >= 1"),
    ("base", "", ""),
  ])
  packages.add(
    "provider",
    graph_package("provider", "1", "base", provides="virtual = 1"),
  )
  |> ignore
  let result = packages.collect_libs("root")
  @debug.assert_eq(result.diagnostics, [])
  @debug.assert_eq(result.flags.map(flag => flag.value), [
    "-lroot", "-lmid", "-lbase",
  ])
}

///|
test "private cycles cannot reverse the valid public dependency order" {
  let packages = private_order_packages([
    ("root", "a, base", ""),
    ("a", "base", ""),
    ("base", "", "a"),
  ])
  let dynamic = packages.collect_libs("root")
  @debug.assert_eq(dynamic.diagnostics, [])
  @debug.assert_eq(dynamic.flags.map(flag => flag.value), [
    "-lroot", "-la", "-lbase",
  ])
  @debug.assert_eq(
    packages.collect_libs("root", static_linking=true).diagnostics.map(problem => {
      problem.code
    }),
    ["PC017"],
  )
}

///|
test "unavailable and incompatible private edges preserve dynamic diagnostics and order" {
  for (private, code) in [("missing", "PC015"), ("base >= 2", "PC016")] {
    let packages = private_order_packages([
      ("root", "base, mid", ""),
      ("mid", "", private),
      ("base", "", ""),
    ])
    let dynamic = packages.collect_libs("root")
    @debug.assert_eq(dynamic.diagnostics, [])
    @debug.assert_eq(dynamic.flags.map(flag => flag.value), [
      "-lroot", "-lbase", "-lmid",
    ])
    @debug.assert_eq(
      packages.collect_libs("root", static_linking=true).diagnostics.map(problem => {
        problem.code
      }),
      [code],
    )
  }
  let packages = private_order_packages([
    ("root", "base, mid", ""),
    ("mid", "", "broken"),
    ("base", "", ""),
  ])
  let original : @moonpkgconfig.Diagnostic = {
    code: "PC004",
    message: "Undefined variable: prefix",
    location: { source: "broken.pc", line: 4, column: 8, },
  }
  let unavailable = { "broken": [original] }
  @debug.assert_eq(packages.collect_libs("root", unavailable~).diagnostics, [])
  @debug.assert_eq(
    packages.collect_libs("root", unavailable~).flags.map(flag => flag.value),
    ["-lroot", "-lbase", "-lmid"],
  )
  @debug.assert_eq(
    packages.collect_libs("root", static_linking=true, unavailable~).diagnostics,
    [original],
  )
}
