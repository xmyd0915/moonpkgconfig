///|
/// Convert a parsed document to JSON without losing raw values or source
/// locations.
pub fn Document::as_json(self : Document) -> Json {
  let entries : Array[Json] = []
  for entry in self.entries {
    entries.push(
      Json::object({
        "kind": Json(
          match entry.kind {
            Variable => "variable"
            Field => "field"
          },
        ),
        "name": Json(entry.name),
        "raw": Json(entry.raw),
        "value": Json(entry.value),
        "location": location_json(entry.location),
      }),
    )
  }
  let diagnostics = self.diagnostics.map(diagnostic_json)
  Json::object({
    "entries": Json::array(entries),
    "diagnostics": Json::array(diagnostics),
  })
}

///|
/// Convert collected compiler or linker flags to JSON with their origins.
pub fn FlagResult::as_json(self : FlagResult) -> Json {
  let flags : Array[Json] = []
  for flag in self.flags {
    flags.push(
      Json::object({
        "value": Json(flag.value),
        "package": Json(flag.package_id),
        "field": Json(flag.field),
        "location": location_json(flag.location),
      }),
    )
  }
  Json::object({
    "flags": Json::array(flags),
    "diagnostics": Json::array(self.diagnostics.map(diagnostic_json)),
  })
}

///|
pub fn Document::json_text(self : Document, pretty? : Bool = false) -> String {
  self.as_json().stringify(indent=if pretty { 2 } else { 0 })
}

///|
pub fn FlagResult::json_text(
  self : FlagResult,
  pretty? : Bool = false,
) -> String {
  self.as_json().stringify(indent=if pretty { 2 } else { 0 })
}

///|
fn location_json(location : Location) -> Json {
  Json::object({
    "source": Json(location.source),
    "line": Json(location.line),
    "column": Json(location.column),
  })
}

///|
fn diagnostic_json(problem : Diagnostic) -> Json {
  Json::object({
    "code": Json(problem.code),
    "message": Json(problem.message),
    "location": location_json(problem.location),
  })
}
