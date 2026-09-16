///|
fn print_usage() -> Unit {
  println("Usage: moon run cmd/inspect <file.pc> [--json]")
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
fn main {
  let args = @env.args()
  let mut path : String? = None
  let mut json = false
  let mut invalid = false
  for i = 1; i < args.length(); i = i + 1 {
    if args[i] == "--json" {
      json = true
    } else if path is None {
      path = Some(args[i])
    } else {
      invalid = true
    }
  }
  if invalid {
    print_usage()
    return
  }
  guard path is Some(path) else {
    print_usage()
    return
  }
  try {
    let input = @fs.read_file_to_string(path)
    let pcfiledir = @path.Path(path).dirname().to_string()
    let document = @pc.parse(input, source=path, pcfiledir~)
    if json {
      println(document.json_text(pretty=true))
    } else {
      print_summary(document)
    }
  } catch {
    @fs.IOError(message) => println("Could not read \{path}: \{message}")
  }
}
