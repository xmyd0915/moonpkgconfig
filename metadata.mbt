///|
/// Validate the required metadata of a parsed `.pc` document.
///
/// Parsing remains loss-tolerant; callers opt into package-level validation
/// before adding a document to a package set.
pub fn Document::validate_metadata(
  self : Document,
  source? : String = "package.pc",
) -> Array[Diagnostic] {
  let diagnostics : Array[Diagnostic] = []
  validate_required_field(self, "Name", source, diagnostics)
  validate_required_field(self, "Description", source, diagnostics)
  validate_required_field(self, "Version", source, diagnostics)
  match self.field("Version") {
    Some(version) =>
      if !version.value.is_empty() && version.value.iter().any(whitespace) {
        diagnostics.push(
          diag("PC012", "Version must not contain whitespace", version.location),
        )
      }
    None => ()
  }
  diagnostics
}

///|
fn validate_required_field(
  document : Document,
  name : String,
  source : String,
  diagnostics : Array[Diagnostic],
) -> Unit {
  match document.field(name) {
    None =>
      diagnostics.push(
        diag("PC010", "Missing required field: " + name, {
          source,
          line: 1,
          column: 1,
        }),
      )
    Some(entry) =>
      if entry.value.is_empty() {
        diagnostics.push(
          diag("PC011", "Required field is empty: " + name, entry.location),
        )
      }
  }
}
