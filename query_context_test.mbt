///|
test "provider index keeps first matching candidate and ignores malformed fields" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add(
    "malformed",
    graph_package("malformed", "1", "", provides="virtual = 9, broken >="),
  )
  |> ignore
  packages.add("old", graph_package("old", "1", "", provides="virtual = 1"))
  |> ignore
  packages.add(
    "first",
    graph_package("first", "1", "", provides="virtual = 3, virtual = 4"),
  )
  |> ignore
  packages.add("later", graph_package("later", "1", "", provides="virtual = 3"))
  |> ignore
  packages.add("root", graph_package("root", "1", "virtual >= 2")) |> ignore
  @debug.assert_eq(packages.resolve("root").order, ["first", "root"])
  @debug.assert_eq(packages.resolve("virtual").order, ["old"])
  @debug.assert_eq(packages.dependency_path("root", "first"), ["root", "first"])
  @debug.assert_eq(packages.dependency_path("root", "later"), [])
}

///|
test "exact package identifiers outrank virtual providers even on version failure" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add(
    "provider",
    graph_package("provider", "1", "", provides="virtual = 9"),
  )
  |> ignore
  packages.add("virtual", graph_package("virtual", "1", "")) |> ignore
  packages.add("root", graph_package("root", "1", "virtual >= 2")) |> ignore
  let result = packages.resolve("root")
  @debug.assert_eq(result.order, ["root"])
  @debug.assert_eq(result.diagnostics.map(d => d.code), ["PC016"])
  @debug.assert_eq(packages.dependency_paths("root").path_to("provider"), [])
  @debug.assert_eq(packages.resolve("virtual").order, ["virtual"])
}

///|
test "query caches observe additions and caller-owned document changes on the next call" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add("root", graph_package("root", "1", "virtual >= 2")) |> ignore
  assert_false(packages.resolve("root").diagnostics.is_empty())
  packages.add(
    "provider",
    graph_package("provider", "1", "", provides="virtual = 3"),
  )
  |> ignore
  @debug.assert_eq(packages.resolve("root").order, ["provider", "root"])
  let document = packages.get("provider").unwrap().document
  for i = 0; i < document.entries.length(); i = i + 1 {
    if document.entries[i].name == "Provides" {
      document.entries[i] = { ..document.entries[i], value: "virtual = 1", }
    }
  }
  @debug.assert_eq(packages.resolve("root").diagnostics.map(d => d.code), [
    "PC015",
  ])
  @debug.assert_eq(packages.dependency_paths("root").path_to("provider"), [])
  packages.add(
    "new-provider",
    graph_package("new-provider", "1", "", provides="virtual = 4"),
  )
  |> ignore
  @debug.assert_eq(packages.resolve("root").order, ["new-provider", "root"])
}

///|
test "cached traversal keeps public and private virtual parameter order" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add(
    "root",
    flag_package(
      "root",
      "public >= 2",
      "-I/root",
      "-lroot",
      private_requires="private >= 2",
    ),
  )
  |> ignore
  packages.add(
    "public-provider",
    @moonpkgconfig.parse(
      "Name: public\nDescription: provider\nVersion: 1\nProvides: public = 3\nCflags: -I/public\nLibs: -lpublic",
    ),
  )
  |> ignore
  packages.add(
    "private-provider",
    @moonpkgconfig.parse(
      "Name: private\nDescription: provider\nVersion: 1\nProvides: private = 3\nCflags: -I/private\nLibs: -lprivate",
    ),
  )
  |> ignore
  @debug.assert_eq(packages.collect_cflags("root").flags.map(f => f.value), [
    "-I/root", "-I/public", "-I/private",
  ])
  @debug.assert_eq(packages.collect_libs("root").flags.map(f => f.value), [
    "-lroot", "-lpublic",
  ])
  @debug.assert_eq(
    packages.collect_libs("root", static_linking=true).flags.map(f => f.value),
    ["-lroot", "-lpublic", "-lprivate"],
  )
}

///|
test "directory checks keep conflicts within each root's selected closure" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add("left", graph_package("left", "1", "", conflicts="right >= 1"))
  |> ignore
  packages.add("right", graph_package("right", "1", "")) |> ignore
  @debug.assert_eq(packages.check_all(), [])
  packages.add("root", graph_package("root", "1", "left, right")) |> ignore
  let result = packages.check_all()
  @debug.assert_eq(result.map(d => d.code), ["PC018"])
  @debug.assert_eq(result[0].message, "Package left conflicts with right 1")
  @debug.assert_eq(result[0].location.source, "left.pc")
}

///|
test "directory fast path preserves cycle and independent diagnostic order" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add("clean", graph_package("clean", "1", "")) |> ignore
  packages.add("a", graph_package("a", "1", "b, missing-a")) |> ignore
  packages.add("b", graph_package("b", "1", "a, missing-b")) |> ignore
  packages.add(
    "root",
    graph_package("root", "1", "clean, a", private_requires="missing-private"),
  )
  |> ignore
  let result = packages.check_all()
  @debug.assert_eq(result.map(d => d.code), [
    "PC017", "PC015", "PC015", "PC017", "PC017", "PC015",
  ])
  @debug.assert_eq(result.map(d => d.location.source), [
    "a", "b.pc", "a.pc", "b", "root", "root.pc",
  ])
  @debug.assert_eq(result[0].message, "Dependency cycle: a -> b -> a")
  @debug.assert_eq(result[3].message, "Dependency cycle: b -> a -> b")
  @debug.assert_eq(result[4].message, "Dependency cycle: root -> a -> b -> a")
  @debug.assert_eq(packages.check_all(include_private=false).length(), 5)
}

///|
test "directory classification does not hide malformed conflict or dependency fields" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add(
    "conflict",
    graph_package("conflict", "1", "", conflicts="missing >="),
  )
  |> ignore
  packages.add("dependency", graph_package("dependency", "1", "missing >="))
  |> ignore
  let result = packages.check_all()
  @debug.assert_eq(result.map(d => d.code), ["PC008", "PC008"])
  @debug.assert_eq(result.map(d => d.location.source), [
    "conflict.pc", "dependency.pc",
  ])
}

///|
test "directory checks reuse a deep clean graph and refresh between calls" {
  let packages = @moonpkgconfig.PackageSet::new()
  for i = 0; i < 5000; i = i + 1 {
    let requires = if i < 4999 { "p\{i + 1}" } else { "" }
    packages.add("p\{i}", graph_package("p\{i}", "1", requires)) |> ignore
  }
  @debug.assert_eq(packages.check_all(), [])
  packages.add("broken", graph_package("broken", "1", "missing")) |> ignore
  @debug.assert_eq(packages.check_all().map(d => d.code), ["PC015"])
}
