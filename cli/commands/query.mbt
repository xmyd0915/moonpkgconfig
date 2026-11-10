///|
priv enum QueryMode {
  Cflags(@pc.FlagSelection?)
  Libs(@pc.FlagSelection?)
  Variable(String)
  ModVersion
  Exists
  AtLeastVersion(String)
  ExactVersion(String)
  MaxVersion(String)
}

///|
fn query_usage(command : String) -> Unit {
  println(
    "Usage: \{command} <directory> <package> <mode> [--path <directory>]... [options]",
  )
  println(
    "Modes: --cflags, --libs, --variable=<name>, --modversion, --exists, --atleast-version=<version>, --exact-version=<version>, --max-version=<version>",
  )
  println(
    "       --cflags-only-I, --cflags-only-other, --libs-only-L, --libs-only-l, --libs-only-other",
  )
  println(
    "Options: --define-variable=<name>=<value>, --path <directory>, --sysroot=<path>",
  )
  println("         --system-include-path=<path>, --system-library-path=<path>")
  println("         --static, --dedupe-paths, --json, --explain")
}

///|
fn valid_variable_name(name : String) -> Bool {
  !name.is_empty() &&
  name
  .iter()
  .all(c => {
    (c >= 'a' && c <= 'z') ||
    (c >= 'A' && c <= 'Z') ||
    (c >= '0' && c <= '9') ||
    c == '_' ||
    c == '.' ||
    c == '-'
  })
}

///|
fn print_diagnostics(diagnostics : Array[@pc.Diagnostic]) -> Unit {
  for problem in diagnostics {
    println(
      "\{problem.code} \{problem.location.source}:\{problem.location.line}:\{problem.location.column} \{problem.message}",
    )
  }
}

///|
fn print_flags(
  result : @pc.FlagResult,
  explain : Bool,
  packages : @pc.PackageSet,
  root : String,
  include_private : Bool,
  unavailable : Map[String, Array[@pc.Diagnostic]],
) -> Unit {
  println(result.shell_text())
  if explain {
    let paths = packages.dependency_paths(root, include_private~, unavailable~)
    for flag in result.flags {
      let path = paths.path_to(flag.package_id)
      let path_text = if path.is_empty() {
        flag.package_id
      } else {
        path.join(" -> ")
      }
      println(
        "  \{flag.value} <- \{flag.package_id}:\{flag.field} [\{flag.location.source}:\{flag.location.line}; via \{path_text}]",
      )
    }
  }
  print_diagnostics(result.diagnostics)
}

///|
fn query_mode_text(mode : QueryMode) -> String {
  match mode {
    Cflags(None) => "--cflags"
    Libs(None) => "--libs"
    Cflags(Some(group)) | Libs(Some(group)) =>
      match group {
        IncludePaths => "--cflags-only-I"
        OtherCflags => "--cflags-only-other"
        LibraryPaths => "--libs-only-L"
        Libraries => "--libs-only-l"
        OtherLibs => "--libs-only-other"
      }
    Variable(name) => "--variable=\{name}"
    ModVersion => "--modversion"
    Exists => "--exists"
    AtLeastVersion(version) => "--atleast-version=\{version}"
    ExactVersion(version) => "--exact-version=\{version}"
    MaxVersion(version) => "--max-version=\{version}"
  }
}

///|
fn query_report(
  directories : Array[String],
  package_name : String?,
  mode : QueryMode?,
  static_linking : Bool,
  result : @pc.FlagResult,
  status~ : String = "ok",
  error~ : Json = Json(null),
  value~ : Json = Json(null),
  matched~ : Json = Json(null),
  paths~ : Json = Json(null),
) -> Unit {
  let (flags, diagnostics) = match result.as_json() {
    Object({ "flags": flags, "diagnostics": diagnostics, .. }) =>
      (flags, diagnostics)
    _ => abort("Flag JSON must contain flags and diagnostics")
  }
  println(
    Json::object({
      "schema_version": Json(1),
      "command": Json("query"),
      "status": Json(status),
      "error": error,
      "directories": Json::array(directories.map(directory => Json(directory))),
      "package": optional_string(package_name),
      "mode": optional_string(mode.map(query_mode_text)),
      "static": Json(static_linking),
      "value": value,
      "matched": matched,
      "paths": paths,
      "flags": flags,
      "diagnostics": diagnostics,
    }).stringify(indent=2),
  )
}

