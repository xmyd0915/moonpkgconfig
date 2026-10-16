///|
test "path snapshots preserve public tie order and shorter private routes" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add(
    "root",
    graph_package("root", "1", "left, right", private_requires="leaf"),
  )
  |> ignore
  packages.add("left", graph_package("left", "1", "leaf")) |> ignore
  packages.add("right", graph_package("right", "1", "leaf")) |> ignore
  packages.add("leaf", graph_package("leaf", "1", "root")) |> ignore
  let public_paths = packages.dependency_paths("root")
  @debug.assert_eq(public_paths.path_to("leaf"), ["root", "left", "leaf"])
  @debug.assert_eq(public_paths.path_to("root"), ["root"])
  @debug.assert_eq(public_paths.path_to("missing"), [])
  @debug.assert_eq(
    packages.dependency_paths("root", include_private=true).path_to("leaf"),
    ["root", "leaf"],
  )
}

///|
test "path snapshots retain virtual providers and reject invalid version edges" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add(
    "provider",
    graph_package("provider", "1", "old >= 2", provides="virtual = 3"),
  )
  |> ignore
  packages.add("old", graph_package("old", "1", "")) |> ignore
  let paths = packages.dependency_paths("virtual")
  @debug.assert_eq(paths.path_to("provider"), ["provider"])
  @debug.assert_eq(paths.path_to("old"), [])
  @debug.assert_eq(packages.dependency_paths("missing").path_to("old"), [])
}

///|
test "paths are fresh arrays and snapshots do not track later package additions" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add("root", graph_package("root", "1", "leaf")) |> ignore
  let before = packages.dependency_paths("root")
  packages.add("leaf", graph_package("leaf", "1", "")) |> ignore
  @debug.assert_eq(before.path_to("leaf"), [])
  let after = packages.dependency_paths("root")
  let changed = after.path_to("leaf")
  changed[0] = "changed"
  @debug.assert_eq(after.path_to("leaf"), ["root", "leaf"])
}

///|
test "deep graphs resolve and explain without recursive traversal" {
  let packages = @moonpkgconfig.PackageSet::new()
  let size = 5000
  for i = 0; i < size; i = i + 1 {
    let requires = if i + 1 < size { "p\{i + 1}" } else { "" }
    packages.add("p\{i}", graph_package("p\{i}", "1", requires)) |> ignore
  }
  let resolution = packages.resolve("p0")
  @debug.assert_eq(resolution.diagnostics, [])
  assert_eq(resolution.order.length(), size)
  assert_eq(resolution.order[0], "p4999")
  assert_eq(resolution.order[size - 1], "p0")
  let path = packages.dependency_paths("p0").path_to("p4999")
  assert_eq(path.length(), size)
  assert_eq(path[0], "p0")
  assert_eq(path[size - 1], "p4999")
}

///|
test "iterative resolution keeps depth-first diagnostic and private field order" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add(
    "root",
    graph_package(
      "root",
      "1",
      "left, old >= 2, missing-root",
      private_requires="private >=",
    ),
  )
  |> ignore
  packages.add("left", graph_package("left", "1", "root, missing-left"))
  |> ignore
  packages.add("old", graph_package("old", "1", "")) |> ignore
  let result = packages.resolve(
    "root",
    include_private=true,
    source="root-query",
  )
  @debug.assert_eq(result.order, ["left", "root"])
  @debug.assert_eq(result.diagnostics.map(d => d.code), [
    "PC017", "PC015", "PC016", "PC015", "PC008",
  ])
  @debug.assert_eq(
    result.diagnostics[0].message,
    "Dependency cycle: root -> left -> root",
  )
  @debug.assert_eq(result.diagnostics[0].location.source, "root-query")
  @debug.assert_eq(result.diagnostics[1].location.source, "left.pc")
  @debug.assert_eq(result.diagnostics[4].location.source, "root.pc")
}
