///|
fn graph_package(
  id : String,
  version : String,
  requires : String,
  private_requires~ : String = "",
  conflicts~ : String = "",
  provides~ : String = "",
) -> @moonpkgconfig.Document {
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
  @moonpkgconfig.parse(text.to_string(), source=id + ".pc")
}

///|
test "resolution diagnoses removed versions for roots dependencies and providers" {
  let packages = @moonpkgconfig.PackageSet::new()
  let document = graph_package("provider", "1", "", provides="virtual = 2")
  let version = document.field("Version").unwrap()
  packages.add("provider", document) |> ignore
  packages.add("root", graph_package("root", "1", "provider")) |> ignore
  packages.add("virtual-root", graph_package("virtual-root", "1", "virtual"))
  |> ignore
  packages.add(
    "conflict",
    graph_package("conflict", "1", "", conflicts="provider >= 2"),
  )
  |> ignore
  packages.add(
    "shared-root",
    graph_package("shared-root", "1", "root, virtual-root, conflict"),
  )
  |> ignore
  @debug.assert_eq(packages.resolve("root").diagnostics, [])
  let entries = document.entries.filter(entry => entry.name != "Version")
  document.entries.clear()
  for entry in entries {
    document.entries.push(entry)
  }
  for root in ["root", "virtual-root", "shared-root", "provider", "virtual"] {
    let result = packages.resolve(root)
    @debug.assert_eq(result.diagnostics.map(d => d.code), ["PC010"])
    @debug.assert_eq(result.diagnostics[0].location.source, "provider.pc")
  }
  @debug.assert_eq(packages.check_all().map(d => d.code), ["PC010"])
  document.entries.push(version)
  for root in ["root", "virtual-root", "shared-root", "provider", "virtual"] {
    @debug.assert_eq(packages.resolve(root).diagnostics, [])
  }
  @debug.assert_eq(packages.check_all(), [])
}

///|
test "resolution diagnoses directly inserted invalid package versions" {
  let packages = @moonpkgconfig.PackageSet::new()
  for
    (id, text, code) in [
      ("missing", "Name: Missing\nDescription: no version", "PC010"),
      ("empty", "Name: Empty\nDescription: empty version\nVersion:", "PC011"),
      (
        "spaces", "Name: Spaces\nDescription: invalid version\nVersion: 1 2", "PC012",
      ),
    ] {
    packages.packages[id] = { id, document: @moonpkgconfig.parse(text), }
    @debug.assert_eq(packages.resolve(id).diagnostics.map(d => d.code), [code])
  }
}

///|
test "removed package map entries do not abort provider or directory checks" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add(
    "provider",
    graph_package("provider", "1", "", provides="virtual = 2"),
  )
  |> ignore
  packages.add("root", graph_package("root", "1", "virtual")) |> ignore
  @debug.assert_eq(packages.resolve("root").diagnostics, [])
  packages.packages.remove("provider") |> ignore
  @debug.assert_eq(packages.resolve("root").diagnostics.map(d => d.code), [
    "PC015",
  ])
  @debug.assert_eq(packages.resolve("provider").diagnostics.map(d => d.code), [
    "PC015",
  ])
  @debug.assert_eq(packages.check_all().map(d => d.code), ["PC015", "PC015"])
  packages.packages["provider"] = {
    id: "provider",
    document: graph_package("provider", "1", "", provides="virtual = 2"),
  }
  @debug.assert_eq(packages.resolve("root").diagnostics, [])
  @debug.assert_eq(packages.check_all(), [])
}

///|
test "resolver returns dependencies before their dependants" {
  let packages = @moonpkgconfig.PackageSet::new()
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
  let packages = @moonpkgconfig.PackageSet::new()
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
  let packages = @moonpkgconfig.PackageSet::new()
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
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add("old", graph_package("old", "1", "")) |> ignore
  packages.add("app", graph_package("app", "1", "old >= 2, missing")) |> ignore
  let result = packages.resolve("app")
  @debug.assert_eq(result.diagnostics.map(d => d.code), ["PC016", "PC015"])
  @debug.assert_eq(result.order, ["app"])
}

///|
test "resolver reports a matching conflict between selected packages" {
  let packages = @moonpkgconfig.PackageSet::new()
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
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add("left", graph_package("left", "1", "", conflicts="right >= 4"))
  |> ignore
  packages.add("right", graph_package("right", "3", "")) |> ignore
  packages.add("app", graph_package("app", "1", "left, right")) |> ignore
  @debug.assert_eq(packages.resolve("app").diagnostics, [])
}

///|
test "resolver reports malformed conflict expressions at their field" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add("app", graph_package("app", "1", "", conflicts="other >="))
  |> ignore
  let result = packages.resolve("app")
  @debug.assert_eq(result.diagnostics.map(d => d.code), ["PC008"])
  @debug.assert_eq(result.diagnostics[0].location.source, "app.pc")
}

///|
test "resolver follows a versioned virtual package provider" {
  let packages = @moonpkgconfig.PackageSet::new()
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
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add(
    "fast-codec",
    graph_package("fast-codec", "7", "", provides="codec = 3"),
  )
  |> ignore
  @debug.assert_eq(packages.resolve("codec").order, ["fast-codec"])
}

///|
test "directory check includes private dependencies and removes repeats" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add("shared", graph_package("shared", "1", "missing")) |> ignore
  packages.add("left", graph_package("left", "1", "shared")) |> ignore
  packages.add("right", graph_package("right", "1", "shared")) |> ignore
  packages.add(
    "app",
    graph_package("app", "1", "left, right", private_requires="private-missing"),
  )
  |> ignore
  let diagnostics = packages.check_all()
  @debug.assert_eq(diagnostics.map(d => d.code), ["PC015", "PC015"])
  @debug.assert_eq(diagnostics.map(d => d.message), [
    "Required package not found: missing", "Required package not found: private-missing",
  ])
}
