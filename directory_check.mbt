///|
priv struct CleanFrame {
  id : String
  steps : Array[ResolveStep]
  mut next : Int
  mut clean : Bool
}

///|
// 1 = active, 2 = proven clean, 3 = requires the full diagnostic traversal.
// Any conflict field is conservative: its meaning depends on a root's selected
// closure, so it must not be checked against the whole directory at once.
fn QueryContext::clean_subgraphs(self : QueryContext) -> Map[String, Int] {
  let states : Map[String, Int] = Map([])
  for root in self.packages.package_ids {
    if states.contains(root) {
      continue
    }
    let frames : Array[CleanFrame] = [self.clean_frame(root)]
    states[root] = 1
    while !frames.is_empty() {
      let frame = frames[frames.length() - 1]
      if frame.next == frame.steps.length() {
        states[frame.id] = if frame.clean { 2 } else { 3 }
        frames.pop() |> ignore
        if !frame.clean && !frames.is_empty() {
          frames[frames.length() - 1].clean = false
        }
        continue
      }
      let step = frame.steps[frame.next]
      frame.next = frame.next + 1
      match step {
        Problem(_) => frame.clean = false
        Visit(id) =>
          match states.get(id) {
            Some(2) => ()
            Some(_) => frame.clean = false
            None => {
              states[id] = 1
              frames.push(self.clean_frame(id))
            }
          }
      }
    }
  }
  states
}

///|
fn QueryContext::clean_frame(self : QueryContext, id : String) -> CleanFrame {
  {
    id,
    steps: self.resolve_steps(id),
    next: 0,
    clean: self.packages.packages.get(id).unwrap().document.field("Conflicts")
    is None,
  }
}
