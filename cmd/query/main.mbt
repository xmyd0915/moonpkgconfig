///|
enum QueryMode {
  Cflags
  Libs
} derive(Eq)

///|
fn print_usage() -> Unit {
  println(
    "Usage: moon run cmd/query <directory> <package> (--cflags | --libs) [--path <directory>]... [--static] [--dedupe-paths] [--json] [--explain]",
  )
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
fn print_flags(result : @pc.FlagResult, explain : Bool) -> Unit {
  println(result.shell_text())
  if explain {
    for flag in result.flags {
      println(
        "  \{flag.value} <- \{flag.package_id}:\{flag.field} [\{flag.location.source}:\{flag.location.line}]",
      )
    }
  }
  print_diagnostics(result.diagnostics)
}

///|
fn main {
  let args = @env.args()
  let positionals : Array[String] = []
  let extra_paths : Array[String] = []
  let mut mode : QueryMode? = None
  let mut static_linking = false
  let mut json = false
  let mut explain = false
  let mut dedupe_paths = false
  let mut invalid = false
  let mut help = false
  let mut i = 1
  while i < args.length() {
    match args[i] {
      "--cflags" =>
        if mode is Some(_) {
          invalid = true
        } else {
          mode = Some(Cflags)
        }
      "--libs" =>
        if mode is Some(_) {
          invalid = true
        } else {
          mode = Some(Libs)
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
        if option.has_prefix("-") {
          invalid = true
        } else {
          positionals.push(option)
        }
    }
    i = i + 1
  }
  if help {
    print_usage()
    return
  }
  if invalid || positionals.length() != 2 || mode is None {
    print_usage()
    @sys.exit(2)
  }
  if static_linking && mode == Some(Cflags) {
    println("--static is only valid with --libs")
    @sys.exit(2)
  }
  let directory = positionals[0]
  let root = positionals[1]
  let directories = [directory, ..extra_paths]
  try {
    let loaded = @loader.load_directories(directories)
    let root_diagnostics = loaded.diagnostics_for(root)
    if !root_diagnostics.is_empty() {
      if json {
        let failed : @pc.FlagResult = {
          flags: [],
          diagnostics: root_diagnostics,
        }
        println(failed.json_text(pretty=true))
      } else {
        print_diagnostics(root_diagnostics)
      }
      @sys.exit(1)
    }
    let collected = match mode.unwrap() {
      Cflags => loaded.packages.collect_cflags(root)
      Libs => loaded.packages.collect_libs(root, static_linking~)
    }
    let result = if dedupe_paths {
      collected.deduplicate_search_paths()
    } else {
      collected
    }
    if json {
      println(result.json_text(pretty=true))
    } else {
      print_flags(result, explain)
    }
    if !result.diagnostics.is_empty() {
      @sys.exit(1)
    }
  } catch {
    @fs.IOError(message) => {
      println("Could not load \{directory}: \{message}")
      @sys.exit(2)
    }
  }
}
