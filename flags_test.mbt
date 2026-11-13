///|
fn flag_package(
  id : String,
  requires : String,
  cflags : String,
  libs : String,
  private_requires~ : String = "",
  private_libs~ : String = "",
  private_cflags~ : String = "",
) -> @moonpkgconfig.Document {
  let text = StringBuilder()
  text.write_string("Name: " + id + "\nDescription: flag fixture\nVersion: 1")
  if !requires.is_empty() {
    text.write_string("\nRequires: " + requires)
  }
  if !private_requires.is_empty() {
    text.write_string("\nRequires.private: " + private_requires)
  }
  if !libs.is_empty() {
    text.write_string("\nLibs: " + libs)
  }
  if !private_libs.is_empty() {
    text.write_string("\nLibs.private: " + private_libs)
  }
  if !cflags.is_empty() {
    text.write_string("\nCflags: " + cflags)
  }
  if !private_cflags.is_empty() {
    text.write_string("\nCflags.private: " + private_cflags)
  }
  @moonpkgconfig.parse(text.to_string(), source=id + ".pc")
}

///|
priv struct FlagGraphRandom {
  mut state : Int32
}

///|
fn FlagGraphRandom::next(self : FlagGraphRandom, bound : Int32) -> Int32 {
  self.state = (self.state * 25173 + 13849) % 65536
  self.state % bound
}

///|
fn FlagGraphRandom::shuffle(
  self : FlagGraphRandom,
  values : Array[Int32],
) -> Unit {
  for i = values.length() - 1; i > 0; i = i - 1 {
    let other = self.next(i + 1)
    let value = values[i]
    values[i] = values[other]
    values[other] = value
  }
}

///|
test "seeded dependency graphs preserve reachability multiplicity and link order" {
  let random = { state: 24301, }
  let mut repeated_edges = 0
  let mut private_edges = 0
  for _graph = 0; _graph < 600; _graph = _graph + 1 {
    let count = 3 + random.next(12)
    let public : Array[Array[Int32]] = []
    let private : Array[Array[Int32]] = []
    let packages = @moonpkgconfig.PackageSet::new()
    for node = 0; node < count; node = node + 1 {
      let ordinary : Array[Int32] = []
      let hidden : Array[Int32] = []
      for dependency = node + 1; dependency < count; dependency = dependency + 1 {
        if random.next(100) < 18 {
          ordinary.push(dependency)
        }
        if random.next(100) < 12 {
          hidden.push(dependency)
          private_edges = private_edges + 1
        }
      }
      if !ordinary.is_empty() && random.next(100) < 15 {
        ordinary.push(ordinary[random.next(ordinary.length())])
        repeated_edges = repeated_edges + 1
      }
      random.shuffle(ordinary)
      random.shuffle(hidden)
      public.push(ordinary)
      private.push(hidden)
      let id = "p" + node.to_string()
      @debug.assert_eq(
        packages.add(
          id,
          flag_package(
            id,
            ordinary.map(n => "p" + n.to_string()).join(", "),
            "",
            "-l" + id,
            private_requires=hidden.map(n => "p" + n.to_string()).join(", "),
            private_libs="-lq" + node.to_string(),
          ),
        ),
        [],
      )
    }
    for static_linking in [false, true] {
      // Derive reachability from the generated adjacency lists, independently
      // of PackageSet traversal and the order returned by the implementation.
      let reached : Map[Int32, Bool] = Map([])
      let pending = [0]
      for cursor = 0; cursor < pending.length(); cursor = cursor + 1 {
        let node = pending[cursor]
        if reached.contains(node) {
          continue
        }
        reached[node] = true
        for dependency in public[node] {
          pending.push(dependency)
        }
        if static_linking {
          for dependency in private[node] {
            pending.push(dependency)
          }
        }
      }
      let result = packages.collect_libs("p0", static_linking~)
      @debug.assert_eq(result.diagnostics, [])
      @debug.assert_eq(
        result.flags.length(),
        reached.length() * (if static_linking { 2 } else { 1 }),
      )
      let positions : Map[String, Int32] = Map([])
      let arguments : Map[String, Bool] = Map([])
      for index, flag in result.flags {
        @debug.assert_eq(arguments.contains(flag.value), false)
        arguments[flag.value] = true
        if flag.field == "Libs" {
          positions[flag.package_id] = index
        }
      }
      @debug.assert_eq(positions.length(), reached.length())
      for node, _ in reached {
        let id = "p" + node.to_string()
        @debug.assert_eq(arguments.contains("-l" + id), true)
        @debug.assert_eq(
          arguments.contains("-lq" + node.to_string()),
          static_linking,
        )
        let edges = public[node].copy()
        if static_linking {
          for dependency in private[node] {
            edges.push(dependency)
          }
        }
        for dependency in edges {
          @debug.assert_eq(
            positions[id] < positions["p" + dependency.to_string()],
            true,
          )
        }
      }
    }
  }
  @debug.assert_eq(repeated_edges > 0 && private_edges > 0, true)
}