///|
fn explained_paths(
  result : @pc.FlagResult,
  packages : @pc.PackageSet,
  root : String,
  include_private : Bool,
  unavailable : Map[String, Array[@pc.Diagnostic]],
) -> Json {
  let paths = packages.dependency_paths(root, include_private~, unavailable~)
  let output : Map[String, Json] = Map([])
  for flag in result.flags {
    if !output.contains(flag.package_id) {
      let route = paths.path_to(flag.package_id)
      if route.is_empty() {
        return Json(null)
      }
      output[flag.package_id] = Json::array(route.map(id => Json(id)))
    }
  }
  Json::object(output)
}

///|
pub fn query(
  args : Array[String],
  command~ : String = "moon run cmd/query",
) -> Unit {
  let positionals : Array[String] = []
  let extra_paths : Array[String] = []
  let overrides : Map[String, String] = Map([])
  let mut mode : QueryMode? = None
  let mut static_linking = false
  let mut json = false
  let mut explain = false
  let mut dedupe_paths = false
  let mut sysroot = ""
  let system_include_paths : Array[String] = []
  let system_library_paths : Array[String] = []
  let mut invalid = false
  let mut help = false
  let mut i = 1
  while i < args.length() {
    match args[i] {
      "--cflags" =>
        if mode is Some(_) {
          invalid = true
        } else {
          mode = Some(Cflags(None))
        }
      "--libs" =>
        if mode is Some(_) {
          invalid = true
        } else {
          mode = Some(Libs(None))
        }
      "--cflags-only-I" | "--cflags-only-other" as option =>
        if mode is Some(_) {
          invalid = true
        } else {
          let selection = if option == "--cflags-only-I" {
            @pc.IncludePaths
          } else {
            @pc.OtherCflags
          }
          mode = Some(Cflags(Some(selection)))
        }
      "--libs-only-L" | "--libs-only-l" | "--libs-only-other" as option =>
        if mode is Some(_) {
          invalid = true
        } else {
          let selection = match option {
            "--libs-only-L" => @pc.LibraryPaths
            "--libs-only-l" => @pc.Libraries
            _ => @pc.OtherLibs
          }
          mode = Some(Libs(Some(selection)))
        }
      "--modversion" =>
        if mode is Some(_) {
          invalid = true
        } else {
          mode = Some(ModVersion)
        }
      "--exists" =>
        if mode is Some(_) {
          invalid = true
        } else {
          mode = Some(Exists)
        }
      "--static" => static_linking = true
      "--json" => json = true
      "--explain" => explain = true
      "--dedupe-paths" => dedupe_paths = true
      "--path" =>
        if i + 1 >= args.length() || args[i + 1].has_prefix("-") {
          invalid = true
        } else {
          extra_paths.push(args[i + 1])
          i = i + 1
        }
      "--help" | "-h" => help = true
      option =>
        if option.has_prefix("--atleast-version=") {
          let version = option[18:].to_owned()
          if mode is Some(_) || version.is_empty() {
            invalid = true
          } else {
            mode = Some(AtLeastVersion(version))
          }
        } else if option.has_prefix("--exact-version=") {
          let version = option[16:].to_owned()
          if mode is Some(_) || version.is_empty() {
            invalid = true
          } else {
            mode = Some(ExactVersion(version))
          }
        } else if option.has_prefix("--max-version=") {
          let version = option[14:].to_owned()
          if mode is Some(_) || version.is_empty() {
            invalid = true
          } else {
            mode = Some(MaxVersion(version))
          }
        } else if option.has_prefix("--variable=") {
          let name = option[11:].to_owned()
          if mode is Some(_) || !valid_variable_name(name) {
            invalid = true
          } else {
            mode = Some(Variable(name))
          }
        } else if option.has_prefix("--define-variable=") {
          let definition = option[18:].to_owned()
          match definition.find("=") {
            Some(split) => {
              let name = definition[:split].to_owned()
              let value = definition[split + 1:].to_owned()
              if !valid_variable_name(name) || name == "pcfiledir" {
                invalid = true
              } else {
                overrides[name] = value
              }
            }
            None => invalid = true
          }
        } else if option.has_prefix("--sysroot=") {
          let path = option[10:].to_owned()
          if path.is_empty() || !sysroot.is_empty() {
            invalid = true
          } else {
            sysroot = path
          }
        } else if option.has_prefix("--system-include-path=") {
          let path = option[22:].to_owned()
          if path.is_empty() {
            invalid = true
          } else {
            system_include_paths.push(path)
          }
        } else if option.has_prefix("--system-library-path=") {
          let path = option[22:].to_owned()
          if path.is_empty() {
            invalid = true
          } else {
            system_library_paths.push(path)
          }
        } else if option.has_prefix("-") {
          invalid = true
        } else {
          positionals.push(option)
        }
    }
    i = i + 1
  }
  if help {
    query_usage(command)
    return
  }
  let directories = if positionals.is_empty() {
    extra_paths
  } else {
    [positionals[0], ..extra_paths]
  }
  let package_name = positionals.get(1)
  let empty_flags : @pc.FlagResult = { flags: [], diagnostics: [], }
  if invalid || positionals.length() != 2 || mode is None {
    if json {
      query_report(
        directories,
        package_name,
        mode,
        static_linking,
        empty_flags,
        status="usage_error",
        error=command_error(
          "usage", "Expected a directory, package and exactly one query mode with supported options",
        ),
      )
    } else {
      query_usage(command)
    }
    @sys.exit(2)
    return
  }
  let cflags_mode = mode is Some(Cflags(_))
  let libs_mode = mode is Some(Libs(_))
  let flag_mode = cflags_mode || libs_mode
  if static_linking && !flag_mode {
    let message = "--static requires a compiler or linker flag mode"
    if json {
      query_report(
        directories,
        package_name,
        mode,
        static_linking,
        empty_flags,
        status="usage_error",
        error=command_error("usage", message),
      )
    } else {
      println(message)
    }
    @sys.exit(2)
    return
  }
  if !flag_mode &&
    (
      dedupe_paths ||
      explain ||
      !sysroot.is_empty() ||
      !system_include_paths.is_empty() ||
      !system_library_paths.is_empty()
    ) {
    let message = "flag path options and --explain require a compiler or linker flag mode"
    if json {
      query_report(
        directories,
        package_name,
        mode,
        static_linking,
        empty_flags,
        status="usage_error",
        error=command_error("usage", message),
      )
    } else {
      println(message)
    }
    @sys.exit(2)
    return
  }
  let directory = positionals[0]
  let root = positionals[1]
  try {
    let loaded = @loader.load_directories(directories, overrides~)
    let root_diagnostics = loaded.diagnostics_for(root)
    if !root_diagnostics.is_empty() {
      if json {
        let failed : @pc.FlagResult = {
          flags: [],
          diagnostics: root_diagnostics,
        }
        query_report(
          directories,
          package_name,
          mode,
          static_linking,
          failed,
          status="diagnostics",
        )
      } else {
        print_diagnostics(root_diagnostics)
      }
      @sys.exit(1)
      return
    }
    match mode.unwrap() {
      Cflags(selection) | Libs(selection) => {
        let collected = if cflags_mode {
          loaded.packages.collect_cflags(
            root,
            static_linking~,
            unavailable=loaded.diagnostics_by_package,
          )
        } else {
          loaded.packages.collect_libs(
            root,
            static_linking~,
            unavailable=loaded.diagnostics_by_package,
          )
        }
        let rooted = collected.with_sysroot(sysroot)
        let filtered = rooted.filter_system_search_paths(
          system_include_paths, system_library_paths,
        )
        let deduplicated = if dedupe_paths {
          filtered.deduplicate_search_paths()
        } else {
          filtered
        }
        let result = match selection {
          Some(group) => deduplicated.select(group)
          None => deduplicated
        }
        if json {
          let paths = if explain && result.diagnostics.is_empty() {
            explained_paths(
              result,
              loaded.packages,
              root,
              cflags_mode || static_linking,
              loaded.diagnostics_by_package,
            )
          } else {
            Json(null)
          }
          query_report(
            directories,
            package_name,
            mode,
            static_linking,
            result,
            status=if result.diagnostics.is_empty() {
              "ok"
            } else {
              "diagnostics"
            },
            paths~,
          )
        } else {
          print_flags(
            result,
            explain,
            loaded.packages,
            root,
            cflags_mode || static_linking,
            loaded.diagnostics_by_package,
          )
        }
        if !result.diagnostics.is_empty() {
          @sys.exit(1)
        }
      }
      ModVersion
      | Variable(_)
      | Exists
      | AtLeastVersion(_)
      | ExactVersion(_)
      | MaxVersion(_) as metadata_query => {
        let resolution = loaded.packages.resolve(
          root,
          unavailable=loaded.diagnostics_by_package,
        )
        if !resolution.diagnostics.is_empty() {
          if json {
            let failed : @pc.FlagResult = {
              flags: [],
              diagnostics: resolution.diagnostics,
            }
            query_report(
              directories,
              package_name,
              mode,
              static_linking,
              failed,
              status="diagnostics",
            )
          } else {
            print_diagnostics(resolution.diagnostics)
          }
          @sys.exit(1)
          return
        }
        let selected_id = resolution.order[resolution.order.length() - 1]
        let selected = loaded.packages.get(selected_id).unwrap()
        let version = selected.document.field("Version").unwrap().value
        match metadata_query {
          ModVersion =>
            if json {
              query_report(
                directories,
                package_name,
                mode,
                static_linking,
                empty_flags,
                value=Json(version),
              )
            } else {
              println(version)
            }
          Variable(name) =>
            match selected.document.variable(name) {
              Some(entry) =>
                if json {
                  query_report(
                    directories,
                    package_name,
                    mode,
                    static_linking,
                    empty_flags,
                    value=Json(entry.value),
                  )
                } else {
                  println(entry.value)
                }
              None => {
                let message = "Variable not found: \{name}"
                if json {
                  query_report(
                    directories,
                    package_name,
                    mode,
                    static_linking,
                    empty_flags,
                    status="not_found",
                    error=command_error("variable", message),
                  )
                } else {
                  println(message)
                }
                @sys.exit(1)
              }
            }
          Exists | AtLeastVersion(_) | ExactVersion(_) | MaxVersion(_) => {
            let matched = match metadata_query {
              Exists => true
              AtLeastVersion(required) =>
                @pc.compare_versions(version, required) >= 0
              ExactVersion(required) =>
                @pc.compare_versions(version, required) == 0
              MaxVersion(required) =>
                @pc.compare_versions(version, required) <= 0
              _ => abort("unreachable version predicate")
            }
            if json {
              query_report(
                directories,
                package_name,
                mode,
                static_linking,
                empty_flags,
                status=if matched { "ok" } else { "nonmatch" },
                matched=Json(matched),
              )
            }
            if !matched {
              @sys.exit(1)
            }
          }
          _ => abort("unreachable metadata query mode")
        }
      }
    }
  } catch {
    @fs.IOError(message) => {
      if json {
        query_report(
          directories,
          package_name,
          mode,
          static_linking,
          empty_flags,
          status="io_error",
          error=command_error(
            "io",
            "Could not load \{directories.join(", ")}: \{message}",
          ),
        )
      } else {
        println("Could not load \{directory}: \{message}")
      }
      @sys.exit(2)
    }
  }
}
