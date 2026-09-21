///|
/// One compiler or linker argument together with its origin.
pub(all) struct ResolvedFlag {
  value : String
  package_id : String
  field : String
  location : Location
} derive(Eq, @debug.Debug)

///|
pub(all) struct FlagResult {
  flags : Array[ResolvedFlag]
  diagnostics : Array[Diagnostic]
} derive(Eq, @debug.Debug)

///|
/// Render collected arguments as one POSIX shell command fragment.
///
/// The underlying `flags` array remains the portable, lossless interface.
/// This text form is intended for copying into sh-compatible shells.
pub fn FlagResult::shell_text(self : FlagResult) -> String {
  self.flags.map(flag => shell_quote(flag.value)).join(" ")
}

///|
fn shell_quote(value : String) -> String {
  if !value.is_empty() && value.iter().all(shell_safe_char) {
    return value
  }
  let output = StringBuilder()
  output.write_char('\'')
  for char in value {
    if char == '\'' {
      output.write_string("'\\''")
    } else {
      output.write_char(char)
    }
  }
  output.write_char('\'')
  output.to_string()
}

///|
fn shell_safe_char(char : Char) -> Bool {
  (char >= 'a' && char <= 'z') ||
  (char >= 'A' && char <= 'Z') ||
  (char >= '0' && char <= '9') ||
  char == '_' ||
  char == '@' ||
  char == '%' ||
  char == '+' ||
  char == '=' ||
  char == ':' ||
  char == ',' ||
  char == '.' ||
  char == '/' ||
  char == '-'
}

///|
/// Return a copy with repeated compiler and linker search paths removed.
///
/// Both attached (`-I/path`, `-L/path`) and split (`-I /path`, `-L /path`)
/// forms are recognized. Other flags, including repeated libraries, are kept
/// because their order and repetition can affect linking.
pub fn FlagResult::deduplicate_search_paths(self : FlagResult) -> FlagResult {
  let flags : Array[ResolvedFlag] = []
  let seen : Map[String, Bool] = Map([])
  let mut i = 0
  while i < self.flags.length() {
    let flag = self.flags[i]
    if (flag.value == "-I" || flag.value == "-L") && i + 1 < self.flags.length() {
      let next = self.flags[i + 1]
      let key = flag.value + "\n" + next.value
      if !seen.contains(key) {
        seen[key] = true
        flags.push(flag)
        flags.push(next)
      }
      i = i + 2
    } else {
      let is_search_path = (
          flag.value.has_prefix("-I") || flag.value.has_prefix("-L")
        ) &&
        flag.value.length() > 2
      if !is_search_path || !seen.contains(flag.value) {
        if is_search_path {
          seen[flag.value] = true
        }
        flags.push(flag)
      }
      i = i + 1
    }
  }
  { flags, diagnostics: self.diagnostics.copy(), }
}

///|
/// Collect public compiler flags in dependant-first order.
pub fn PackageSet::collect_cflags(
  self : PackageSet,
  root : String,
) -> FlagResult {
  let resolution = self.resolve(root)
  let flags : Array[ResolvedFlag] = []
  let diagnostics = resolution.diagnostics.copy()
  for id in self.flag_order(root, false) {
    append_flag_field(self, id, "Cflags", flags, diagnostics)
  }
  { flags, diagnostics, }
}

///|
/// Collect linker flags in dependant-first order. Static queries also include
/// private dependency edges and each package's `Libs.private` field.
pub fn PackageSet::collect_libs(
  self : PackageSet,
  root : String,
  static_linking? : Bool = false,
) -> FlagResult {
  let resolution = self.resolve(root, include_private=static_linking)
  let flags : Array[ResolvedFlag] = []
  let diagnostics = resolution.diagnostics.copy()
  for id in self.flag_order(root, static_linking) {
    append_flag_field(self, id, "Libs", flags, diagnostics)
    if static_linking {
      append_flag_field(self, id, "Libs.private", flags, diagnostics)
    }
  }
  { flags, diagnostics, }
}

///|
// pkgconf emits the requested package first, then walks dependencies in their
// declaration order. A separate traversal is used because `Resolution.order`
// is intentionally dependency-first for build planning.
fn PackageSet::flag_order(
  self : PackageSet,
  root : String,
  include_private : Bool,
) -> Array[String] {
  let order : Array[String] = []
  let seen : Map[String, Bool] = Map([])
  let root_requirement : Requirement = { name: root, op: Any, version: "", }
  let root_id = match self.packages.get(root) {
    Some(_) => Some(root)
    None => self.find_provider(root_requirement).map(pkg => pkg.id)
  }
  if root_id is Some(id) {
    seen[id] = true
    order.push(id)
    let mut index = 0
    while index < order.length() {
      let pkg = self.packages.get(order[index]).unwrap()
      append_flag_requirements(self, pkg, "Requires", seen, order)
      if include_private {
        append_flag_requirements(self, pkg, "Requires.private", seen, order)
      }
      index = index + 1
    }
  }
  order
}

///|
fn append_flag_requirements(
  packages : PackageSet,
  pkg : Package,
  field_name : String,
  seen : Map[String, Bool],
  order : Array[String],
) -> Unit {
  guard pkg.document.field(field_name) is Some(field) else { return }
  guard parse_requirements(field.value, source=field.location.source)
    is Ok(requirements) else {
    return
  }
  for requirement in requirements {
    let dependency_id = match packages.packages.get(requirement.name) {
      Some(dependency) => {
        let version = dependency.document.field("Version").unwrap().value
        if requirement.matches(version) {
          Some(requirement.name)
        } else {
          None
        }
      }
      None => packages.find_provider(requirement).map(provider => provider.id)
    }
    if dependency_id is Some(id) {
      if !seen.contains(id) {
        seen[id] = true
        order.push(id)
      }
    }
  }
}

///|
fn append_flag_field(
  packages : PackageSet,
  id : String,
  field_name : String,
  output : Array[ResolvedFlag],
  diagnostics : Array[Diagnostic],
) -> Unit {
  guard packages.packages.get(id) is Some(pkg) else { return }
  guard pkg.document.field(field_name) is Some(entry) else { return }
  match split_flags(entry.value, source=entry.location.source) {
    Ok(values) =>
      for value in values {
        output.push({
          value,
          package_id: id,
          field: field_name,
          location: entry.location,
        })
      }
    Err(problem) =>
      diagnostics.push(
        diag(problem.code, problem.message, {
          source: entry.location.source,
          line: entry.location.line,
          column: entry.location.column + problem.location.column - 1,
        }),
      )
  }
}
