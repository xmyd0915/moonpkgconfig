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
  let root_requirement : Requirement = { name: root, op: Any, version: "", }
  let root_id = match self.packages.get(root) {
    Some(_) => Some(root)
    None => self.find_provider(root_requirement).map(pkg => pkg.id)
  }
  match root_id {
    Some(id) =>
      resolve_graph(
        self, id, include_private, source, states, order, stack, diagnostics,
      )
    None =>
      diagnostics.push(
        diag("PC015", "Required package not found: " + root, {
          source,
          line: 1,
          column: 1,
        }),
      )
  }
  append_selected_conflicts(self, order, diagnostics)
  { order, diagnostics, }
}

///|
/// Check every package as a possible root and return each distinct diagnostic
/// once. Private dependencies participate by default because a directory check
/// should also catch problems that only affect static linking.
pub fn PackageSet::check_all(
  self : PackageSet,
  include_private? : Bool = true,
) -> Array[Diagnostic] {
  let diagnostics : Array[Diagnostic] = []
  for id in self.package_ids {
    let result = self.resolve(id, include_private~, source=id)
    for problem in result.diagnostics {
      if !diagnostics.any(existing => existing == problem) {
        diagnostics.push(problem)
      }
    }
  }
  diagnostics
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
priv enum ResolveStep {
  Visit(String)
  Problem(Diagnostic)
}

///|
priv struct ResolveFrame {
  id : String
  steps : Array[ResolveStep]
  mut next : Int
}

///|
fn resolve_graph(
  packages : PackageSet,
  id : String,
  include_private : Bool,
  source : String,
  states : Map[String, Int],
  order : Array[String],
  stack : Array[String],
  diagnostics : Array[Diagnostic],
) -> Unit {
  let frames : Array[ResolveFrame] = [
    { id, steps: resolve_steps(packages, id, include_private), next: 0, },
  ]
  states[id] = 1
  stack.push(id)
  while !frames.is_empty() {
    let last = frames.length() - 1
    let frame = frames[last]
    if frame.next == frame.steps.length() {
      frames.pop() |> ignore
      stack.pop() |> ignore
      states[frame.id] = 2
      order.push(frame.id)
      continue
    }
    let step = frame.steps[frame.next]
    frame.next = frame.next + 1
    match step {
      Problem(problem) => diagnostics.push(problem)
      Visit(next) =>
        match states.get(next) {
          Some(2) => ()
          Some(1) =>
            diagnostics.push(
              diag(
                "PC017",
                "Dependency cycle: " + stack.join(" -> ") + " -> " + next,
                { source, line: 1, column: 1, },
              ),
            )
          _ => {
            states[next] = 1
            stack.push(next)
            frames.push({
              id: next,
              steps: resolve_steps(packages, next, include_private),
              next: 0,
            })
          }
        }
    }
  }
}

///|
fn resolve_steps(
  packages : PackageSet,
  id : String,
  include_private : Bool,
) -> Array[ResolveStep] {
  let steps : Array[ResolveStep] = []
  let pkg = packages.packages.get(id).unwrap()
  append_resolve_steps(packages, pkg, "Requires", steps)
  if include_private {
    append_resolve_steps(packages, pkg, "Requires.private", steps)
  }
  steps
}

///|
fn append_resolve_steps(
  packages : PackageSet,
  pkg : Package,
  field_name : String,
  steps : Array[ResolveStep],
) -> Unit {
  guard pkg.document.field(field_name) is Some(field) else { return }
  match parse_requirements(field.value, source=field.location.source) {
    Err(problem) =>
      steps.push(
        Problem(
          diag(problem.code, problem.message, {
            source: field.location.source,
            line: field.location.line,
            column: field.location.column + problem.location.column - 1,
          }),
        ),
      )
    Ok(requirements) =>
      for requirement in requirements {
        match packages.packages.get(requirement.name) {
          None =>
            match packages.find_provider(requirement) {
              None =>
                steps.push(
                  Problem(
                    diag(
                      "PC015",
                      "Required package not found: " + requirement.name,
                      {
                        source: field.location.source,
                        line: field.location.line,
                        column: field.location.column,
                      },
                    ),
                  ),
                )
              Some(provider) => steps.push(Visit(provider.id))
            }
          Some(dependency) => {
            let version = dependency.document.field("Version").unwrap().value
            if !requirement.matches(version) {
              steps.push(
                Problem(
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
                ),
              )
            } else {
              steps.push(Visit(requirement.name))
            }
          }
        }
      }
  }
}