///|
test "compiler flags put dependants before dependencies" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add("codec", flag_package("codec", "", "-I/codec", "-lcodec"))
  |> ignore
  packages.add("app", flag_package("app", "codec", "-I/app -DAPP=1", "-lapp"))
  |> ignore
  let result = packages.collect_cflags("app")
  @debug.assert_eq(result.diagnostics, [])
  @debug.assert_eq(result.flags.map(f => f.value), [
    "-I/app", "-DAPP=1", "-I/codec",
  ])
  @debug.assert_eq(result.flags.map(f => f.package_id), ["app", "app", "codec"])
  @debug.assert_eq(result.flags[0].location.source, "app.pc")
}

///|
test "linker flags put dependants before dependencies" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add("codec", flag_package("codec", "", "", "-lcodec")) |> ignore
  packages.add("app", flag_package("app", "codec", "", "-lapp")) |> ignore
  @debug.assert_eq(packages.collect_libs("app").flags.map(f => f.value), [
    "-lapp", "-lcodec",
  ])
}

///|
test "static linker flags include private edges and fields" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add("helper", flag_package("helper", "", "", "-lhelper")) |> ignore
  packages.add(
    "app",
    flag_package(
      "app",
      "",
      "",
      "-lapp",
      private_requires="helper",
      private_libs="-pthread",
    ),
  )
  |> ignore
  @debug.assert_eq(packages.collect_libs("app").flags.map(f => f.value), [
    "-lapp",
  ])
  @debug.assert_eq(
    packages.collect_libs("app", static_linking=true).flags.map(f => f.value),
    ["-lapp", "-pthread", "-lhelper"],
  )
}

///|
test "compiler flags include private dependency headers" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add("helper", flag_package("helper", "", "-I/helper", "-lhelper"))
  |> ignore
  packages.add(
    "app",
    flag_package("app", "", "-I/app", "-lapp", private_requires="helper"),
  )
  |> ignore
  @debug.assert_eq(packages.collect_cflags("app").flags.map(f => f.value), [
    "-I/app", "-I/helper",
  ])
  @debug.assert_eq(packages.collect_libs("app").flags.map(f => f.value), [
    "-lapp",
  ])
}

///|
test "flag tokenization errors retain the field source" {
  let packages = @moonpkgconfig.PackageSet::new()
  let bad = @moonpkgconfig.parse(
    "Name: bad\nDescription: bad flags\nVersion: 1\n  Cflags: 'unfinished",
    source="bad.pc",
  )
  packages.add("bad", bad) |> ignore
  let result = packages.collect_cflags("bad")
  @debug.assert_eq(result.diagnostics.map(d => d.code), ["PC006"])
  @debug.assert_eq(result.diagnostics[0].location.source, "bad.pc")
  @debug.assert_eq(result.diagnostics[0].location.line, 4)
  @debug.assert_eq(result.diagnostics[0].location.column, 22)
  @debug.assert_eq(result.flags, [])
}

///|
test "search path deduplication keeps other repeated flags and first origin" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add(
    "dependency",
    flag_package(
      "dependency", "", "-I/shared -I /split -I/mixed -DVALUE=1", "-L/shared -L /split -L/mixed -lrepeat",
    ),
  )
  |> ignore
  packages.add(
    "app",
    flag_package(
      "app", "dependency", "-I/shared -I /split -I /mixed -DVALUE=1", "-L/shared -L /split -L /mixed -lrepeat",
    ),
  )
  |> ignore
  let cflags = packages.collect_cflags("app").deduplicate_search_paths()
  @debug.assert_eq(cflags.flags.map(f => f.value), [
    "-I/shared", "-I", "/split", "-I", "/mixed", "-DVALUE=1", "-DVALUE=1",
  ])
  @debug.assert_eq(cflags.flags[0].package_id, "app")
  let libs = packages.collect_libs("app").deduplicate_search_paths()
  @debug.assert_eq(libs.flags.map(f => f.value), [
    "-L/shared", "-L", "/split", "-L", "/mixed", "-lrepeat", "-lrepeat",
  ])
  @debug.assert_eq(libs.flags[0].package_id, "app")
}

