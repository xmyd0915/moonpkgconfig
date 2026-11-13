///|
// The map compares complete diagnostics, including every location field.
// Hash collisions use structural equality rather than a concatenated text key.
priv struct DiagnosticCollector {
  values : Array[Diagnostic]
  seen : Map[Diagnostic, Bool]
}

///|
fn DiagnosticCollector::new() -> DiagnosticCollector {
  { values: [], seen: Map([]), }
}

///|
fn DiagnosticCollector::push(
  self : DiagnosticCollector,
  problem : Diagnostic,
) -> Unit {
  self.values.push(problem)
  self.seen[problem] = true
}

///|
fn append_unavailable(
  problems : Array[Diagnostic],
  diagnostics : DiagnosticCollector,
) -> Unit {
  for problem in problems {
    if !diagnostics.seen.contains(problem) {
      diagnostics.push(problem)
    }
  }
}
