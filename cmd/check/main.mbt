///|
fn print_usage() -> Unit {
  println("Usage: moon run cmd/check <directory>")
  println(
    "Exit codes: 0 valid, 1 diagnostics found, 2 usage or directory error",
  )
}

///|
fn print_diagnostic(problem : @pc.Diagnostic) -> Unit {
  println(
    "\{problem.code} \{problem.location.source}:\{problem.location.line}:\{problem.location.column} \{problem.message}",
  )
}

///|
fn main {
  let args = @env.args()
  if args.length() == 2 && (args[1] == "--help" || args[1] == "-h") {
    print_usage()
    return
  }
  if args.length() != 2 || args[1].has_prefix("-") {
    print_usage()
    @sys.exit(2)
  }
  let directory = args[1]
  try {
    let loaded = @loader.load_directory(directory)
    let diagnostics = loaded.diagnostics.copy()
    for problem in loaded.packages.check_all() {
      if !diagnostics.any(existing => existing == problem) {
        diagnostics.push(problem)
      }
    }
    for problem in diagnostics {
      print_diagnostic(problem)
    }
    println(
      "Checked \{loaded.package_ids.length()} packages from \{loaded.file_count} .pc files; \{diagnostics.length()} diagnostics.",
    )
    if !diagnostics.is_empty() {
      @sys.exit(1)
    }
  } catch {
    @fs.IOError(message) => {
      println("Could not check \{directory}: \{message}")
      @sys.exit(2)
    }
  }
}