///|
test "search path operands never cross package or field boundaries" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add(
    "dependency",
    flag_package("dependency", "", "/dependency-first", "-ldependency"),
  )
  |> ignore
  packages.add("app", flag_package("app", "dependency", "-I", "-lapp"))
  |> ignore
  let result = packages.collect_cflags("app").deduplicate_search_paths()
  @debug.assert_eq(result.flags.map(flag => flag.value), [
    "-I", "/dependency-first",
  ])
  @debug.assert_eq(result.flags.map(flag => flag.package_id), [
    "app", "dependency",
  ])
}

///|
test "flag order keeps declared siblings stable in a diamond graph" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add("common", flag_package("common", "", "-I/common", "-lcommon"))
  |> ignore
  packages.add("left", flag_package("left", "common", "-I/left", "-lleft"))
  |> ignore
  packages.add("right", flag_package("right", "common", "-I/right", "-lright"))
  |> ignore
  packages.add("root", flag_package("root", "left, right", "-I/root", "-lroot"))
  |> ignore
  @debug.assert_eq(packages.collect_cflags("root").flags.map(f => f.value), [
    "-I/root", "-I/left", "-I/right", "-I/common",
  ])
  @debug.assert_eq(packages.collect_libs("root").flags.map(f => f.value), [
    "-lroot", "-lleft", "-lright", "-lcommon",
  ])
}

///|
test "triangle links defer shared dependencies and retain flag origins" {
  let packages = @moonpkgconfig.PackageSet::new()
  for
    (id, requires) in [
      ("root", "base, mid, base"),
      ("mid", "base"),
      ("base", ""),
    ] {
    packages.add(
      id,
      flag_package(
        id,
        requires,
        "-I/" + id,
        "-l" + id,
        private_libs="-l" + id + "-private",
        private_cflags="-D" + id + "_PRIVATE",
      ),
    )
    |> ignore
  }
  let dynamic = packages.collect_libs("root")
  @debug.assert_eq(dynamic.diagnostics, [])
  @debug.assert_eq(dynamic.flags.map(f => f.value), [
    "-lroot", "-lmid", "-lbase",
  ])
  @debug.assert_eq(dynamic.flags.map(f => f.package_id), ["root", "mid", "base"])
  @debug.assert_eq(dynamic.flags.map(f => f.location.source), [
    "root.pc", "mid.pc", "base.pc",
  ])
  @debug.assert_eq(
    packages.collect_libs("root", static_linking=true).flags.map(f => f.value),
    [
      "-lroot", "-lroot-private", "-lmid", "-lmid-private", "-lbase", "-lbase-private",
    ],
  )
  // Compiler paths remain breadth-first, with all private fields last.
  @debug.assert_eq(
    packages.collect_cflags("root", static_linking=true).flags.map(f => f.value),
    [
      "-I/root", "-I/base", "-I/mid", "-Droot_PRIVATE", "-Dbase_PRIVATE", "-Dmid_PRIVATE",
    ],
  )
}

///|
test "cross-level shared libraries follow every dependant" {
  let packages = @moonpkgconfig.PackageSet::new()
  for
    (id, requires) in [
      ("root", "left, right"),
      ("left", "shared"),
      ("right", "bridge"),
      ("bridge", "shared"),
      ("shared", ""),
    ] {
    packages.add(id, flag_package(id, requires, "-I/" + id, "-l" + id))
    |> ignore
  }
  let result = packages.collect_libs("root")
  @debug.assert_eq(result.diagnostics, [])
  @debug.assert_eq(result.flags.map(f => f.value), [
    "-lroot", "-lleft", "-lright", "-lbridge", "-lshared",
  ])
  @debug.assert_eq(packages.collect_cflags("root").flags.map(f => f.value), [
    "-I/root", "-I/left", "-I/right", "-I/shared", "-I/bridge",
  ])
}

