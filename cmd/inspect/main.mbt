///|
fn print_usage() -> Unit {
  println("Usage: moon run cmd/inspect <file.pc> [--json]")
  println("Exit codes: 0 valid, 1 diagnostics found, 2 usage or file error")
}

///|
fn print_summary(document : @pc.Document) -> Unit {
  for
    field_name in [
      "Name", "Description", "Version", "Requires", "Requires.private", "Provides",
      "Conflicts", "Cflags", "Libs", "Libs.private",
    ] {
    match document.field(field_name) {
      Some(entry) =>
        println(
          "\{entry.name}: \{entry.value} [\{entry.location.source}:\{entry.location.line}]",
        )
      None => ()
    }
  }
  if document.diagnostics.is_empty() {
    println("Diagnostics: none")
  } else {
    println("Diagnostics:")
    for problem in document.diagnostics {
      println(
        "  \{problem.code} \{problem.location.source}:\{problem.location.line}:\{problem.location.column} \{problem.message}",
      )
    }
  }
}

///|
fn checked_document(document : @pc.Document, source : String) -> @pc.Document {
  let diagnostics : Array[@pc.Diagnostic] = []
  for problem in document.diagnostics {
    diagnostics.push(problem)
  }
  for problem in document.validate_metadata(source~) {
    diagnostics.push(problem)
  }
  { entries: document.entries, diagnostics, }
}

///|
fn main {
  let args = @env.args()
  let mut path : String? = None
  let mut json = false
  let mut invalid = false
  let mut help = false
  for i = 1; i < args.length(); i = i + 1 {
    if args[i] == "--json" {
      json = true
    } else if args[i] == "--help" || args[i] == "-h" {
      help = true
    } else if args[i].has_prefix("-") {
      invalid = true
    } else if path is None {
      path = Some(args[i])
    } else {
      invalid = true
    }
  }
  if help {
    print_usage()
    return
  }
  if invalid {
    print_usage()
    @sys.exit(2)
  }
  guard path is Some(path) else {
    print_usage()
    @sys.exit(2)
  }
  try {
    let input = @fs.read_file_to_string(path)
    let pcfiledir = @path.Path(path).dirname().to_string()
    let document = checked_document(
      @pc.parse(input, source=path, pcfiledir~),
      path,
    )
    if json {
      println(document.json_text(pretty=true))
    } else {
      print_summary(document)
    }
    if !document.diagnostics.is_empty() {
      @sys.exit(1)
    }
  } catch {
    @fs.IOError(message) => {
      println("Could not read \{path}: \{message}")
      @sys.exit(2)
    }
  }
}
