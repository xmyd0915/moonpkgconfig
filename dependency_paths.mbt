///|
/// A snapshot of shortest dependency routes from one root.
///
/// Only predecessor identifiers are stored. Paths are materialized on demand,
/// avoiding a copy of every prefix while searching a deep graph.
pub struct DependencyPaths {
  root : String
  parents : Map[String, String]
}

///|
/// Return a fresh shortest path, or an empty array for an unreachable package.
pub fn DependencyPaths::path_to(
  self : DependencyPaths,
  target : String,
) -> Array[String] {
  if !self.parents.contains(target) {
    return []
  }
  let reversed : Array[String] = []
  let mut current = target
  while current != self.root {
    reversed.push(current)
    current = self.parents.get(current).unwrap()
  }
  reversed.push(self.root)
  reversed.rev_in_place()
  reversed
}

///|
/// Search once when explaining multiple parameters from the same root.
///
/// Public edges precede private edges; equal-length routes follow declaration
/// order. Later additions to PackageSet do not change this snapshot.
pub fn PackageSet::dependency_paths(
  self : PackageSet,
  root : String,
  include_private? : Bool = false,
) -> DependencyPaths {
  self.build_dependency_paths(root, include_private, None)
}

///|
fn PackageSet::build_dependency_paths(
  self : PackageSet,
  root : String,
  include_private : Bool,
  target : String?,
) -> DependencyPaths {
  let parents : Map[String, String] = Map([])
  let requirement : Requirement = { name: root, op: Any, version: "", }
  let root_id = match self.packages.get(root) {
    Some(_) => Some(root)
    None => self.find_provider(requirement).map(pkg => pkg.id)
  }
  guard root_id is Some(start) else { return { root, parents, } }
  let queue : Array[String] = [start]
  parents[start] = start
  let mut index = 0
  while index < queue.length() {
    let id = queue[index]
    if target == Some(id) {
      break
    }
    let pkg = self.packages.get(id).unwrap()
    append_dependency_parents(self, pkg, "Requires", parents, queue)
    if include_private {
      append_dependency_parents(self, pkg, "Requires.private", parents, queue)
    }
    index = index + 1
  }
  { root: start, parents, }
}

///|
fn append_dependency_parents(
  packages : PackageSet,
  pkg : Package,
  field_name : String,
  parents : Map[String, String],
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
    if !parents.contains(id) {
      parents[id] = pkg.id
      queue.push(id)
    }
  }
}
