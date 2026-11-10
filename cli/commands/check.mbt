///|
fn check_usage(command : String) -> Unit {
  println("Usage: \{command} <directory> [--path <directory>]... [--json]")
  println(
    "Exit codes: 0 valid, 1 diagnostics found, 2 usage or directory error",
  )
}

///|
fn check_report(
  directories : Array[String],
  status : String,
  loaded : @loader.DirectoryLoad?,
  diagnostics : Array[@pc.Diagnostic],
  error : Json,
) -> Json {
  let diagnostic_document : @pc.Document = { entries: [], diagnostics, }
  let problems = match diagnostic_document.as_json() {
    Object({ "diagnostics": problems, .. }) => problems
    _ => abort("Document JSON must contain diagnostics")
  }
  let (file_count, package_count, package_ids) = match loaded {
    Some(result) =>
      (
        Json(result.file_count),
        Json(result.package_ids.length()),
        Json::array(result.package_ids.map(id => Json(id))),
      )
    None => (Json(null), Json(null), Json::array([]))
  }
  Json::object({
    "schema_version": Json(1),
    "command": Json("check"),
    "status": Json(status),
    "directories": Json::array(directories.map(directory => Json(directory))),
    "file_count": file_count,
    "package_count": package_count,
    "package_ids": package_ids,
    "diagnostics": problems,
    "error": error,
  })
}

///|
/// Check explicit directories in precedence order. JSON counts are null if
/// loading did not complete; an IO failure is never an empty successful check.
pub fn check(
  args : Array[String],
  command~ : String = "moon run cmd/check",
) -> Unit {
  let mut directory : String? = None
  let extra_paths : Array[String] = []
  let mut json = false
  let mut help = false
  let mut invalid = false
  let mut i = 1
  while i < args.length() {
    match args[i] {
      "--json" => json = true
      "--help" | "-h" => help = true
      "--path" =>
        if i + 1 >= args.length() || args[i + 1].has_prefix("-") {
          invalid = true
        } else {
          extra_paths.push(args[i + 1])
          i = i + 1
        }
      option =>
        if option.has_prefix("-") || directory is Some(_) {
          invalid = true
        } else {
          directory = Some(option)
        }
    }
    i = i + 1
  }
  if help {
    check_usage(command)
    return
  }
  let directories = match directory {
    Some(first) => [first, ..extra_paths]
    None => extra_paths
  }
  if invalid || directory is None {
    if json {
      println(
        check_report(
          directories,
          "usage_error",
          None,
          [],
          Json::object({
            "kind": Json("usage"),
            "message": Json(
              "Expected one directory, optional --path directories and --json",
            ),
          }),
        ).stringify(indent=2),
      )
    } else {
      check_usage(command)
    }
    @sys.exit(2)
    return
  }
  try {
    let loaded = @loader.load_directories(directories)
    let diagnostics = loaded.diagnostics.copy()
    for
      problem in loaded.packages.check_all(
        unavailable=loaded.diagnostics_by_package,
      ) {
      if !diagnostics.any(existing => existing == problem) {
        diagnostics.push(problem)
      }
    }
    if json {
      println(
        check_report(
          directories,
          if diagnostics.is_empty() {
            "ok"
          } else {
            "diagnostics"
          },
          Some(loaded),
          diagnostics,
          Json(null),
        ).stringify(indent=2),
      )
    } else {
      print_diagnostics(diagnostics)
      println(
        "Checked \{loaded.package_ids.length()} packages from \{loaded.file_count} .pc files; \{diagnostics.length()} diagnostics.",
      )
    }
    if !diagnostics.is_empty() {
      @sys.exit(1)
    }
  } catch {
    @fs.IOError(message) => {
      if json {
        println(
          check_report(
            directories,
            "io_error",
            None,
            [],
            Json::object({ "kind": Json("io"), "message": Json(message) }),
          ).stringify(indent=2),
        )
      } else {
        println("Could not check \{directories.join(", ")}: \{message}")
      }
      @sys.exit(2)
    }
  }
}
