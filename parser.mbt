///| Expand only variables defined earlier, as pkg-config does.

///|
/// The map can include caller-provided builtins such as pcfiledir.
pub fn expand(
  value : String,
  variables : Map[String, String],
  location~ : Location,
) -> Result[String, Diagnostic] {
  let chars = value.to_array()
  let out = StringBuilder()
  let mut expanded_length = 0
  let mut i = 0
  while i < chars.length() {
    if chars[i] == '$' && i + 1 < chars.length() && chars[i + 1] == '$' {
      out.write_char('$')
      expanded_length = expanded_length + 1
      i = i + 2
    } else if chars[i] == '$' && i + 1 < chars.length() && chars[i + 1] == '{' {
      let start = i
      i = i + 2
      let name_start = i
      while i < chars.length() && chars[i] != '}' {
        i = i + 1
      }
      let at = { ..location, column: location.column + start, }
      if i == chars.length() {
        return Err(diag("PC003", "Unclosed variable reference", at))
      }
      let name = chars_text(chars, name_start, i)
      match variables.get(name) {
        Some(v) => {
          expanded_length = expanded_length + v.length()
          if expanded_length > 1048576 {
            return Err(diag("PC009", "Expanded value exceeds 1 MiB", location))
          }
          out.write_string(v)
        }
        None => return Err(diag("PC004", "Undefined variable: " + name, at))
      }
      i = i + 1
    } else {
      out.write_char(chars[i])
      expanded_length = expanded_length +
        (if chars[i].to_int() > 65535 { 2 } else { 1 })
      i = i + 1
    }
    if expanded_length > 1048576 {
      return Err(diag("PC009", "Expanded value exceeds 1 MiB", location))
    }
  }
  Ok(out.to_string())
}

///|
fn valid_key(name : String) -> Bool {
  !name.is_empty() &&
  name
  .iter()
  .all(c => {
    (c >= 'a' && c <= 'z') ||
    (c >= 'A' && c <= 'Z') ||
    (c >= '0' && c <= '9') ||
    c == '_' ||
    c == '.' ||
    c == '-'
  })
}

///| Parse .pc syntax with ordered substitution, comments and continuations.

///|
/// Deliberately strict about duplicate definitions and undefined variables.
pub fn parse(
  content : String,
  source? : String = "input.pc",
  pcfiledir? : String = ".",
) -> Document {
  let entries : Array[Entry] = []
  let diagnostics : Array[Diagnostic] = []
  let variables : Map[String, String] = { "pcfiledir": pcfiledir }
  let fields : Map[String, Bool] = Map([])
  let chars = content.to_array()
  let line = StringBuilder()
  let mut physical_line = 1
  let mut start_line = 1
  let mut i = if chars.length() > 0 && chars[0] == '\u{FEFF}' { 1 } else { 0 }
  while i < chars.length() {
    let c = chars[i]
    if c == '\\' && i + 1 < chars.length() {
      let next = chars[i + 1]
      if next == '\n' ||
        (next == '\r' && i + 2 < chars.length() && chars[i + 2] == '\n') {
        physical_line = physical_line + 1
        i = i + (if next == '\r' { 3 } else { 2 })
        continue
      }
      // Escaped hashes are literal, other escapes belong to the fragment parser.
      if next == '#' {
        line.write_char('#')
      } else {
        line.write_char(c)
        line.write_char(next)
      }
      i = i + 2
      continue
    }
    if c == '#' {
      while i < chars.length() && chars[i] != '\n' {
        i = i + 1
      }
      continue
    }
    if c == '\n' {
      parse_line(
        line.to_string(),
        source,
        start_line,
        variables,
        fields,
        entries,
        diagnostics,
      )
      line.reset()
      physical_line = physical_line + 1
      start_line = physical_line
    } else {
      line.write_char(c)
    }
    i = i + 1
  }
  parse_line(
    line.to_string(),
    source,
    start_line,
    variables,
    fields,
    entries,
    diagnostics,
  )
  { entries, diagnostics, }
}

///|
fn parse_line(
  text : String,
  source : String,
  line_number : Int,
  variables : Map[String, String],
  fields : Map[String, Bool],
  entries : Array[Entry],
  diagnostics : Array[Diagnostic],
) -> Unit {
  if text.is_blank() {
    return
  }
  let chars = text.to_array()
  let mut start = 0
  while start < chars.length() && whitespace(chars[start]) {
    start = start + 1
  }
  let location = { source, line: line_number, column: start + 1, }
  let mut split = start
  while split < chars.length() && chars[split] != '=' && chars[split] != ':' {
    split = split + 1
  }
  if split == chars.length() {
    diagnostics.push(
      diag("PC001", "Expected variable=value or Field: value", location),
    )
    return
  }
  let name = chars_text(chars, start, split).trim().to_owned()
  if !valid_key(name) {
    diagnostics.push(diag("PC002", "Invalid key: " + name, location))
    return
  }
  let kind = if chars[split] == '=' { Variable } else { Field }
  if (kind == Variable && variables.contains(name)) ||
    (kind == Field && fields.contains(name)) {
    diagnostics.push(
      diag("PC005", "Duplicate or reserved definition: " + name, location),
    )
    return
  }
  let mut value_start = split + 1
  while value_start < chars.length() && whitespace(chars[value_start]) {
    value_start = value_start + 1
  }
  let raw = chars_text(chars, value_start, chars.length()).trim_end().to_owned()
  let value_location = { ..location, column: value_start + 1, }
  match expand(raw, variables, location=value_location) {
    Err(d) => diagnostics.push(d)
    Ok(value) => {
      entries.push({ kind, name, raw, value, location, value_location, })
      match kind {
        Variable => variables[name] = value
        Field => fields[name] = true
      }
    }
  }
}
