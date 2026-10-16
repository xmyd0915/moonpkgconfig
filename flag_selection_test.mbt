///|
test "compiler selections preserve split paths, other operands and origins" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add(
    "app",
    flag_package(
      "app", "dep", "-I \"/sdk/include path\" -DAPP=1 -isystem /system -include -Iconfig.h",
      "",
    ),
  )
  |> ignore
  packages.add("dep", flag_package("dep", "", "-I/dep -pthread", "")) |> ignore
  let all = packages.collect_cflags("app")
  let includes = all.select(@moonpkgconfig.IncludePaths)
  @debug.assert_eq(includes.flags.map(f => f.value), [
    "-I", "/sdk/include path", "-I/dep",
  ])
  @debug.assert_eq(includes.flags, [all.flags[0], all.flags[1], all.flags[7]])
  @debug.assert_eq(
    all.select(@moonpkgconfig.OtherCflags).flags.map(f => f.value),
    ["-DAPP=1", "-isystem", "/system", "-include", "-Iconfig.h", "-pthread"],
  )
  @debug.assert_eq(includes.shell_text(), "-I '/sdk/include path' -I/dep")
  @debug.assert_eq(all.flags.length(), 9)
}

///|
test "linker selections retain library order and opaque option operands" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add(
    "app",
    flag_package(
      "app", "", "", "-L /sdk/lib -l app -pthread -framework -lFoundation -l:exact.a -lapp -lib:foreign -Xlinker -Lhidden",
    ),
  )
  |> ignore
  let all = packages.collect_libs("app")
  @debug.assert_eq(
    all.select(@moonpkgconfig.LibraryPaths).flags.map(f => f.value),
    ["-L", "/sdk/lib"],
  )
  @debug.assert_eq(
    all.select(@moonpkgconfig.Libraries).flags.map(f => f.value),
    ["-l", "app", "-l:exact.a", "-lapp"],
  )
  @debug.assert_eq(
    all.select(@moonpkgconfig.OtherLibs).flags.map(f => f.value),
    [
      "-pthread", "-framework", "-lFoundation", "-lib:foreign", "-Xlinker", "-Lhidden",
    ],
  )
}

///|
test "static selection includes private libraries without hiding diagnostics" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add(
    "app",
    flag_package(
      "app",
      "",
      "",
      "-lapp",
      private_requires="helper",
      private_libs="-lm",
    ),
  )
  |> ignore
  packages.add("helper", flag_package("helper", "", "", "-lhelper")) |> ignore
  @debug.assert_eq(
    packages.collect_libs("app").select(@moonpkgconfig.Libraries).flags.map(f => {
      f.value
    }),
    ["-lapp"],
  )
  @debug.assert_eq(
    packages
    .collect_libs("app", static_linking=true)
    .select(@moonpkgconfig.Libraries).flags.map(f => f.value),
    ["-lapp", "-lm", "-lhelper"],
  )
  let failed = packages.collect_libs("missing")
  let selected = failed.select(@moonpkgconfig.LibraryPaths)
  @debug.assert_eq(selected.flags, [])
  assert_true(!selected.diagnostics.is_empty())
  @debug.assert_eq(selected.diagnostics, failed.diagnostics)
}

///|
test "selection never binds split options across fields or packages" {
  let origin : @moonpkgconfig.Location = {
    source: "app.pc",
    line: 4,
    column: 1,
  }
  let result : @moonpkgconfig.FlagResult = {
    flags: [
      { value: "-I", package_id: "app", field: "Cflags", location: origin, },
      {
        value: "from-dependency",
        package_id: "dep",
        field: "Cflags",
        location: origin,
      },
      { value: "-L", package_id: "app", field: "Libs", location: origin, },
      {
        value: "-lprivate",
        package_id: "app",
        field: "Libs.private",
        location: origin,
      },
      {
        value: "-framework",
        package_id: "app",
        field: "Libs",
        location: origin,
      },
      {
        value: "-lnew-line",
        package_id: "app",
        field: "Libs",
        location: { ..origin, line: 5, },
      },
    ],
    diagnostics: [],
  }
  @debug.assert_eq(
    result.select(@moonpkgconfig.IncludePaths).flags.map(f => f.value),
    ["-I"],
  )
  @debug.assert_eq(
    result.select(@moonpkgconfig.LibraryPaths).flags.map(f => f.value),
    ["-L"],
  )
  @debug.assert_eq(
    result.select(@moonpkgconfig.Libraries).flags.map(f => f.value),
    ["-lprivate", "-lnew-line"],
  )
}

///|
test "selection composes with sysroot, exact filtering and path deduplication" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add(
    "app",
    flag_package(
      "app", "", "-I/usr/include -I /opt/include -I/opt/include -DKEEP=1", "",
    ),
  )
  |> ignore
  let all = packages.collect_cflags("app")
  let selected = all
    .filter_system_search_paths(["/usr/include"], [])
    .with_sysroot("/sdk")
    .deduplicate_search_paths()
    .select(@moonpkgconfig.IncludePaths)
  @debug.assert_eq(selected.flags.map(f => f.value), ["-I", "/sdk/opt/include"])
  @debug.assert_eq(selected.flags[0].location, all.flags[1].location)
  @debug.assert_eq(selected.flags[1].location, all.flags[2].location)
}

///|
test "GNU linker groups stay intact in other linker flags" {
  let packages = @moonpkgconfig.PackageSet::new()
  packages.add(
    "app",
    flag_package(
      "app", "", "", "-loutside -Wl,--start-group -lfirst -lsecond -Wl,--end-group -ltail",
    ),
  )
  |> ignore
  let all = packages.collect_libs("app")
  @debug.assert_eq(
    all.select(@moonpkgconfig.Libraries).flags.map(f => f.value),
    ["-loutside", "-ltail"],
  )
  @debug.assert_eq(
    all.select(@moonpkgconfig.OtherLibs).flags.map(f => f.value),
    ["-Wl,--start-group", "-lfirst", "-lsecond", "-Wl,--end-group"],
  )
}
