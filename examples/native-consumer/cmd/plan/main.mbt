///|
fn main {
  let args = @env.args()
  if args.length() < 4 || (args[2] != "static" && args[2] != "dynamic") {
    println("Usage: plan <package> <static|dynamic> <pc-directory>...")
    @sys.exit(2)
  }
  let root = args[1]
  let static_linking = args[2] == "static"
  let directories : Array[String] = []
  for i in 3..<args.length() {
    directories.push(args[i])
  }
  try {
    let loaded = @loader.load_directories(directories)
    let cflags : @pc.FlagResult = loaded.packages.collect_cflags(
      root,
      static_linking~,
      unavailable=loaded.diagnostics_by_package,
    )
    let libs : @pc.FlagResult = loaded.packages.collect_libs(
      root,
      static_linking~,
      unavailable=loaded.diagnostics_by_package,
    )
    let paths = loaded.packages.dependency_paths(
      root,
      include_private=true,
      unavailable=loaded.diagnostics_by_package,
    )
    let dependencies : Array[Json] = []
    for id in loaded.package_ids {
      let route = paths.path_to(id)
      if !route.is_empty() {
        let pkg = loaded.packages.get(id).unwrap()
        dependencies.push(
          Json::object({
            "package": Json(id),
            "version": Json(pkg.document.field("Version").unwrap().value),
            "path": Json::array(route.map(part => Json(part))),
          }),
        )
      }
    }
    println(
      Json::object({
        "package": Json(root),
        "static": Json(static_linking),
        "cflags": cflags.as_json(),
        "libs": libs.as_json(),
        "dependencies": Json::array(dependencies),
      }).stringify(indent=2),
    )
    if !cflags.diagnostics.is_empty() || !libs.diagnostics.is_empty() {
      @sys.exit(1)
    }
  } catch {
    @fs.IOError(message) => {
      println("Could not read metadata: \{message}")
      @sys.exit(2)
    }
  }
}
