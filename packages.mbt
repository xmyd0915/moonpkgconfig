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
  package_ids : Array[String]
}

///|
pub fn PackageSet::new() -> PackageSet {
  { packages: Map([]), package_ids: [], }
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
  self.package_ids.push(id)
  []
}

///|
pub fn PackageSet::get(self : PackageSet, id : String) -> Package? {
  self.packages.get(id)
}

///|
/// Find the first package, in insertion order, whose `Provides` field can
/// satisfy a virtual dependency. Exact package identifiers are handled by the
/// caller and always take precedence. Versioned rules follow pkgconf 3.0.7's
/// constraint-pair semantics, including its deliberately asymmetric ranges.
fn PackageSet::find_provider(
  self : PackageSet,
  requirement : Requirement,
) -> Package? {
  for id in self.package_ids {
    let pkg = self.packages.get(id).unwrap()
    guard pkg.document.field("Provides") is Some(field) else { continue }
    guard parse_requirements(field.value, source=field.location.source)
      is Ok(provides) else {
      continue
    }
    for provided in provides {
      if provided.name == requirement.name &&
        virtual_requirement_matches(requirement, provided) {
        return Some(pkg)
      }
    }
  }
  None
}

///|
/// Compare a requested virtual dependency with one `Provides` declaration.
///
/// This is not ordinary interval intersection. It mirrors the comparator-pair
/// table used by pkgconf 3.0.7 so range boundaries behave the same way.
fn virtual_requirement_matches(
  requirement : Requirement,
  provided : Requirement,
) -> Bool {
  if requirement.op == Any {
    return provided.op != Any
  }
  if provided.op == Any {
    return false
  }
  let order = compare_versions(requirement.version, provided.version)
  match requirement.op {
    Any => abort("handled above")
    Less =>
      match provided.op {
        Any => false
        Less => order < 0
        Greater => order > 0
        LessEqual => order <= 0
        GreaterEqual => order > 0
        Equal => order > 0
        NotEqual => order <= 0
      }
    Greater =>
      match provided.op {
        Any => false
        Less => order < 0
        Greater => order > 0
        LessEqual => order < 0
        GreaterEqual => order >= 0
        Equal => order < 0
        NotEqual => order >= 0
      }
    LessEqual =>
      match provided.op {
        Any => false
        Less => order < 0
        Greater => order > 0
        LessEqual => order <= 0
        GreaterEqual => order >= 0
        Equal => order >= 0
        NotEqual => order < 0
      }
    GreaterEqual =>
      match provided.op {
        Any => false
        Less => order < 0
        Greater => order > 0
        LessEqual => order <= 0
        GreaterEqual => order >= 0
        Equal => order <= 0
        NotEqual => order > 0
      }
    Equal =>
      match provided.op {
        Any => false
        Less => order < 0
        Greater => order > 0
        LessEqual => order <= 0
        GreaterEqual => order >= 0
        Equal => order == 0
        NotEqual => order != 0
      }
    NotEqual =>
      match provided.op {
        Any => false
        Less => order >= 0
        Greater => order <= 0
        LessEqual => order > 0
        GreaterEqual => order < 0
        Equal => order != 0
        NotEqual => order == 0
      }
  }
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
        if self.find_provider(requirement) is None {
          diagnostics.push(
            diag("PC015", "Required package not found: " + requirement.name, {
              source,
              line: 1,
              column: 1,
            }),
          )
        }
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
