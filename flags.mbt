///|
/// One compiler or linker argument together with its origin.
#derive(Eq, @debug.Debug)
pub(all) struct ResolvedFlag {
  value : String
  package_id : String
  field : String
  location : Location
}

///|
#derive(Eq, @debug.Debug)
pub(all) struct FlagResult {
  flags : Array[ResolvedFlag]
  diagnostics : Array[Diagnostic]
}

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
/// paths, paths already within the sysroot and unrelated arguments are unchanged.
/// Every rewritten flag keeps its original package, field and source location.
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
  if is_absolute_search_path(path) &&
    path != sysroot &&
    !path.has_prefix(sysroot + "/") {
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
/// Collect compiler flags in dependency order, with each dependant before its
/// dependencies and independent branches in declaration order. Static queries also
/// include each package's `Cflags.private` field.
/// `unavailable` retains original diagnostics for excluded dependencies, as
/// in `resolve`. Private dependency failures affect compiler queries too.
pub fn PackageSet::collect_cflags(
  self : PackageSet,
  root : String,
  static_linking~ : Bool = false,
  unavailable~ : Map[String, Array[Diagnostic]] = Map([]),
) -> FlagResult {
  // Private dependencies still contribute headers and compile definitions.
  // Their linker flags are restricted to static linking in collect_libs.
  let context = QueryContext::new(self, true, unavailable~)
  let resolution = context.resolve(root, "query")
  let flags : Array[ResolvedFlag] = []
  let diagnostics = resolution.diagnostics.copy()
  let order = context.link_order(root)
  for id in order {
    append_flag_field(self, id, "Cflags", flags, diagnostics)
  }
  if static_linking {
    // pkgconf appends private compiler fields after all public fields.
    for id in order {
      append_flag_field(self, id, "Cflags.private", flags, diagnostics)
    }
  }
  { flags, diagnostics, }
}

///|
/// Collect linker flags in dependant-first order. Static queries also include
/// private dependency edges and each package's `Libs.private` field.
/// Valid private dependencies can constrain the order of public libraries in
/// dynamic output, without adding private libraries or private diagnostics.
/// `unavailable` retains original diagnostics for excluded dependencies, as
/// in `resolve`, following the selected public/private edge mode.
pub fn PackageSet::collect_libs(
  self : PackageSet,
  root : String,
  static_linking~ : Bool = false,
  unavailable~ : Map[String, Array[Diagnostic]] = Map([]),
) -> FlagResult {
  let context = QueryContext::new(self, static_linking, unavailable~)
  let resolution = context.resolve(root, "query")
  let flags : Array[ResolvedFlag] = []
  let diagnostics = resolution.diagnostics.copy()
  let order = if static_linking || !diagnostics.is_empty() {
    context.link_order(root)
  } else {
    let complete = QueryContext::new(self, true, unavailable~)
    if complete.resolve(root, "query").diagnostics.is_empty() {
      // pkgconf orders the complete graph before filtering private-only nodes.
      // A hidden chain can therefore delay a library also reached publicly.
      let public : Map[String, Bool] = Map([])
      for id in resolution.order {
        public[id] = true
      }
      complete.link_order(root).filter(id => public.contains(id))
    } else {
      // Private failures are outside the core dynamic query's diagnostic scope.
      // In particular, a private cycle must not reorder a valid public DAG.
      context.link_order(root)
    }
  }
  for id in order {
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
/// `unavailable` blocks fallback through excluded exact ids, as in `resolve`.
pub fn PackageSet::dependency_path(
  self : PackageSet,
  root : String,
  target : String,
  include_private~ : Bool = false,
  unavailable~ : Map[String, Array[Diagnostic]] = Map([]),
) -> Array[String] {
  self
  .build_dependency_paths(root, include_private, Some(target), unavailable)
  .path_to(target)
}

///|
// Reverse postorder with reversed child visits puts every dependant before its
// dependencies, while keeping independent branches in declaration order. In a
// triangle, a direct dependency must wait for the sibling that also uses it.
// The explicit stack handles deep graphs without recursive calls; resolution
// has already reported cycles or missing dependencies.
fn QueryContext::link_order(
  self : QueryContext,
  root : String,
) -> Array[String] {
  let finished : Array[String] = []
  let seen : Map[String, Bool] = Map([])
  let pending : Array[(String, Bool)] = []
  if self.root_id(root) is Some(id) {
    pending.push((id, false))
  }
  while !pending.is_empty() {
    let (id, complete) = pending.pop().unwrap()
    if complete {
      finished.push(id)
    } else if !seen.contains(id) {
      seen[id] = true
      pending.push((id, true))
      // Pushing in declaration order visits the last child first.
      for step in self.resolve_steps(id) {
        if step is Visit(next) {
          pending.push((next, false))
        }
      }
    }
  }
  let order : Array[String] = []
  for i = finished.length() - 1; i >= 0; i = i - 1 {
    order.push(finished[i])
  }
  order
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
