///|
fn graph_package(
  id : String,
  version : String,
  requires : String,
  private_requires? : String = "",
  conflicts? : String = "",
  provides? : String = "",
) -> Document {
  let text = StringBuilder()
  text.write_string(
    "Name: " + id + "\nDescription: graph fixture\nVersion: " + version,
  )
  if !requires.is_empty() {
    text.write_string("\nRequires: " + requires)
  }
  if !private_requires.is_empty() {
    text.write_string("\nRequires.private: " + private_requires)
  }
  if !conflicts.is_empty() {
    text.write_string("\nConflicts: " + conflicts)
  }
  if !provides.is_empty() {
    text.write_string("\nProvides: " + provides)
  }
  parse(text.to_string(), source=id + ".pc")
}

///|
test "resolver returns dependencies before their dependants" {
  let packages = PackageSet::new()
  packages.add("compression", graph_package("compression", "1", "")) |> ignore
  packages.add("codec", graph_package("codec", "2", "compression >= 1"))
  |> ignore
  packages.add("app", graph_package("app", "3", "codec >= 2")) |> ignore
  let result = packages.resolve("app")
  @debug.assert_eq(result.diagnostics, [])
  @debug.assert_eq(result.order, ["compression", "codec", "app"])
}

///|
test "private dependencies are opt in" {
  let packages = PackageSet::new()
  packages.add("static-helper", graph_package("static-helper", "1", ""))
  |> ignore
  packages.add(
    "app",
    graph_package("app", "1", "", private_requires="static-helper"),
  )
  |> ignore
  @debug.assert_eq(packages.resolve("app").order, ["app"])
  @debug.assert_eq(packages.resolve("app", include_private=true).order, [
    "static-helper", "app",
  ])
}

///|
test "resolver reports cycles without recursing forever" {
  let packages = PackageSet::new()
  packages.add("a", graph_package("a", "1", "b")) |> ignore
  packages.add("b", graph_package("b", "1", "c")) |> ignore
  packages.add("c", graph_package("c", "1", "a")) |> ignore
  let result = packages.resolve("a")
  @debug.assert_eq(result.diagnostics.map(d => d.code), ["PC017"])
  @debug.assert_eq(
    result.diagnostics[0].message,
    "Dependency cycle: a -> b -> c -> a",
  )
}

///|
test "resolver keeps independent transitive errors" {
  let packages = PackageSet::new()
  packages.add("old", graph_package("old", "1", "")) |> ignore
  packages.add("app", graph_package("app", "1", "old >= 2, missing")) |> ignore
  let result = packages.resolve("app")
  @debug.assert_eq(result.diagnostics.map(d => d.code), ["PC016", "PC015"])
  @debug.assert_eq(result.order, ["app"])
}

///|
test "resolver reports a matching conflict between selected packages" {
  let packages = PackageSet::new()
  packages.add("left", graph_package("left", "1", "", conflicts="right >= 3"))
  |> ignore
  packages.add("right", graph_package("right", "3", "")) |> ignore
  packages.add("app", graph_package("app", "1", "left, right")) |> ignore
  let result = packages.resolve("app")
  @debug.assert_eq(result.diagnostics.map(d => d.code), ["PC018"])
  @debug.assert_eq(result.diagnostics[0].location.source, "left.pc")
}

///|
test "resolver ignores a conflict whose version does not match" {
  let packages = PackageSet::new()
  packages.add("left", graph_package("left", "1", "", conflicts="right >= 4"))
  |> ignore
  packages.add("right", graph_package("right", "3", "")) |> ignore
  packages.add("app", graph_package("app", "1", "left, right")) |> ignore
  @debug.assert_eq(packages.resolve("app").diagnostics, [])
}

///|
test "resolver reports malformed conflict expressions at their field" {
  let packages = PackageSet::new()
  packages.add("app", graph_package("app", "1", "", conflicts="other >="))
  |> ignore
  let result = packages.resolve("app")
  @debug.assert_eq(result.diagnostics.map(d => d.code), ["PC008"])
  @debug.assert_eq(result.diagnostics[0].location.source, "app.pc")
}

///|
test "resolver follows a versioned virtual package provider" {
  let packages = PackageSet::new()
  packages.add(
    "fast-codec",
    graph_package("fast-codec", "7", "", provides="codec = 3"),
  )
  |> ignore
  packages.add("app", graph_package("app", "1", "codec >= 2")) |> ignore
  let result = packages.resolve("app")
  @debug.assert_eq(result.diagnostics, [])
  @debug.assert_eq(result.order, ["fast-codec", "app"])
}

///|
test "resolver can start from an unversioned virtual package name" {
  let packages = PackageSet::new()
  packages.add(
    "fast-codec",
    graph_package("fast-codec", "7", "", provides="codec = 3"),
  )
  |> ignore
  @debug.assert_eq(packages.resolve("codec").order, ["fast-codec"])
}
