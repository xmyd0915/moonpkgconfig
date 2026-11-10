///|
fn inspect_usage(command : String) -> Unit {
  println("Usage: \{command} <file.pc> [--json]")
  println("Exit codes: 0 valid, 1 diagnostics found, 2 usage or file error")
}

///|
fn print_summary(document : @pc.Document) -> Unit {
  for
    field_name in [
      "Name", "Description", "Version", "Requires", "Requires.private", "Provides",
      "Conflicts", "Cflags", "Cflags.private", "Libs", "Libs.private",
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
fn inspect_report(
  file : String?,
  document : @pc.Document,
  status : String,
  error~ : Json = Json(null),
) -> Unit {
  let (entries, diagnostics) = match document.as_json() {
    Object({ "entries": entries, "diagnostics": diagnostics, .. }) =>
      (entries, diagnostics)
    _ => abort("Document JSON must contain entries and diagnostics")
  }
  println(
    Json::object({
      "schema_version": Json(1),
      "command": Json("inspect"),
      "status": Json(status),
      "error": error,
      "file": optional_string(file),
      "entries": entries,
      "diagnostics": diagnostics,
    }).stringify(indent=2),
  )
}

///|
pub fn inspect(
  args : Array[String],
  command~ : String = "moon run cmd/inspect",
) -> Unit {
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
    inspect_usage(command)
    return
  }
  let empty_document : @pc.Document = { entries: [], diagnostics: [], }
  if invalid || path is None {
    if json {
      inspect_report(
        path,
        empty_document,
        "usage_error",
        error=command_error("usage", "Expected one file and optional --json"),
      )
    } else {
      inspect_usage(command)
    }
    @sys.exit(2)
    return
  }
  guard path is Some(path) else { abort("A file was required before reading") }
  try {
    let input = @fs.read_file_to_string(path)
    let pcfiledir = @path.Path(path).dirname().to_string()
    let document = checked_document(
      @pc.parse(input, source=path, pcfiledir~),
      path,
    )
    if json {
      inspect_report(
        Some(path),
        document,
        if document.diagnostics.is_empty() {
          "ok"
        } else {
          "diagnostics"
        },
      )
    } else {
      print_summary(document)
    }
    if !document.diagnostics.is_empty() {
      @sys.exit(1)
    }
  } catch {
    @fs.IOError(message) => {
      let message = "Could not read \{path}: \{message}"
      if json {
        inspect_report(
          Some(path),
          empty_document,
          "io_error",
          error=command_error("io", message),
        )
      } else {
        println(message)
      }
      @sys.exit(2)
    }
  }
}
