///|
/// A source location. Columns count Unicode scalar values, starting at one.
#derive(Eq, @debug.Debug)
pub(all) struct Location {
  source : String
  line : Int32
  column : Int32
}

///|
/// Diagnostics are errors in the supported subset, not pkgconf exit codes.
#derive(Eq, @debug.Debug)
pub(all) struct Diagnostic {
  code : String
  message : String
  location : Location
}

///|
#derive(Eq, @debug.Debug)
pub(all) enum EntryKind {
  Variable
  Field
}

///|
/// Original value is retained for explaining substitutions.
#derive(Eq, @debug.Debug)
pub(all) struct Entry {
  kind : EntryKind
  name : String
  raw : String
  value : String
  location : Location
  value_location : Location
}

///|
/// A parsed document. Invalid entries are not available to subsequent queries.
#derive(Eq, @debug.Debug)
pub(all) struct Document {
  entries : Array[Entry]
  diagnostics : Array[Diagnostic]
}

///|
#derive(Eq, @debug.Debug)
pub(all) enum VersionOp {
  Any
  Equal
  NotEqual
  Less
  LessEqual
  Greater
  GreaterEqual
}

///|
/// Version comparison and transitive dependency resolution are later milestones.
#derive(Eq, @debug.Debug)
pub(all) struct Requirement {
  name : String
  op : VersionOp
  version : String
}

///|
pub fn Document::field(self : Document, name : String) -> Entry? {
  for e in self.entries {
    if e.kind == Field && e.name == name {
      return Some(e)
    }
  }
  None
}

///|
pub fn Document::variable(self : Document, name : String) -> Entry? {
  for e in self.entries {
    if e.kind == Variable && e.name == name {
      return Some(e)
    }
  }
  None
}

///|
fn diag(code : String, message : String, location : Location) -> Diagnostic {
  { code, message, location, }
}

///|
fn chars_text(chars : Array[Char], start : Int32, end : Int32) -> String {
  let out = StringBuilder()
  for i = start; i < end; i = i + 1 {
    out.write_char(chars[i])
  }
  out.to_string()
}

///|
fn whitespace(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\r' || c == '\n'
}
