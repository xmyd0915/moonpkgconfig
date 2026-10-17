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
/// `unavailable` blocks fallback through excluded exact ids, as in `resolve`.
pub fn PackageSet::dependency_paths(
  self : PackageSet,
  root : String,
  include_private? : Bool = false,
  unavailable? : Map[String, Array[Diagnostic]] = Map([]),
) -> DependencyPaths {
  self.build_dependency_paths(root, include_private, None, unavailable)
}

///|
fn PackageSet::build_dependency_paths(
  self : PackageSet,
  root : String,
  include_private : Bool,
  target : String?,
  unavailable : Map[String, Array[Diagnostic]],
) -> DependencyPaths {
  let parents : Map[String, String] = Map([])
  let context = QueryContext::new(self, include_private, unavailable~)
  let root_id = context.root_id(root)
  guard root_id is Some(start) else { return { root, parents, } }
  let queue : Array[String] = [start]
  parents[start] = start
  let mut index = 0
  while index < queue.length() {
    let id = queue[index]
    if target == Some(id) {
      break
    }
    for step in context.resolve_steps(id) {
      if step is Visit(next) && !parents.contains(next) {
        parents[next] = id
        queue.push(next)
      }
    }
    index = index + 1
  }
  { root: start, parents, }
}
