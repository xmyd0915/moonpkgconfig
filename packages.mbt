///|
/// A validated package stored under the identifier used in dependency lists.
pub(all) struct Package {
  id : String
  document : Document
} derive(Eq, @debug.Debug)

///|
/// An in-memory package collection. File discovery belongs to adapters and the
/// CLI; the core resolver accepts parsed documents so it works on every target.
pub(all) struct PackageSet {
  packages : Map[String, Package]
}

///|
pub fn PackageSet::new() -> PackageSet {
  { packages: Map([]), }
}

///|
/// Add one package after checking its identifier and required metadata.
/// Nothing is inserted when diagnostics are returned.
pub fn PackageSet::add(
  self : PackageSet,
  id : String,
  document : Document,
  source? : String = "package.pc",
) -> Array[Diagnostic] {
  if id.is_empty() || id.iter().any(whitespace) {
    return [
      diag(
        "PC013",
        "Package identifier must not be empty or contain whitespace",
        { source, line: 1, column: 1, },
      ),
    ]
  }
  if self.packages.get(id) is Some(_) {
    return [
      diag("PC014", "Duplicate package identifier: " + id, {
        source,
        line: 1,
        column: 1,
      }),
    ]
  }
  let diagnostics = document.validate_metadata(source~)
  if !diagnostics.is_empty() {
    return diagnostics
  }
  self.packages[id] = { id, document, }
  []
}

///|
pub fn PackageSet::get(self : PackageSet, id : String) -> Package? {
  self.packages.get(id)
}

///|
/// Check a direct dependency list against the packages currently in the set.
pub fn PackageSet::check_requirements(
  self : PackageSet,
  requirements : Array[Requirement],
  source? : String = "Requires",
) -> Array[Diagnostic] {
  let diagnostics : Array[Diagnostic] = []
  for requirement in requirements {
    match self.packages.get(requirement.name) {
      None =>
        diagnostics.push(
          diag("PC015", "Required package not found: " + requirement.name, {
            source,
            line: 1,
            column: 1,
          }),
        )
      Some(pkg) => {
        let version = pkg.document.field("Version").unwrap().value
        if !requirement.matches(version) {
          diagnostics.push(
            diag(
              "PC016",
              "Package " +
              requirement.name +
              " has version " +
              version +
              ", which does not satisfy " +
              requirement_text(requirement),
              { source, line: 1, column: 1, },
            ),
          )
        }
      }
    }
  }
  diagnostics
}

///|
fn requirement_text(requirement : Requirement) -> String {
  match requirement.op {
    Any => "(any)"
    Equal => "= " + requirement.version
    NotEqual => "!= " + requirement.version
    Less => "< " + requirement.version
    LessEqual => "<= " + requirement.version
    Greater => "> " + requirement.version
    GreaterEqual => ">= " + requirement.version
  }
}
