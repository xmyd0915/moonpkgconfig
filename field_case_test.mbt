///|
test "known field case is ignored throughout dependency and flag queries" {
  let packages = @moonpkgconfig.PackageSet::new()
  let root = @moonpkgconfig.parse(
    "nAmE: root\ndEsCrIpTiOn: case fixture\nvErSiOn: 1\nuRl: https://example.invalid\n  rEqUiReS: virtual >= 2\nrEqUiReS.pRiVaTe: helper\ncFlAgS: -I/root\ncFlAgS.pRiVaTe: -DROOT_PRIVATE\nlIbS: -lroot\nlIbS.pRiVaTe: -lm",
    source="root.pc",
  )
  @debug.assert_eq(packages.add("root", root), [])
  @debug.assert_eq(
    packages.add(
      "codec",
      @moonpkgconfig.parse(
        "NAME: codec\nDESCRIPTION: provider\nVERSION: 2\nPROVIDES: virtual = 2\nCFLAGS: -I/codec\nLIBS: -lcodec\nCONFLICTS: root > 9",
        source="codec.pc",
      ),
    ),
    [],
  )
  @debug.assert_eq(packages.add("helper", graph_package("helper", "1", "")), [])
  @debug.assert_eq(packages.resolve("root", include_private=true).diagnostics, [])
  @debug.assert_eq(
    packages.collect_libs("root", static_linking=true).flags.map(f => f.value),
    ["-lroot", "-lm", "-lcodec"],
  )
  let cflags = packages.collect_cflags("root", static_linking=true)
  @debug.assert_eq(cflags.diagnostics, [])
  @debug.assert_eq(cflags.flags.map(f => f.value), [
    "-I/root", "-I/codec", "-DROOT_PRIVATE",
  ])
  @debug.assert_eq(cflags.flags[0].field, "Cflags")
  let requires = root.field("REQUIRES").unwrap()
  @debug.assert_eq(requires.name, "rEqUiReS")
  @debug.assert_eq(requires.raw, "virtual >= 2")
  @debug.assert_eq(requires.location, { source: "root.pc", line: 5, column: 3, })
  @debug.assert_eq(root.field("URL").unwrap().value, "https://example.invalid")
}

///|
test "case variants of every standard field are duplicate definitions" {
  for
    (canonical, other) in [
      ("Name", "NAME"),
      ("Description", "DESCRIPTION"),
      ("Version", "VERSION"),
      ("URL", "url"),
      ("Requires", "REQUIRES"),
      ("Requires.private", "REQUIRES.PRIVATE"),
      ("Conflicts", "CONFLICTS"),
      ("Provides", "PROVIDES"),
      ("Cflags", "CFLAGS"),
      ("Cflags.private", "CFLAGS.PRIVATE"),
      ("Libs", "LIBS"),
      ("Libs.private", "LIBS.PRIVATE"),
    ] {
    let doc = @moonpkgconfig.parse(
      canonical + ": first\n  " + other + ": second",
      source="duplicates.pc",
    )
    @debug.assert_eq(doc.diagnostics.map(d => d.code), ["PC005"])
    @debug.assert_eq(doc.field(other).unwrap().name, canonical)
    @debug.assert_eq(doc.field(other).unwrap().value, "first")
    @debug.assert_eq(doc.diagnostics[0].location, {
      source: "duplicates.pc",
      line: 2,
      column: 3,
    })
  }
}

///|
test "public document field lookup handles manually supplied original names" {
  let entry = @moonpkgconfig.parse("Libs: -lmanual", source="manual.pc").entries[0]
  let document : @moonpkgconfig.Document = {
    entries: [{ ..entry, name: "lIbS", }],
    diagnostics: [],
  }
  @debug.assert_eq(document.field("LIBS"), Some({ ..entry, name: "lIbS", }))
  @debug.assert_eq(document.entries[0].raw, "-lmanual")
}
