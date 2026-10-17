///|
// Caches live for one public operation. PackageSet and its documents remain
// caller-owned and may change between operations.
priv struct QueryContext {
  packages : PackageSet
  include_private : Bool
  mut providers : Map[String, Array[(String, Requirement)]]?
  steps : Map[String, Array[ResolveStep]]
  unavailable : Map[String, Array[Diagnostic]]
}

///|
fn QueryContext::new(
  packages : PackageSet,
  include_private : Bool,
  unavailable? : Map[String, Array[Diagnostic]] = Map([]),
) -> QueryContext {
  { packages, include_private, providers: None, steps: Map([]), unavailable, }
}

///|
// Only excluded identifiers carry load failures. A valid exact package wins;
// empty error arrays do not block virtual providers.
fn QueryContext::unavailable_diagnostics(
  self : QueryContext,
  id : String,
) -> Array[Diagnostic]? {
  if self.packages.packages.contains(id) {
    return None
  }
  match self.unavailable.get(id) {
    Some(problems) if !problems.is_empty() => Some(problems)
    _ => None
  }
}

///|
fn QueryContext::root_id(self : QueryContext, root : String) -> String? {
  if self.packages.packages.contains(root) {
    Some(root)
  } else if self.unavailable_diagnostics(root) is Some(_) {
    None
  } else {
    self.find_provider({ name: root, op: Any, version: "", })
  }
}

///|
// Index candidates by virtual name while preserving package insertion order
// and declaration order. Exact package identifiers are handled by callers.
fn QueryContext::find_provider(
  self : QueryContext,
  requirement : Requirement,
) -> String? {
  let providers = match self.providers {
    Some(index) => index
    None => {
      let index : Map[String, Array[(String, Requirement)]] = Map([])
      for id in self.packages.package_ids {
        let pkg = self.packages.packages.get(id).unwrap()
        guard pkg.document.field("Provides") is Some(field) else { continue }
        guard parse_requirements(field.value, source=field.location.source)
          is Ok(provides) else {
          continue
        }
        for provided in provides {
          match index.get(provided.name) {
            Some(candidates) => candidates.push((pkg.id, provided))
            None => index[provided.name] = [(pkg.id, provided)]
          }
        }
      }
      self.providers = Some(index)
      index
    }
  }
  guard providers.get(requirement.name) is Some(candidates) else { return None }
  for (id, provided) in candidates {
    if virtual_requirement_matches(requirement, provided) {
      return Some(id)
    }
  }
  None
}

///|
fn QueryContext::resolve_steps(
  self : QueryContext,
  id : String,
) -> Array[ResolveStep] {
  match self.steps.get(id) {
    Some(steps) => steps
    None => {
      let steps : Array[ResolveStep] = []
      let pkg = self.packages.packages.get(id).unwrap()
      append_resolve_steps(self, pkg, "Requires", steps)
      if self.include_private {
        append_resolve_steps(self, pkg, "Requires.private", steps)
      }
      self.steps[id] = steps
      steps
    }
  }
}
