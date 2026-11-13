///|
/// A source location. Columns count Unicode scalar values, starting at one.
#derive(Eq, Hash, @debug.Debug)
pub(all) struct Location {
  source : String
  line : Int32
  column : Int32
}

///|
pub extend Location with Hash::{hash, hash_combine}

///|
/// Diagnostics are errors in the supported subset, not pkgconf exit codes.
#derive(Eq, Hash, @debug.Debug)
pub(all) struct Diagnostic {
  code : String
  message : String
  location : Location
}

///|
pub extend Diagnostic with Hash::{hash, hash_combine}

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
/// A named dependency with an optional version constraint.
#derive(Eq, @debug.Debug)
pub(all) struct Requirement {
  name : String
  op : VersionOp
  version : String
}

///|
pub fn Document::field(self : Document, name : String) -> Entry? {
  let key = field_key(name)
  for e in self.entries {
    if e.kind == Field && field_key(e.name) == key {
      return Some(e)
    }
  }
  None
}

///|
// Only standard fields ignore ASCII case. Extension fields and variables keep
// their spelling, and entries retain the source's original field name.
fn field_key(name : String) -> String {
  for
    known in [
      "Name", "Description", "Version", "URL", "Requires", "Requires.private", "Conflicts",
      "Provides", "Cflags", "Cflags.private", "Libs", "Libs.private",
    ] {
    if name.equal_ignore_ascii_case(known) {
      return known
    }
  }
  name
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
