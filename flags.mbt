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
    let split_search_path = (flag.value == "-I" || flag.value == "-L") &&
      i + 1 < self.flags.length() &&
      same_flag_origin(flag, self.flags[i + 1])
    if split_search_path {
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
      let key = if is_search_path {
        flag.value[0:2].to_owned() + "\n" + flag.value[2:].to_owned()
      } else {
        flag.value
      }
      if !is_search_path || !seen.contains(key) {
        if is_search_path {
          seen[key] = true
        }
        flags.push(flag)
      }
      i = i + 1
    }
  }
  { flags, diagnostics: self.diagnostics.copy(), }
}

///|
/// Prefix absolute compiler and linker search paths with a sysroot.
///
/// Attached and split `-I`, `-L` and `-isystem` forms are supported. Relative
/// paths and unrelated arguments are unchanged, and every rewritten flag keeps
/// its original package, field and source location.
pub fn FlagResult::with_sysroot(
  self : FlagResult,
  sysroot : String,
) -> FlagResult {
  if sysroot.is_empty() || sysroot == "/" {
    return { flags: self.flags.copy(), diagnostics: self.diagnostics.copy(), }
  }
  let root_chars = sysroot.to_array()
  let root = if root_chars[root_chars.length() - 1] == '/' {
    sysroot[:sysroot.length() - 1].to_owned()
  } else {
    sysroot
  }
  let flags : Array[ResolvedFlag] = []
  let mut i = 0
  while i < self.flags.length() {
    let flag = self.flags[i]
    let split = (
        flag.value == "-I" || flag.value == "-L" || flag.value == "-isystem"
      ) &&
      i + 1 < self.flags.length() &&
      same_flag_origin(flag, self.flags[i + 1])
    if split {
      let operand = self.flags[i + 1]
      flags.push(flag)
      flags.push(flag_with_value(operand, sysroot_path(root, operand.value)))
      i = i + 2
    } else {
      let prefix_length = if flag.value.has_prefix("-isystem") &&
        flag.value.length() > 8 {
        8
      } else if (flag.value.has_prefix("-I") || flag.value.has_prefix("-L")) &&
        flag.value.length() > 2 {
        2
      } else {
        0
      }
      if prefix_length > 0 {
        let path = flag.value[prefix_length:].to_owned()
        flags.push(
          flag_with_value(
            flag,
            flag.value[:prefix_length].to_owned() + sysroot_path(root, path),
          ),
        )
      } else {
        flags.push(flag)
      }
      i = i + 1
    }
  }
  { flags, diagnostics: self.diagnostics.copy(), }
}

///|
/// Remove exact system `-I` and `-L` search paths.
///
/// The caller supplies the system paths explicitly, keeping library behavior
/// deterministic across hosts. `-isystem` and path prefixes are intentionally
/// retained, matching pkgconf's system path filtering behavior.
pub fn FlagResult::filter_system_search_paths(
  self : FlagResult,
  include_paths : Array[String],
  library_paths : Array[String],
) -> FlagResult {
  let includes : Map[String, Bool] = Map([])
  let libraries : Map[String, Bool] = Map([])
  for path in include_paths {
    includes[path] = true
  }
  for path in library_paths {
    libraries[path] = true
  }
  let flags : Array[ResolvedFlag] = []
  let mut i = 0
  while i < self.flags.length() {
    let flag = self.flags[i]
    let split = (flag.value == "-I" || flag.value == "-L") &&
      i + 1 < self.flags.length() &&
      same_flag_origin(flag, self.flags[i + 1])
    if split {
      let operand = self.flags[i + 1]
      let paths = if flag.value == "-I" { includes } else { libraries }
      if !paths.contains(operand.value) {
        flags.push(flag)
        flags.push(operand)
      }
      i = i + 2
    } else {
      let removable = if flag.value.has_prefix("-I") && flag.value.length() > 2 {
        includes.contains(flag.value[2:].to_owned())
      } else if flag.value.has_prefix("-L") && flag.value.length() > 2 {
        libraries.contains(flag.value[2:].to_owned())
      } else {
        false
      }
      if !removable {
        flags.push(flag)
      }
      i = i + 1
    }
  }
  { flags, diagnostics: self.diagnostics.copy(), }
}

///|
fn flag_with_value(flag : ResolvedFlag, value : String) -> ResolvedFlag {
  {
    value,
    package_id: flag.package_id,
    field: flag.field,
    location: flag.location,
  }
}

///|
fn sysroot_path(sysroot : String, path : String) -> String {
  if is_absolute_search_path(path) {
    sysroot + path
  } else {
    path
  }
}

///|
fn is_absolute_search_path(path : String) -> Bool {
  path.has_prefix("/")
}

///|
fn same_flag_origin(left : ResolvedFlag, right : ResolvedFlag) -> Bool {
  left.package_id == right.package_id &&
  left.field == right.field &&
  left.location == right.location
}

///|
/// Collect public compiler flags in dependant-first order.
pub fn PackageSet::collect_cflags(
  self : PackageSet,
  root : String,
) -> FlagResult {
  // Private dependencies still contribute headers and compile definitions.
  // Their linker flags are restricted to static linking in collect_libs.
  let resolution = self.resolve(root, include_private=true)
  let flags : Array[ResolvedFlag] = []
  let diagnostics = resolution.diagnostics.copy()
  for id in self.flag_order(root, true) {
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
/// Return the shortest dependency path from `root` to `target`.
///
/// Public edges are always considered; private edges participate only when
/// `include_private` is true. An empty array means the target is not reachable.
pub fn PackageSet::dependency_path(
  self : PackageSet,
  root : String,
  target : String,
  include_private? : Bool = false,
) -> Array[String] {
  let root_requirement : Requirement = { name: root, op: Any, version: "", }
  let root_id = match self.packages.get(root) {
    Some(_) => Some(root)
    None => self.find_provider(root_requirement).map(pkg => pkg.id)
  }
  guard root_id is Some(start) else { return [] }
  let paths : Map[String, Array[String]] = Map([])
  let queue : Array[String] = [start]
  paths[start] = [start]
  let mut index = 0
  while index < queue.length() {
    let id = queue[index]
    if id == target {
      return paths.get(id).unwrap().copy()
    }
    let pkg = self.packages.get(id).unwrap()
    append_dependency_paths(self, pkg, "Requires", paths, queue)
    if include_private {
      append_dependency_paths(self, pkg, "Requires.private", paths, queue)
    }
    index = index + 1
  }
  []
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
    let dependency_id = matching_dependency_id(packages, requirement)
    if dependency_id is Some(id) {
      if !seen.contains(id) {
        seen[id] = true
        order.push(id)
      }
    }
  }
}

///|
fn append_dependency_paths(
  packages : PackageSet,
  pkg : Package,
  field_name : String,
  paths : Map[String, Array[String]],
  queue : Array[String],
) -> Unit {
  guard pkg.document.field(field_name) is Some(field) else { return }
  guard parse_requirements(field.value, source=field.location.source)
    is Ok(requirements) else {
    return
  }
  for requirement in requirements {
    guard matching_dependency_id(packages, requirement) is Some(id) else {
      continue
    }
    if !paths.contains(id) {
      let path = paths.get(pkg.id).unwrap().copy()
      path.push(id)
      paths[id] = path
      queue.push(id)
    }
  }
}

///|
fn matching_dependency_id(
  packages : PackageSet,
  requirement : Requirement,
) -> String? {
  match packages.packages.get(requirement.name) {
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
          source: entry.value_location.source,
          line: entry.value_location.line,
          column: entry.value_location.column + problem.location.column - 1,
        }),
      )
  }
}
