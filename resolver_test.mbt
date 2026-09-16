///|
fn graph_package(
  id : String,
  version : String,
  requires : String,
  private_requires? : String = "",
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
