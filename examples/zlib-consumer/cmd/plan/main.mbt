///|
fn main {
  let args = @env.args()
  if args.length() < 2 {
    println("Usage: plan <project-pc-directory> [dependency-pc-directory]...")
    @sys.exit(2)
  }
  let directories : Array[String] = []
  for i in 1..<args.length() {
    directories.push(args[i])
  }
  try {
    let loaded = @loader.load_directories(directories)
    let problems = loaded.diagnostics_for("compression-app")
    let cflags : @pc.FlagResult = if problems.is_empty() {
      loaded.packages.collect_cflags("compression-app")
    } else {
      { flags: [], diagnostics: problems, }
    }
    let libs : @pc.FlagResult = if problems.is_empty() {
      loaded.packages.collect_libs("compression-app", static_linking=true)
    } else {
      { flags: [], diagnostics: problems, }
    }
    let path = loaded.packages
      .dependency_paths("compression-app", include_private=true)
      .path_to("zlib")
    let version = match loaded.packages.get("zlib") {
      Some(pkg) => pkg.document.field("Version").unwrap().value
      None => ""
    }
    println(
      Json::object({
        "cflags": cflags.as_json(),
        "libs": libs.as_json(),
        "dependency_path": Json::array(path.map(part => Json(part))),
        "zlib_version": Json(version),
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
