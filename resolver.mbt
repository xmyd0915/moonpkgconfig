///|
/// Result of resolving one root package. Dependencies precede dependants in
/// `order`; diagnostics explain every branch that could not be resolved.
pub(all) struct Resolution {
  order : Array[String]
  diagnostics : Array[Diagnostic]
} derive(Eq, @debug.Debug)

///|
/// Resolve the dependency graph rooted at `root`.
///
/// `Requires.private` participates only when `include_private` is true.
pub fn PackageSet::resolve(
  self : PackageSet,
  root : String,
  include_private? : Bool = false,
  source? : String = "query",
) -> Resolution {
  let states : Map[String, Int] = Map([])
  let order : Array[String] = []
  let stack : Array[String] = []
  let diagnostics : Array[Diagnostic] = []
  resolve_visit(
    self, root, include_private, source, states, order, stack, diagnostics,
  )
  append_selected_conflicts(self, order, diagnostics)
  { order, diagnostics, }
}

///|
fn append_selected_conflicts(
  packages : PackageSet,
  order : Array[String],
  diagnostics : Array[Diagnostic],
) -> Unit {
  let selected : Map[String, Bool] = Map([])
  for id in order {
    selected[id] = true
  }
  for id in order {
    guard packages.packages.get(id) is Some(pkg) else { continue }
    guard pkg.document.field("Conflicts") is Some(field) else { continue }
    match parse_requirements(field.value, source=field.location.source) {
      Err(problem) =>
        diagnostics.push(
          diag(problem.code, problem.message, {
            source: field.location.source,
            line: field.location.line,
            column: field.location.column + problem.location.column - 1,
          }),
        )
      Ok(conflicts) =>
        for conflict in conflicts {
          if conflict.name != id && selected.contains(conflict.name) {
            guard packages.packages.get(conflict.name) is Some(other) else {
              continue
            }
            let version = other.document.field("Version").unwrap().value
            if conflict.matches(version) {
              diagnostics.push(
                diag(
                  "PC018",
                  "Package " +
                  id +
                  " conflicts with " +
                  conflict.name +
                  " " +
                  version,
                  field.location,
                ),
              )
            }
          }
        }
    }
  }
}

///|
fn resolve_visit(
  packages : PackageSet,
  id : String,
  include_private : Bool,
  source : String,
  states : Map[String, Int],
  order : Array[String],
  stack : Array[String],
  diagnostics : Array[Diagnostic],
) -> Unit {
  match states.get(id) {
    Some(2) => return
    Some(1) => {
      diagnostics.push(
        diag("PC017", "Dependency cycle: " + stack.join(" -> ") + " -> " + id, {
          source,
          line: 1,
          column: 1,
        }),
      )
      return
    }
    _ => ()
  }
  guard packages.packages.get(id) is Some(pkg) else {
    diagnostics.push(
      diag("PC015", "Required package not found: " + id, {
        source,
        line: 1,
        column: 1,
      }),
    )
    return
  }
  states[id] = 1
  stack.push(id)
  visit_requirement_field(
    packages, pkg, "Requires", include_private, source, states, order, stack, diagnostics,
  )
  if include_private {
    visit_requirement_field(
      packages, pkg, "Requires.private", include_private, source, states, order,
      stack, diagnostics,
    )
  }
  stack.pop() |> ignore
  states[id] = 2
  order.push(id)
}

///|
fn visit_requirement_field(
  packages : PackageSet,
  pkg : Package,
  field_name : String,
  include_private : Bool,
  source : String,
  states : Map[String, Int],
  order : Array[String],
  stack : Array[String],
  diagnostics : Array[Diagnostic],
) -> Unit {
  guard pkg.document.field(field_name) is Some(field) else { return }
  match parse_requirements(field.value, source=field.location.source) {
    Err(problem) =>
      diagnostics.push(
        diag(problem.code, problem.message, {
          source: field.location.source,
          line: field.location.line,
          column: field.location.column + problem.location.column - 1,
        }),
      )
    Ok(requirements) =>
      for requirement in requirements {
        match packages.packages.get(requirement.name) {
          None =>
            diagnostics.push(
              diag("PC015", "Required package not found: " + requirement.name, {
                source: field.location.source,
                line: field.location.line,
                column: field.location.column,
              }),
            )
          Some(dependency) => {
            let version = dependency.document.field("Version").unwrap().value
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
                  field.location,
                ),
              )
            } else {
              resolve_visit(
                packages,
                requirement.name,
                include_private,
                source,
                states,
                order,
                stack,
                diagnostics,
              )
            }
          }
        }
      }
  }
}