///|
test "link branches keep declaration order and duplicate edges are stable" {
  let packages = @moonpkgconfig.PackageSet::new()
  for
    (id, requires) in [
      ("root", "a, b"),
      ("a", "x"),
      ("x", "y"),
      ("y", ""),
      ("b", "z"),
      ("z", ""),
    ] {
    packages.add(id, flag_package(id, requires, "", "-l" + id)) |> ignore
  }
  @debug.assert_eq(packages.collect_libs("root").flags.map(f => f.value), [
    "-lroot", "-la", "-lx", "-ly", "-lb", "-lz",
  ])
  // pkgconf 3.0.7 gives the final repeated dependency its last declared place.
  let repeated = @moonpkgconfig.PackageSet::new()
  repeated.add("root", flag_package("root", "a, b, a", "", "-lroot")) |> ignore
  repeated.add("a", flag_package("a", "", "", "-la -la")) |> ignore
  repeated.add("b", flag_package("b", "", "", "-lb")) |> ignore
  @debug.assert_eq(repeated.collect_libs("root").flags.map(f => f.value), [
    "-lroot", "-lb", "-la", "-la",
  ])
}

///|
test "private shared edges affect only static link order" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add(
    "root",
    flag_package("root", "base", "", "-lroot", private_requires="mid, base"),
  )
  |> ignore
  packages.add("mid", flag_package("mid", "base", "", "-lmid")) |> ignore
  packages.add("base", flag_package("base", "", "", "-lbase")) |> ignore
  @debug.assert_eq(packages.collect_libs("root").flags.map(f => f.value), [
    "-lroot", "-lbase",
  ])
  @debug.assert_eq(
    packages.collect_libs("root", static_linking=true).flags.map(f => f.value),
    ["-lroot", "-lmid", "-lbase"],
  )
}

///|
test "deep shared link graphs use an iterative dependency order" {
  let packages = @moonpkgconfig.PackageSet::new()
  let size = 5000
  packages.add("root", flag_package("root", "p4999, p0", "", "-lroot"))
  |> ignore
  for i = 0; i < size; i = i + 1 {
    let requires = if i + 1 < size { "p\{i + 1}" } else { "" }
    packages.add("p\{i}", flag_package("p\{i}", requires, "", "-lp\{i}"))
    |> ignore
  }
  let result = packages.collect_libs("root")
  @debug.assert_eq(result.diagnostics, [])
  assert_eq(result.flags.length(), size + 1)
  assert_eq(result.flags[0].value, "-lroot")
  for i = 0; i < size; i = i + 1 {
    assert_eq(result.flags[i + 1].value, "-lp\{i}")
  }
}

///|
test "dependency paths use the shortest valid public or private route" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add("common", flag_package("common", "", "", "-lcommon")) |> ignore
  packages.add("left", flag_package("left", "common", "", "-lleft")) |> ignore
  packages.add("right", flag_package("right", "common", "", "-lright"))
  |> ignore
  packages.add(
    "root",
    flag_package(
      "root",
      "left, right",
      "",
      "-lroot",
      private_requires="private-helper",
    ),
  )
  |> ignore
  packages.add(
    "private-helper",
    flag_package("private-helper", "", "", "-lprivate"),
  )
  |> ignore
  @debug.assert_eq(packages.dependency_path("root", "root"), ["root"])
  @debug.assert_eq(packages.dependency_path("root", "common"), [
    "root", "left", "common",
  ])
  @debug.assert_eq(packages.dependency_path("root", "private-helper"), [])
  @debug.assert_eq(
    packages.dependency_path("root", "private-helper", include_private=true),
    ["root", "private-helper"],
  )
}

///|
test "shell output preserves argument boundaries and literal characters" {
  let location : @moonpkgconfig.Location = {
    source: "quoted.pc",
    line: 1,
    column: 1,
  }
  let result : @moonpkgconfig.FlagResult = {
    flags: [
      {
        value: "-I/opt/sdk dir/include",
        package_id: "quoted",
        field: "Cflags",
        location,
      },
      { value: "-DNAME=a b", package_id: "quoted", field: "Cflags", location, },
      { value: "", package_id: "quoted", field: "Cflags", location, },
      { value: "plain", package_id: "quoted", field: "Cflags", location, },
      { value: "a'b", package_id: "quoted", field: "Cflags", location, },
      { value: "$HOME", package_id: "quoted", field: "Cflags", location, },
    ],
    diagnostics: [],
  }
  @debug.assert_eq(
    result.shell_text(),
    "'-I/opt/sdk dir/include' '-DNAME=a b' '' plain 'a'\\''b' '$HOME'",
  )
}

