///|
fn unavailable_problem() -> @moonpkgconfig.Diagnostic {
  {
    code: "PC004",
    message: "Undefined variable: prefix",
    location: { source: "helper.pc", line: 2, column: 8, },
  }
}

///|
test "excluded dependencies retain their original diagnostics" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add("app", graph_package("app", "1", "helper")) |> ignore
  let unavailable = { "helper": [unavailable_problem()] }
  let result = packages.resolve("app", unavailable~)
  @debug.assert_eq(result.diagnostics, [unavailable_problem()])
  @debug.assert_eq(result.order, ["app"])
  @debug.assert_eq(packages.resolve("app").diagnostics.map(d => d.code), [
    "PC015",
  ])
  @debug.assert_eq(packages.resolve("helper", unavailable~).diagnostics, [
    unavailable_problem(),
  ])
  @debug.assert_eq(packages.collect_cflags("helper", unavailable~).flags, [])
}

///|
test "shared unavailable dependency diagnostics keep first occurrence order" {
  let packages = @moonpkgconfig.PackageSet::new()
  for
    (id, requires) in [
      ("app", "left right"),
      ("left", "helper"),
      ("right", "helper"),
    ] {
    packages.add(id, graph_package(id, "1", requires)) |> ignore
  }
  let other : @moonpkgconfig.Diagnostic = {
    code: "PC010",
    message: "Missing required field: Name",
    location: { source: "helper.pc", line: 1, column: 1, },
  }
  let problems = [unavailable_problem(), other]
  let unavailable = { "helper": problems }
  let result = packages.resolve("app", unavailable~)
  @debug.assert_eq(result.diagnostics, problems)
  result.diagnostics.clear()
  @debug.assert_eq(problems.length(), 2)
  @debug.assert_eq(
    packages.collect_libs("app", unavailable~).diagnostics,
    problems,
  )
}

///|
test "unavailable private dependencies follow compiler and linker query modes" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add(
    "app",
    flag_package("app", "", "-I/app", "-lapp", private_requires="helper"),
  )
  |> ignore
  let unavailable = { "helper": [unavailable_problem()] }
  @debug.assert_eq(packages.collect_libs("app", unavailable~).diagnostics, [])
  @debug.assert_eq(
    packages.collect_libs("app", unavailable~).flags.map(f => f.value),
    ["-lapp"],
  )
  @debug.assert_eq(
    packages.collect_libs("app", static_linking=true, unavailable~).diagnostics,
    [unavailable_problem()],
  )
  @debug.assert_eq(packages.collect_cflags("app", unavailable~).diagnostics, [
    unavailable_problem(),
  ])
  @debug.assert_eq(packages.resolve("app", unavailable~).diagnostics, [])
  @debug.assert_eq(
    packages.resolve("app", include_private=true, unavailable~).diagnostics,
    [unavailable_problem()],
  )
}

///|
test "an excluded exact filename blocks virtual provider fallback" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add("app", graph_package("app", "1", "helper >= 1")) |> ignore
  packages.add(
    "provider",
    graph_package("provider", "1", "", provides="helper = 2"),
  )
  |> ignore
  let unavailable = { "helper": [unavailable_problem()] }
  @debug.assert_eq(packages.resolve("app").diagnostics, [])
  @debug.assert_eq(packages.resolve("app", unavailable~).diagnostics, [
    unavailable_problem(),
  ])
  @debug.assert_eq(packages.resolve("helper", unavailable~).diagnostics, [
    unavailable_problem(),
  ])
  @debug.assert_eq(packages.dependency_path("app", "provider"), [
    "app", "provider",
  ])
  @debug.assert_eq(packages.dependency_path("app", "provider", unavailable~), [])
  @debug.assert_eq(
    packages.dependency_paths("app", unavailable~).path_to("provider"),
    [],
  )
}

///|
test "unrelated and empty unavailable entries do not poison valid queries" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add("app", graph_package("app", "1", "helper")) |> ignore
  packages.add(
    "provider",
    graph_package("provider", "1", "", provides="helper = 2"),
  )
  |> ignore
  let unavailable = { "other": [unavailable_problem()], "helper": [] }
  @debug.assert_eq(packages.resolve("app", unavailable~).diagnostics, [])
  @debug.assert_eq(packages.check_all(unavailable~), [])
}

///|
test "a rejected version does not report unreachable source failures" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add("app", graph_package("app", "1", "old >= 2")) |> ignore
  packages.add("old", graph_package("old", "1", "helper")) |> ignore
  let unavailable = { "helper": [unavailable_problem()] }
  @debug.assert_eq(
    packages.resolve("app", unavailable~).diagnostics.map(d => d.code),
    ["PC016"],
  )
}

///|
test "unavailable state refreshes and valid exact packages have precedence" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add("app", graph_package("app", "1", "helper")) |> ignore
  let unavailable = { "helper": [unavailable_problem()] }
  @debug.assert_eq(packages.resolve("app", unavailable~).diagnostics, [
    unavailable_problem(),
  ])
  unavailable.clear()
  @debug.assert_eq(
    packages.resolve("app", unavailable~).diagnostics.map(d => d.code),
    ["PC015"],
  )
  unavailable["helper"] = [unavailable_problem()]
  packages.add("helper", graph_package("helper", "1", "")) |> ignore
  @debug.assert_eq(packages.resolve("app", unavailable~).diagnostics, [])
  @debug.assert_eq(packages.resolve("helper", unavailable~).diagnostics, [])
}

///|
test "directory checking does not mark unavailable edges as clean" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add("app", graph_package("app", "1", "helper")) |> ignore
  packages.add(
    "provider",
    graph_package("provider", "1", "", provides="helper = 2"),
  )
  |> ignore
  let unavailable = { "helper": [unavailable_problem()] }
  @debug.assert_eq(packages.check_all(unavailable~), [unavailable_problem()])
}
