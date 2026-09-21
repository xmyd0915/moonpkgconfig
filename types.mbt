///|
/// A source location. Columns count Unicode scalar values, starting at one.
pub(all) struct Location {
  source : String
  line : Int
  column : Int
} derive(Eq, @debug.Debug)

///|
/// Diagnostics are errors in the supported subset, not pkgconf exit codes.
pub(all) struct Diagnostic {
  code : String
  message : String
  location : Location
} derive(Eq, @debug.Debug)

///|
pub(all) enum EntryKind {
  Variable
  Field
} derive(Eq, @debug.Debug)

///|
/// Original value is retained for explaining substitutions.
pub(all) struct Entry {
  kind : EntryKind
  name : String
  raw : String
  value : String
  location : Location
  value_location : Location
} derive(Eq, @debug.Debug)

///|
/// A parsed document. Invalid entries are not available to subsequent queries.
pub(all) struct Document {
  entries : Array[Entry]
  diagnostics : Array[Diagnostic]
} derive(Eq, @debug.Debug)

///|
pub(all) enum VersionOp {
  Any
  Equal
  NotEqual
  Less
  LessEqual
  Greater
  GreaterEqual
} derive(Eq, @debug.Debug)

///|
/// Version comparison and transitive dependency resolution are later milestones.
pub(all) struct Requirement {
  name : String
  op : VersionOp
  version : String
} derive(Eq, @debug.Debug)

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
fn chars_text(chars : Array[Char], start : Int, end : Int) -> String {
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