///|
test "sysroot rewrites absolute search paths and retains origins" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add(
    "paths",
    flag_package(
      "paths", "", "-I/usr/include -I relative -isystem /opt/system -isystemrelative -DKEEP=1",
      "-L/usr/lib -L relative -lpaths",
    ),
  )
  |> ignore
  let cflags = packages.collect_cflags("paths").with_sysroot("/sdk/")
  @debug.assert_eq(cflags.flags.map(f => f.value), [
    "-I/sdk/usr/include", "-I", "relative", "-isystem", "/sdk/opt/system", "-isystemrelative",
    "-DKEEP=1",
  ])
  @debug.assert_eq(cflags.flags.map(f => f.package_id), [
    "paths", "paths", "paths", "paths", "paths", "paths", "paths",
  ])
  @debug.assert_eq(
    packages.collect_libs("paths").with_sysroot("/sdk").flags.map(f => f.value),
    ["-L/sdk/usr/lib", "-L", "relative", "-lpaths"],
  )
}

///|
test "system path filtering is exact and limited to I and L flags" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add(
    "paths",
    flag_package(
      "paths", "", "-I/usr/include -I /usr/include -I/usr/include/project -isystem /usr/include -DKEEP=1",
      "-L/usr/lib -L /usr/lib -L/usr/lib/project -lpaths",
    ),
  )
  |> ignore
  let cflags = packages
    .collect_cflags("paths")
    .filter_system_search_paths(["/usr/include"], ["/usr/lib"])
  @debug.assert_eq(cflags.flags.map(f => f.value), [
    "-I/usr/include/project", "-isystem", "/usr/include", "-DKEEP=1",
  ])
  let libs = packages
    .collect_libs("paths")
    .filter_system_search_paths(["/usr/include"], ["/usr/lib"])
  @debug.assert_eq(libs.flags.map(f => f.value), [
    "-L/usr/lib/project", "-lpaths",
  ])
}

///|
test "sysroot composition keeps rewritten former system paths" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add(
    "paths",
    flag_package("paths", "", "-I/usr/include", "-L/usr/lib"),
  )
  |> ignore
  let cflags = packages
    .collect_cflags("paths")
    .with_sysroot("/sdk")
    .filter_system_search_paths(["/usr/include"], ["/usr/lib"])
  @debug.assert_eq(cflags.flags.map(f => f.value), ["-I/sdk/usr/include"])
}

///|
test "sysroot rewriting is idempotent at path component boundaries" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add(
    "paths",
    flag_package(
      "paths", "", "-I/sdk/include -I /sdk -I/sdk-other/include -I/usr/include -isystem /sdk/system -isystem/sdk/attached -DKEEP=/sdk",
      "-L/sdk/lib -L /sdk -L/sdk-other/lib -L/usr/lib -lpaths",
    ),
  )
  |> ignore
  let cflags = packages.collect_cflags("paths")
  let rewritten = cflags.with_sysroot("/sdk")
  @debug.assert_eq(rewritten.flags.map(f => f.value), [
    "-I/sdk/include", "-I", "/sdk", "-I/sdk/sdk-other/include", "-I/sdk/usr/include",
    "-isystem", "/sdk/system", "-isystem/sdk/attached", "-DKEEP=/sdk",
  ])
  @debug.assert_eq(rewritten.with_sysroot("/sdk"), rewritten)
  @debug.assert_eq(cflags.with_sysroot("/sdk/"), rewritten)
  @debug.assert_eq(
    rewritten.flags.map(f => f.location),
    cflags.flags.map(f => f.location),
  )
  let libs = packages.collect_libs("paths").with_sysroot("/sdk")
  @debug.assert_eq(libs.flags.map(f => f.value), [
    "-L/sdk/lib", "-L", "/sdk", "-L/sdk/sdk-other/lib", "-L/sdk/usr/lib", "-lpaths",
  ])
  @debug.assert_eq(libs.with_sysroot("/sdk"), libs)
}
