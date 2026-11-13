///|
test "metadata selection ignores missing and malformed dependency declarations" {
  let packages = @moonpkgconfig.PackageSet::new()
  for
    (id, requires, private_requires) in [
      ("public", "absent", ""),
      ("private", "", "absent"),
      ("malformed", "broken >=", "broken == 2"),
    ] {
    packages.add(id, graph_package(id, "2", requires, private_requires~))
    |> ignore
    let selected = packages.select(id).unwrap()
    @debug.assert_eq(selected.id, id)
    @debug.assert_eq(selected.document.field("Version").unwrap().value, "2")
    assert_false(
      packages.resolve(id, include_private=true).diagnostics.is_empty(),
    )
  }
  @debug.assert_eq(packages.resolve("private").diagnostics, [])
}

///|
test "metadata selection preserves exact and virtual root precedence" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add(
    "first",
    graph_package("first", "1", "missing", provides="virtual = 1"),
  )
  |> ignore
  packages.add(
    "second",
    graph_package("second", "2", "", provides="virtual = 2"),
  )
  |> ignore
  @debug.assert_eq(packages.select("virtual").unwrap().id, "first")
  let original : @moonpkgconfig.Diagnostic = {
    code: "PC019",
    message: "Metadata file cannot be read",
    location: { source: "first-directory/virtual.pc", line: 1, column: 1, },
  }
  let unavailable = { "virtual": [original] }
  @debug.assert_eq(packages.select("virtual", unavailable~), Err([original]))
  match packages.select("virtual", unavailable~) {
    Err(problems) => problems.clear()
    Ok(_) =>
      fail("the first unavailable exact file must block provider fallback")
  }
  @debug.assert_eq(unavailable["virtual"], [original])
  @debug.assert_eq(
    packages.select("virtual", unavailable={ "virtual": [] }).unwrap().id,
    "first",
  )
  packages.add("virtual", graph_package("virtual", "3", "missing")) |> ignore
  @debug.assert_eq(
    packages.select("virtual", unavailable~).unwrap().id,
    "virtual",
  )
  packages.packages.remove("virtual") |> ignore
  @debug.assert_eq(packages.select("virtual", unavailable~), Err([original]))
  packages.packages.remove("first") |> ignore
  @debug.assert_eq(packages.select("virtual").unwrap().id, "second")
}

///|
test "metadata selection returns original document failures before metadata checks" {
  let packages = @moonpkgconfig.PackageSet::new()
  let document = @moonpkgconfig.parse(
    "Name: bad\nDescription: failed field\nVersion: 1\nLibs: ${missing}",
    source="source/bad.pc",
  )
  packages.packages["bad"] = { id: "bad", document, }
  @debug.assert_eq(packages.select("bad"), Err(document.diagnostics))
  match packages.select("bad") {
    Err(problems) => problems.clear()
    Ok(_) => fail("document diagnostics must remain visible")
  }
  @debug.assert_eq(document.diagnostics[0].location, {
    source: "source/bad.pc",
    line: 4,
    column: 7,
  })
  let stopped = @moonpkgconfig.parse(
    "invalid\n".repeat(101),
    source="stopped.pc",
  )
  packages.packages["stopped"] = { id: "stopped", document: stopped, }
  @debug.assert_eq(packages.select("stopped"), Err(stopped.diagnostics))
}

///|
test "metadata selection observes caller mutations and repairs without stale state" {
  let packages = @moonpkgconfig.PackageSet::new()
  let document = graph_package(
    "changed",
    "1",
    "missing",
    provides="virtual = 1",
  )
  packages.add("changed", document) |> ignore
  @debug.assert_eq(packages.select("virtual").unwrap().id, "changed")
  let version = document.field("Version").unwrap()
  for i = 0; i < document.entries.length(); i = i + 1 {
    if document.entries[i].name == "Version" {
      document.entries[i] = { ..version, value: "1 2", }
    }
  }
  for root in ["changed", "virtual"] {
    match packages.select(root) {
      Err(problems) => {
        @debug.assert_eq(problems.map(problem => problem.code), ["PC012"])
        @debug.assert_eq(problems[0].location, version.location)
      }
      Ok(_) => fail("an invalid version must not be selected")
    }
  }
  let retained = document.entries.filter(entry => entry.name != "Version")
  document.entries.clear()
  for entry in retained {
    document.entries.push(entry)
  }
  match packages.select("changed") {
    Err(problems) => {
      @debug.assert_eq(problems.map(problem => problem.code), ["PC010"])
      @debug.assert_eq(problems[0].location.source, "changed.pc")
    }
    Ok(_) => fail("a removed version must not be selected")
  }
  document.entries.push(version)
  @debug.assert_eq(
    packages.select("changed").unwrap().document.field("Version"),
    Some(version),
  )
  packages.packages.remove("changed") |> ignore
  match packages.select("virtual", source="caller") {
    Err(problems) => {
      @debug.assert_eq(problems.map(problem => problem.code), ["PC015"])
      @debug.assert_eq(problems[0].location.source, "caller")
    }
    Ok(_) => fail("removed map entries cannot remain selectable")
  }
}
